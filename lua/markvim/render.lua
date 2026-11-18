-- Rendering engine.
--
-- Design (see doc/ARCHITECTURE.md):
--  * Only the visible rows (plus a margin) of each window are parsed and decorated.
--  * Decorations are persistent extmarks in two namespaces per "view":
--      ns        marks removed from the cursor row in live mode (conceal, icons, ...)
--      ns_fixed  marks that always stay (backgrounds, virtual lines)
--  * A view is a namespace pair optionally scoped to specific windows through
--    `nvim__ns_set`, which is how split mode shows raw text and a rendered
--    preview of the *same* buffer without copying anything.
--  * Marks of the last render are cached per row, so moving the cursor only
--    deletes/restores the marks of two rows.
local api = vim.api
local state = require('markvim.state')
local config = require('markvim.config')
local util = require('markvim.util')
local ts = require('markvim.ts')
local compute = require('markvim.compute')

local M = {}

-- Views ---------------------------------------------------------------------

local function windows_of(buf, view)
  if view.wins then
    local out = {}
    for _, w in ipairs(view.wins) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == buf then
        out[#out + 1] = w
      end
    end
    return out
  end
  return vim.fn.win_findbuf(buf)
end

-- Expand a cursor row to the enclosing raw block, if any.
local function expand(rows, row, blocks)
  for _, b in ipairs(blocks) do
    if row >= b[1] and row <= b[2] then
      for r = b[1], b[2] do
        rows[r] = true
      end
      return
    end
  end
end

---Rows that must be shown raw for a view (cursor rows of its windows).
---@return table<integer, boolean>
local function raw_rows(buf, view, blocks)
  local rows = {}
  if not view.hybrid then
    return rows
  end
  for _, win in ipairs(windows_of(buf, view)) do
    local row = api.nvim_win_get_cursor(win)[1] - 1
    rows[row] = true
    if blocks then
      expand(rows, row, blocks)
    end
  end
  return rows
end

local set_extmark = api.nvim_buf_set_extmark

local function block_is_raw(raw, block)
  for row = block[1], block[2] do
    if raw[row] then
      return true
    end
  end
  return false
end

---Realize the computed marks of `ctx` into a view's namespaces.
local function apply(buf, view, ctx, tick)
  api.nvim_buf_clear_namespace(buf, view.ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, view.ns_fixed, 0, -1)
  local ns, ns_fixed = view.ns, view.ns_fixed
  for row, list in pairs(ctx.fixed) do
    for i = 1, #list do
      local m = list[i]
      set_extmark(buf, ns_fixed, row, m[1], m[2])
    end
  end
  local blocks = ctx.raw_blocks
  if ctx.cfg.live.context == 'block' then
    blocks = vim.list_extend(vim.list_slice(blocks), ctx.blocks)
  end
  if #blocks == 0 then
    blocks = nil
  end
  local raw = raw_rows(buf, view, blocks)
  for row, list in pairs(ctx.main) do
    if not raw[row] then
      for i = 1, #list do
        local m = list[i]
        set_extmark(buf, ns, row, m[1], m[2])
      end
    end
  end
  view.conditional = {}
  for _, mark in ipairs(ctx.conditional) do
    local entry = { mark = mark }
    if not block_is_raw(raw, mark.block) then
      entry.id = set_extmark(buf, ns, mark.row, mark.col, mark.opts)
    end
    view.conditional[#view.conditional + 1] = entry
  end
  view.rows = ctx.main
  view.blocks = blocks
  view.raw = raw
  view.tick = tick
end

---Update the raw (un-rendered) rows of all hybrid views after a cursor move.
---@param buf integer
function M.cursor(buf)
  local s = state.get(buf)
  if not s or not s.enabled then
    return
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  for _, view in ipairs(s.views) do
    if view.hybrid and view.rows then
      local new = raw_rows(buf, view, view.blocks)
      local old = view.raw
      local valid = view.tick == tick
      for row in pairs(old) do
        if not new[row] and valid then
          local list = view.rows[row]
          if list then
            for i = 1, #list do
              local m = list[i]
              set_extmark(buf, view.ns, row, m[1], m[2])
            end
          end
        end
      end
      for row in pairs(new) do
        if not old[row] then
          api.nvim_buf_clear_namespace(buf, view.ns, row, row + 1)
        end
      end
      for _, entry in ipairs(view.conditional or {}) do
        local show = not block_is_raw(new, entry.mark.block)
        if show and not entry.id and valid then
          entry.id = set_extmark(buf, view.ns, entry.mark.row, entry.mark.col, entry.mark.opts)
        elseif not show and entry.id then
          pcall(api.nvim_buf_del_extmark, buf, view.ns, entry.id)
          entry.id = nil
        end
      end
      view.raw = new
    end
  end
end

-- Viewport ------------------------------------------------------------------

---@return integer[][] visible, integer[][] padded
local function viewport(buf, wins, margin)
  local line_count = api.nvim_buf_line_count(buf)
  local visible, padded = {}, {}
  for _, win in ipairs(wins) do
    local top = vim.fn.line('w0', win) - 1
    local bot = vim.fn.line('w$', win) - 1
    local height = api.nvim_win_get_height(win)
    if bot < top then
      bot = top
    end
    -- `w$` is not reliable before the first draw; cover the window height.
    bot = math.min(line_count - 1, math.max(bot, top + height - 1))
    visible[#visible + 1] = { top, bot }
    padded[#padded + 1] = { math.max(0, top - margin), math.min(line_count - 1, bot + margin) }
  end
  return util.merge_ranges(visible), util.merge_ranges(padded)
end

local function covered(rendered, visible)
  for _, v in ipairs(visible) do
    local ok = false
    for _, r in ipairs(rendered) do
      if v[1] >= r[1] and v[2] <= r[2] then
        ok = true
        break
      end
    end
    if not ok then
      return false
    end
  end
  return true
end

local function min_width(wins)
  local w = math.huge
  for _, win in ipairs(wins) do
    w = math.min(w, util.text_width(win))
  end
  return w
end

local function set_win_option(win, name, value)
  api.nvim_set_option_value(name, value, { win = win, scope = 'local' })
end

---Make sure every window showing the buffer has the right conceal options.
local function ensure_win_options(s, wins, cfg)
  for _, win in ipairs(wins) do
    if not s.win_opts[win] then
      s.win_opts[win] = {
        conceallevel = api.nvim_get_option_value('conceallevel', { win = win }),
        concealcursor = api.nvim_get_option_value('concealcursor', { win = win }),
      }
      local raw_edit = s.mode == 'split' and cfg.split.edit == 'raw' and (not s.split or win ~= s.split.win)
      if not raw_edit then
        set_win_option(win, 'conceallevel', cfg.win_options.conceallevel)
        local preview = s.mode == 'preview' or (s.split and win == s.split.win)
        set_win_option(win, 'concealcursor', preview and 'nvic' or '')
      end
    end
  end
end

-- Render --------------------------------------------------------------------

---Render the visible area of `buf`. Cheap when nothing changed.
---@param buf integer
---@param force boolean|nil
function M.render(buf, force)
  local s = state.get(buf)
  if not s or not s.enabled or not api.nvim_buf_is_valid(buf) then
    return
  end
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    return
  end
  local t0 = util.now()
  local cfg = config.get()
  ensure_win_options(s, wins, cfg)
  local tick = api.nvim_buf_get_changedtick(buf)
  local visible, padded = viewport(buf, wins, cfg.margin)
  if not force and s.rendered and s.rendered.tick == tick and covered(s.rendered.ranges, visible) then
    M.cursor(buf)
    return
  end
  local t1 = util.now()
  local ctx = compute(buf, s, cfg, padded, min_width(wins))
  if not ctx then
    return
  end
  local t2 = util.now()
  for _, view in ipairs(s.views) do
    apply(buf, view, ctx, tick)
  end
  local t3 = util.now()
  s.rendered = { ranges = padded, tick = tick }
  s.diagram_blocks = ctx.diagram_blocks
  s.stats = {
    viewport_ms = t1 - t0,
    compute_ms = t2 - t1,
    apply_ms = t3 - t2,
    total_ms = t3 - t0,
    phases = ctx.phases,
    marks = ctx.count,
    ranges = padded,
  }
end

---Debounced render.
---@param buf integer
---@param delay integer|nil ms; defaults from config by mode
function M.schedule(buf, delay)
  local s = state.get(buf)
  if not s or not s.enabled then
    return
  end
  if not delay then
    local cfg = config.get().debounce
    delay = api.nvim_get_mode().mode:sub(1, 1) == 'i' and cfg.insert or cfg.normal
  end
  if delay <= 0 then
    M.render(buf)
    return
  end
  local timer = s.timer
  if not timer then
    timer = vim.uv.new_timer()
    s.timer = timer
  end
  timer:stop()
  timer:start(delay, 0, function()
    vim.schedule(function()
      M.render(buf)
    end)
  end)
end

-- Window options ------------------------------------------------------------

local function restore_win_options(s)
  for win, opts in pairs(s.win_opts) do
    if api.nvim_win_is_valid(win) then
      pcall(set_win_option, win, 'conceallevel', opts.conceallevel)
      pcall(set_win_option, win, 'concealcursor', opts.concealcursor)
    end
  end
  s.win_opts = {}
end

-- Namespaces / modes --------------------------------------------------------

local function ns_for(buf, name)
  return api.nvim_create_namespace(('markvim:%d:%s'):format(buf, name))
end

local function clear_views(buf, views)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  for _, view in ipairs(views) do
    api.nvim_buf_clear_namespace(buf, view.ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, view.ns_fixed, 0, -1)
  end
end

local function close_split(buf, s)
  local split = s.split
  if not split then
    return
  end
  s.split = nil
  -- Un-scope namespaces so a later split can re-scope them cleanly.
  for _, view in ipairs(s.views) do
    if view.wins then
      pcall(api.nvim__ns_set, view.ns, { wins = {} })
      pcall(api.nvim__ns_set, view.ns_fixed, { wins = {} })
    end
  end
  if api.nvim_win_is_valid(split.src_win) then
    pcall(set_win_option, split.src_win, 'scrollbind', false)
  end
  if api.nvim_win_is_valid(split.win) then
    pcall(api.nvim_win_close, split.win, true)
  end
  pcall(api.nvim_del_augroup_by_name, 'markvim.split.' .. buf)
end

local function open_split(buf, s)
  local cfg = config.get().split
  local src_win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(src_win) ~= buf then
    src_win = vim.fn.win_findbuf(buf)[1]
  end
  local vertical = cfg.position == 'left' or cfg.position == 'right'
  local total = vertical and api.nvim_win_get_width(src_win) or api.nvim_win_get_height(src_win)
  local size = cfg.size < 1 and math.floor(total * cfg.size) or math.floor(cfg.size)
  local win_cfg = { split = cfg.position, win = src_win }
  if vertical then
    win_cfg.width = size
  else
    win_cfg.height = size
  end
  local win = api.nvim_open_win(buf, false, win_cfg)
  set_win_option(win, 'conceallevel', config.get().win_options.conceallevel)
  set_win_option(win, 'concealcursor', 'nvic')
  set_win_option(win, 'cursorline', false)
  if cfg.scrollbind then
    set_win_option(win, 'scrollbind', true)
    set_win_option(src_win, 'scrollbind', true)
    vim.cmd('syncbind')
  end
  s.split = { win = win, src_win = src_win }
  s.win_opts[win] = s.win_opts[win] or { conceallevel = 0, concealcursor = '' }
  local group = api.nvim_create_augroup('markvim.split.' .. buf, { clear = true })
  api.nvim_create_autocmd('WinClosed', {
    group = group,
    pattern = { tostring(win), tostring(src_win) },
    callback = function()
      vim.schedule(function()
        if state.get(buf) and state.get(buf).split then
          M.set_mode(buf, 'live')
        end
      end)
    end,
  })
end

---Build the views for the buffer's current mode.
local function build_views(buf, s)
  local cfg = config.get()
  local views = {}
  if s.mode == 'split' and s.split then
    views[#views + 1] = {
      ns = ns_for(buf, 'preview'),
      ns_fixed = ns_for(buf, 'preview_fixed'),
      wins = { s.split.win },
      hybrid = false,
    }
    api.nvim__ns_set(views[1].ns, { wins = { s.split.win } })
    api.nvim__ns_set(views[1].ns_fixed, { wins = { s.split.win } })
    if cfg.split.edit == 'live' then
      local v = {
        ns = ns_for(buf, 'edit'),
        ns_fixed = ns_for(buf, 'edit_fixed'),
        wins = { s.split.src_win },
        hybrid = true,
      }
      api.nvim__ns_set(v.ns, { wins = { s.split.src_win } })
      api.nvim__ns_set(v.ns_fixed, { wins = { s.split.src_win } })
      views[#views + 1] = v
    end
  else
    views[1] = {
      ns = ns_for(buf, 'main'),
      ns_fixed = ns_for(buf, 'fixed'),
      hybrid = s.mode == 'live',
    }
  end
  for _, v in ipairs(views) do
    v.raw = {}
  end
  s.views = views
end

---@param buf integer
---@param mode 'live'|'preview'|'split'
function M.set_mode(buf, mode)
  local s = state.get(buf)
  if not s then
    return
  end
  if mode ~= 'live' and mode ~= 'preview' and mode ~= 'split' then
    error(('markvim: unknown mode %q'):format(tostring(mode)))
  end
  if mode == 'split' and s.float then
    mode = 'preview'
  end
  close_split(buf, s)
  clear_views(buf, s.views)
  restore_win_options(s)
  s.mode = mode
  s.rendered = nil
  if mode == 'split' then
    open_split(buf, s)
  end
  build_views(buf, s)
  if not s.enabled then
    -- Selecting a mode updates window options even when marks are disabled.
    ensure_win_options(s, vim.fn.win_findbuf(buf), config.get())
  end
  M.render(buf, true)
end

-- Attach / detach -----------------------------------------------------------

local global_group

local function setup_global_autocmds()
  if global_group then
    return
  end
  global_group = api.nvim_create_augroup('markvim.global', { clear = true })
  api.nvim_create_autocmd('WinScrolled', {
    group = global_group,
    callback = function()
      for key, ev in pairs(vim.v.event) do
        if key ~= 'all' then
          local win = tonumber(key)
          if win and api.nvim_win_is_valid(win) and (ev.topline ~= 0 or ev.height ~= 0 or ev.width ~= 0) then
            local buf = api.nvim_win_get_buf(win)
            if state.get(buf) then
              M.render(buf)
            end
          end
        end
      end
    end,
  })
  -- Diagram colors depend on 'background'; re-render everything when it flips.
  api.nvim_create_autocmd('OptionSet', {
    group = global_group,
    pattern = 'background',
    callback = function()
      for buf in pairs(state.buffers) do
        M.invalidate(buf)
      end
    end,
  })
  api.nvim_create_autocmd('WinResized', {
    group = global_group,
    callback = function()
      for _, win in ipairs(vim.v.event.windows or {}) do
        if api.nvim_win_is_valid(win) then
          local buf = api.nvim_win_get_buf(win)
          if state.get(buf) then
            M.render(buf, true)
          end
        end
      end
    end,
  })
end

---@param buf integer
---@return boolean attached
function M.attach(buf)
  if state.get(buf) then
    return true
  end
  if not api.nvim_buf_is_valid(buf) then
    return false
  end
  local bt = vim.bo[buf].buftype
  if bt == 'terminal' or bt == 'prompt' or bt == 'quickfix' then
    return false
  end
  local cfg = config.get()
  if not cfg.enabled then
    return false
  end
  local name = api.nvim_buf_get_name(buf)
  if name ~= '' and vim.fn.getfsize(name) > cfg.max_file_size then
    return false
  end
  local parser = ts.parser(buf)
  if not parser then
    vim.notify_once('markvim: no markdown treesitter parser available', vim.log.levels.WARN)
    return false
  end
  require('markvim.hl').setup()
  setup_global_autocmds()
  if cfg.code.border ~= 'none' then
    -- markvim hides (or spaces / borders) fence lines itself.
    local compat = require('markvim.compat')
    if compat.keep_fence_lines() then
      compat.restart_highlighter(buf)
    end
  end

  local s = state.new(buf)
  s.parser = parser
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if util.is_float(win) then
      s.float = true
    end
  end
  local mode = vim.b[buf].markvim_mode or (s.float and cfg.float_mode or cfg.mode)

  local group = api.nvim_create_augroup('markvim.buf.' .. buf, { clear = true })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    buffer = buf,
    callback = function()
      M.schedule(buf)
    end,
  })
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    buffer = buf,
    callback = function()
      M.cursor(buf)
    end,
  })
  api.nvim_create_autocmd('InsertLeave', {
    group = group,
    buffer = buf,
    callback = function()
      M.schedule(buf, 0)
    end,
  })
  api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    buffer = buf,
    callback = function()
      M.render(buf)
    end,
  })
  api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      M.detach(buf)
    end,
  })

  M.set_mode(buf, mode)
  local open_key = cfg.diagram.enabled and cfg.diagram.keys and cfg.diagram.keys.open
  if open_key and not s.float and vim.bo[buf].buftype == '' then
    vim.keymap.set('n', open_key, function()
      if not require('markvim.diagram').open_at(buf) then
        -- Not on a diagram: do what the key normally does.
        api.nvim_feedkeys(vim.keycode(open_key), 'n', false)
      end
    end, { buffer = buf, desc = 'markvim: open diagram in a panel' })
    s.open_key = open_key
  end
  if type(cfg.on_attach) == 'function' then
    cfg.on_attach(buf)
  end
  return true
