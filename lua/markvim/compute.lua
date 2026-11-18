-- Build marks from Tree-sitter captures. Applying them to windows is render.lua's job.
local api = vim.api
local ts = require('markvim.ts')
local util = require('markvim.util')

---@class markvim.Mark
---@field [1] integer col
---@field [2] table extmark opts

-- Ordered to keep generated queries deterministic.
-- Each group maps a configuration section to a renderer and its capture patterns.
local groups = {
  markdown = {
    { option = 'heading', module = 'heading', captures = { { 'heading', '[(atx_heading) (setext_heading)]' } } },
    {
      option = 'code',
      module = 'code',
      captures = {
        { 'code', '(fenced_code_block)' },
        { 'code_indent', '(indented_code_block)' },
      },
    },
    { option = 'bullet', module = 'list', captures = { { 'list_item', '(list_item)' } } },
    { option = 'quote', module = 'quote', captures = { { 'quote', '(block_quote)' } } },
    { option = 'table', module = 'table', captures = { { 'table', '(pipe_table)' } } },
    { option = 'rule', module = 'rule', captures = { { 'rule', '(thematic_break)' } } },
    { option = 'html', module = 'html', captures = { { 'html', '(html_block)' } } },
  },
  markdown_inline = {
    {
      option = 'inline',
      module = 'inline',
      captures = {
        { 'code_span', '(code_span)' },
        { 'emphasis', '[(emphasis) (strong_emphasis)]' },
        { 'strike', '(strikethrough)' },
        { 'escape', '(backslash_escape)' },
        { 'latex', '(latex_block)' },
        { 'html_tag', '(html_tag)' },
        { 'hard_break', '(hard_line_break)' },
      },
    },
    {
      option = 'link',
      module = 'link',
      captures = {
        { 'link', '(inline_link)' },
        { 'image', '(image)' },
        { 'shortcut', '(shortcut_link)' },
        { 'ref_link', '[(full_reference_link) (collapsed_reference_link)]' },
        { 'autolink', '[(uri_autolink) (email_autolink)]' },
      },
    },
  },
}

local modules_by_capture = {}
for _, language_groups in pairs(groups) do
  for _, group in ipairs(language_groups) do
    for _, capture in ipairs(group.captures) do
      modules_by_capture[capture[1]] = group.module
    end
  end
end

local loaded_modules = {}

local function element_module(name)
  local mod = loaded_modules[name]
  if not mod then
    mod = require('markvim.elements.' .. name)
    loaded_modules[name] = mod
  end
  return mod
end

local queries = { markdown = {}, markdown_inline = {} }

