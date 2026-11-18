local util = require('markvim.util')
local ts = require('markvim.ts')
local M = {}

local function blank(ctx, row)
  return ctx.line(row):find('^%s*$') ~= nil
end

---True when every row outside [sr, last] is blank, i.e. the buffer is nothing
---but this block (an LSP signature hover, for instance).
local function only_block(ctx, sr, last)
  local n = vim.api.nvim_buf_line_count(ctx.buf)
  if n > 200 then
    return false
  end
  for row = 0, sr - 1 do
    if not blank(ctx, row) then
      return false
    end
  end
  for row = last + 1, n - 1 do
    if not blank(ctx, row) then
      return false
    end
  end
  return true
end

---Hide a fence line, or show it as an empty line when `code.spacing` is on and
---the row next to it (outside the block) holds text.
local function hide_fence(ctx, row, neighbour)
  if ctx.cfg.code.spacing and neighbour >= 0 and neighbour < vim.api.nvim_buf_line_count(ctx.buf) then
    if not blank(ctx, neighbour) then
      ctx.add(row, 0, { end_col = #ctx.line(row), conceal = '' })
      return
    end
  end
  ctx.add(row, 0, { conceal_lines = '' })
  ctx.hidden[row] = true
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.code(ctx, node)
  local cfg = ctx.cfg.code
  local sr, _, er, ec = node:range()
  local last = ec == 0 and er - 1 or er
  if last < sr then
    return
  end
  local lang_node, has_close = nil, false
  for child in node:iter_children() do
    local t = child:type()
    if t == 'info_string' then
      lang_node = child:named_child(0)
    elseif t == 'fenced_code_block_delimiter' then
      local dr = child:range()
      if dr > sr then
        has_close = true
      end
    end
  end
  local lang = lang_node and ts.text(ctx, lang_node) or nil
  if lang == '' then
    lang = nil
  end
  local first = sr + 1
  local lastc = has_close and last - 1 or last

  local diagram_cfg = ctx.cfg.diagram
  local diagram_lang = lang and lang:lower()
  if diagram_lang and diagram_cfg.enabled and diagram_cfg.backend ~= 'none' and diagram_cfg.languages[diagram_lang] then
    local handled = require('markvim.diagram').render_block(ctx, node, diagram_lang, {
      top = sr,
      bottom = last,
      first = first,
      last = lastc,
    })
    if handled then
      return
    end
  end

  ctx.blocks[#ctx.blocks + 1] = { sr, last }
  local bg = cfg.background
  if bg == 'buffer' then
    bg = not ctx.float
  elseif bg == 'auto' then
    bg = not (ctx.float and only_block(ctx, sr, last))
  end
  local pad = cfg.left_pad > 0 and { { (' '):rep(cfg.left_pad), bg and 'MarkvimCode' or nil } } or nil
  for row = first, lastc do
    if bg then
      ctx.fix(row, 0, { line_hl_group = 'MarkvimCode' })
    end
    if pad then
      ctx.fix(row, 0, { virt_text = pad, virt_text_pos = 'inline' })
    end
  end

  local label
  if cfg.language and lang then
    label = {}
    local icon, ihl
    if cfg.language_icon and ctx.cfg.icons ~= 'ascii' then
      icon, ihl = require('markvim.icons').language(lang)
    end
    if icon then
      label[#label + 1] = { icon .. ' ', ihl or 'MarkvimCodeInfo' }
    end
    label[#label + 1] = { lang, 'MarkvimCodeInfo' }
  end

  -- Right-aligned label on the first content row it does not collide with
  -- (a wide row wraps and the label would cover text); as a last resort put
  -- it after the text of the first row.
  local function place_label()
    local w = 0
    for _, chunk in ipairs(label) do
      w = w + util.strwidth(chunk[1])
    end
    for row = first, math.min(lastc, first + 8) do
      if ctx.width_of(row, 0, #ctx.line(row)) + w + 1 <= ctx.width then
        ctx.fix(row, 0, { virt_text = label, virt_text_pos = 'right_align', hl_mode = 'combine' })
        return
      end
    end
    ctx.fix(first, 0, { virt_text = label, virt_text_pos = 'eol', hl_mode = 'combine' })
  end

  if cfg.border == 'hide' then
    hide_fence(ctx, sr, sr - 1)
    if has_close then
      hide_fence(ctx, last, last + 1)
    end
    if label and first <= lastc then
      place_label()
    end
  elseif cfg.border == 'thin' then
    local h = ctx.icons.rule
    local top_line = ctx.line(sr)
    local text, used = {}, 0
    if label and cfg.language_pos == 'left' then
      text[#text + 1] = { h .. ' ', 'MarkvimCodeBorder' }
      used = used + 2
      for _, chunk in ipairs(label) do
        text[#text + 1] = chunk
        used = used + util.strwidth(chunk[1])
      end
      text[#text + 1] = { ' ', 'MarkvimCodeBorder' }
      used = used + 1
    end
    text[#text + 1] = { util.fill(h, ctx.width - used), 'MarkvimCodeBorder' }
    ctx.add(sr, 0, { end_col = #top_line, conceal = '' })
    ctx.add(sr, 0, { virt_text = text, virt_text_pos = 'inline' })
    if label and cfg.language_pos ~= 'left' then
      ctx.add(sr, 0, { virt_text = label, virt_text_pos = 'right_align' })
    end
    if has_close then
      local bottom = ctx.line(last)
      ctx.add(last, 0, { end_col = #bottom, conceal = '' })
      ctx.add(last, 0, {
        virt_text = { { util.fill(h, ctx.width), 'MarkvimCodeBorder' } },
        virt_text_pos = 'inline',
      })
    end
  elseif label and first <= lastc then
    place_label()
  end
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.code_indent(ctx, node)
  if not ctx.cfg.code.indented then
    return
  end
  local sr, _, er, ec = node:range()
  local last = ec == 0 and er - 1 or er
  for row = sr, last do
    ctx.fix(row, 0, { line_hl_group = 'MarkvimCode' })
  end
end

return M