end

---@param buf integer
function M.detach(buf)
  local s = state.get(buf)
  if not s then
    return
  end
  close_split(buf, s)
  clear_views(buf, s.views)
  restore_win_options(s)
  if s.open_key then
    pcall(vim.keymap.del, 'n', s.open_key, { buffer = buf })
  end
  if s.panel and s.panel.close then
    s.panel:close()
  end
  pcall(api.nvim_del_augroup_by_name, 'markvim.buf.' .. buf)
  state.remove(buf)
end

---@param buf integer
---@param enabled boolean
function M.set_enabled(buf, enabled)
  local s = state.get(buf)
  if not s then
    if enabled then
      M.attach(buf)
    end
    return
  end
  if s.enabled == enabled then
    return
  end
  if enabled then
    s.enabled = true
    s.rendered = nil
    M.render(buf, true)
  else
    s.enabled = false
    if s.timer then
      s.timer:stop()
    end
    close_split(buf, s)
    clear_views(buf, s.views)
    restore_win_options(s)
    s.rendered = nil
    if s.mode == 'split' then
      s.mode = 'live'
      build_views(buf, s)
    end
  end
end

---@param buf integer
function M.toggle(buf)
  local s = state.get(buf)
  M.set_enabled(buf, not (s and s.enabled))
end

---Called by async producers (diagrams) when new data for a buffer is available.
---@param buf integer
function M.invalidate(buf)
  local s = state.get(buf)
  if s then
    s.rendered = nil
    M.schedule(buf, 0)
  end
end

return M