---Build or reuse the query for the enabled sections of a language.
---@param lang 'markdown'|'markdown_inline'
---@param cfg markvim.Config
---@return vim.treesitter.Query|nil
local function query_for(lang, cfg)
  local enabled = {}
  local language_groups = groups[lang]
  for i, group in ipairs(language_groups) do
    local section = cfg[group.option]
    if section and section.enabled ~= false then
      enabled[#enabled + 1] = i
    end
  end
  if #enabled == 0 then
    return nil
  end

  local key = table.concat(enabled, ',')
  local query = queries[lang][key]
  if not query then
    local patterns = {}
    for _, i in ipairs(enabled) do
      for _, capture in ipairs(language_groups[i].captures) do
        local name, pattern = capture[1], capture[2]
        patterns[#patterns + 1] = pattern .. ' @' .. name
      end
    end
    query = vim.treesitter.query.parse(lang, table.concat(patterns, '\n'))
    queries[lang][key] = query
  end
  return query
end

-- Context -------------------------------------------------------------------

---@class markvim.ConditionalMark
---@field row integer
---@field col integer
---@field opts table extmark opts
---@field block integer[] inclusive source rows

---@class markvim.Ctx
---@field buf integer
---@field cfg markvim.Config
---@field icons table
---@field width integer usable text width of the narrowest window
---@field float boolean
---@field main table<integer, markvim.Mark[]>
---@field fixed table<integer, markvim.Mark[]>
---@field conditional markvim.ConditionalMark[] marks shown unless their source block is raw
---@field blocks integer[][] {srow, erow} of block elements (for live.context = 'block')
---@field raw_blocks integer[][] blocks that are always shown raw as a whole when the cursor is inside
---@field hidden table<integer, boolean> rows hidden with conceal_lines
---@field diagram_blocks markvim.DiagramBlock[]
---@field count integer
---@field phases table<string, number>
---@field set_lines fun(top: integer, lines: string[])
---@field line fun(row: integer): string
---@field add fun(row: integer, col: integer, opts: table)
---@field fix fun(row: integer, col: integer, opts: table)
---@field add_conditional fun(row: integer, col: integer, opts: table, block: integer[])
---@field adjust fun(row: integer, col: integer, delta: integer)
---@field conceal fun(row: integer, scol: integer, ecol: integer)
---@field width_of fun(row: integer, scol: integer, ecol: integer): integer

local function new_ctx(buf, cfg, width, float)
  local ctx = {
    buf = buf,
    cfg = cfg,
    icons = require('markvim.icons').get(cfg.icons),
    width = width,
    float = float,
    main = {},
    fixed = {},
    conditional = {},
    blocks = {},
    raw_blocks = {},
    hidden = {},
    diagram_blocks = {},
    count = 0,
  }
  local lines, base = {}, 0
  function ctx.set_lines(top, l)
    lines, base = l, top
  end
  function ctx.line(row)
    local l = lines[row - base + 1]
    if l == nil then
      l = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
    end
    return l
  end
  local main, fixed = ctx.main, ctx.fixed
  function ctx.add(row, col, opts)
    local list = main[row]
    if not list then
      list = {}
      main[row] = list
    end
    list[#list + 1] = { col, opts }
    ctx.count = ctx.count + 1
  end
  function ctx.fix(row, col, opts)
    local list = fixed[row]
    if not list then
      list = {}
      fixed[row] = list
    end
    list[#list + 1] = { col, opts }
    ctx.count = ctx.count + 1
  end
  function ctx.add_conditional(row, col, opts, block)
    ctx.conditional[#ctx.conditional + 1] = { row = row, col = col, opts = opts, block = block }
    ctx.count = ctx.count + 1
  end
  local adjustments = {} -- row -> flat list of col, delta pairs
  function ctx.adjust(row, col, delta)
    local list = adjustments[row]
    if not list then
      list = {}
      adjustments[row] = list
    end
    list[#list + 1] = col
    list[#list + 1] = delta
  end
  -- Record the width adjustment together with the inline conceal.
  function ctx.conceal(row, scol, ecol)
    if ecol > scol then
      ctx.add(row, scol, { end_col = ecol, conceal = '' })
      ctx.adjust(row, scol, scol - ecol)
    end
  end
  -- Display width of a byte range of a row after conceals/inserted icons.
  function ctx.width_of(row, scol, ecol)
    local w = api.nvim_strwidth(ctx.line(row):sub(scol + 1, ecol))
    local list = adjustments[row]
    if list then
      for i = 1, #list, 2 do
        local c = list[i]
        if c >= scol and c < ecol then
          w = w + list[i + 1]
        end
      end
    end
    return w
  end
  return ctx
end

local INLINE_REGION_QUERY = '[(inline) (pipe_table_cell)] @region'

---Parse the inline regions inside `ranges` with the buffer's private
---markdown_inline tree and return its trees (nil when there are none).
---@return table<integer, TSTree>|nil
local function inline_trees_for(buf, s, root, ranges)
  local tick = api.nvim_buf_get_changedtick(buf)
  local lt = s.inline
  if s.inline_tick == tick and vim.deep_equal(s.inline_ranges, ranges) then
    return s.inline_trees
  end
  if lt and s.inline_tick ~= tick then
    -- The private tree gets no edit notifications.
    lt:invalidate()
  end
  s.inline_tick, s.inline_ranges, s.inline_trees = tick, ranges, nil

  local q = vim.treesitter.query.parse('markdown', INLINE_REGION_QUERY)
  local regions = {}
  for _, r in ipairs(ranges) do
    for _, node in q:iter_captures(root, buf, r[1], r[2] + 1) do
      local sr, sc, er, ec = node:range()
      local count = node:named_child_count()
      if count == 0 then
        regions[#regions + 1] = { { sr, sc, er, ec } }
      else
        -- Exclude named children (block continuation markers such as `> `),
        -- exactly like the injection machinery does.
        local list = {}
        local row, col = sr, sc
        for i = 0, count - 1 do
          local csr, csc, cer, cec = node:named_child(i):range()
          if csr > row or (csr == row and csc > col) then
            list[#list + 1] = { row, col, csr, csc }
          end
          row, col = cer, cec
        end
        if er > row or (er == row and ec > col) then
          list[#list + 1] = { row, col, er, ec }
        end
        if #list > 0 then
          regions[#regions + 1] = list
        end
      end
    end
  end
  if #regions == 0 then
    return nil -- never parse with zero regions: that would mean "whole buffer"
  end
  if not lt then
    lt = require('vim.treesitter.languagetree').new(buf, 'markdown_inline', { injections = { markdown_inline = '' } })
    s.inline = lt
  end
  lt:set_included_regions(regions)
  s.inline_trees = lt:parse(true)
  return s.inline_trees
end

-- Compute -------------------------------------------------------------------

---Run the queries over `ranges` and collect marks into a context.
---@param buf integer
---@param s markvim.BufState
---@param cfg markvim.Config
---@param ranges integer[][] inclusive 0-based row ranges
---@param width integer
---@return markvim.Ctx|nil
local function compute(buf, s, cfg, ranges, width)
  local parser = s.parser
  if not parser then
    parser = ts.parser(buf)
    if not parser then
      return nil
    end
    s.parser = parser
  end
  local ctx = new_ctx(buf, cfg, width, s.float)
  local block_q = query_for('markdown', cfg)
  local inline_q = query_for('markdown_inline', cfg)

  local phases = {}
  ctx.phases = phases
  local t0 = util.now()
  -- Only the block tree is needed here. Leave injections to the highlighter.
  local trees = parser:parse()
  local root = trees and trees[1] and trees[1]:root()
  if not root then
    return nil
  end
  phases.parse = util.now() - t0
  -- Inline content is parsed with a private markdown_inline tree restricted to
  -- the inline regions of the visible rows. The shared parser's injected child
  -- can hold a tree per paragraph of the whole file (see ARCHITECTURE.md), which
  -- makes every iteration and edit O(file); this keeps it O(viewport).
  t0 = util.now()
  local inline_trees = inline_q and inline_trees_for(buf, s, root, ranges) or nil
  phases.inline_parse = util.now() - t0
  t0 = util.now()

  for _, r in ipairs(ranges) do
    local top, bot = r[1], r[2]
    ctx.set_lines(top, api.nvim_buf_get_lines(buf, top, bot + 1, false))
    -- Inline first: tables need the width adjustments produced here.
    if inline_trees then
      local captures = inline_q.captures
      for _, tree in pairs(inline_trees) do
        local iroot = tree:root()
        local sr, _, er = iroot:range()
        if er >= top and sr <= bot then
          for id, node in inline_q:iter_captures(iroot, buf, math.max(sr, top), math.min(er, bot) + 1) do
            local cap = captures[id]
            element_module(modules_by_capture[cap])[cap](ctx, node)
          end
        end
      end
    end
    if block_q then
      local captures = block_q.captures
      for id, node in block_q:iter_captures(root, buf, top, bot + 1) do
        local cap = captures[id]
        element_module(modules_by_capture[cap])[cap](ctx, node)
      end
    end
  end
  phases.elements = util.now() - t0
  return ctx
end

return compute
