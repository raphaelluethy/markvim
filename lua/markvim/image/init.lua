-- Terminal image support (kitty graphics protocol with Unicode placeholders).
-- Only loaded when a diagram is rendered as an image.
local api = vim.api
local config = require('markvim.config')
local M = {}

local detected -- cached terminal detection

---@class markvim.TermInfo
---@field supported boolean
---@field name string
---@field remote boolean
---@field tmux boolean

---Detect terminal capabilities from the environment (no round-trips).
---@return markvim.TermInfo
function M.detect()
  if detected then
    return detected
  end
  local env = vim.env
  local prog = (env.TERM_PROGRAM or ''):lower()
  local term = (env.TERM or ''):lower()
  local info = {
    supported = false,
    name = prog ~= '' and prog or term,
    remote = env.SSH_TTY ~= nil or env.SSH_CLIENT ~= nil,
    tmux = env.TMUX ~= nil,
  }
  local tmux_client
  if info.tmux then
    local res = vim.system({ 'tmux', 'display-message', '-p', '#{client_termname}' }, { text = true }):wait()
    tmux_client = res.code == 0 and vim.trim(res.stdout or ''):lower() or ''
  end
  local function is(name)
    return prog:find(name, 1, true) or term:find(name, 1, true) or (tmux_client and tmux_client:find(name, 1, true))
  end
  if env.KITTY_WINDOW_ID or is('kitty') then
    info.supported, info.name = true, 'kitty'
  elseif env.GHOSTTY_RESOURCES_DIR or is('ghostty') then
    info.supported, info.name = true, 'ghostty'
  elseif is('iterm') then
    info.supported, info.name = true, 'iterm2'
  elseif env.KONSOLE_VERSION then
    info.supported, info.name = false, 'konsole' -- placeholders unverified
  elseif is('wezterm') or env.WEZTERM_EXECUTABLE then
    info.supported, info.name = false, 'wezterm' -- no Unicode placeholder support
  end
  if env.MARKVIM_IMAGES == '1' then
    info.supported = true
  elseif env.MARKVIM_IMAGES == '0' then
    info.supported = false
  end
  if info.tmux and info.supported then
    -- Ask tmux to pass the graphics escapes through.
    vim.system({ 'tmux', 'set', '-p', 'allow-passthrough', 'all' }):wait()
  end
  detected = info
  return info
end

---@return boolean
function M.available()
  local b = config.get().image.backend
  if b == false or b == 'none' then
    return false
  end
  if b == 'kitty' then
    return true
  end
  return M.detect().supported and api.nvim_ui_send ~= nil
end

local cell_cache

---Pixel size of a terminal cell: ioctl(TIOCGWINSZ) through LuaJIT ffi, with a fallback.
---@return number width, number height
function M.cell_size()
  if cell_cache then
    return cell_cache[1], cell_cache[2]
  end
  local cfg = config.get().image.cell
  local w, h = cfg.width, cfg.height
  local ok = pcall(function()
    local ffi = require('ffi')
    pcall(
      ffi.cdef,
      [[
      typedef struct { unsigned short ws_row; unsigned short ws_col; unsigned short ws_xpixel; unsigned short ws_ypixel; } markvim_winsize;
      int ioctl(int, unsigned long, ...);
    ]]
    )
    local TIOCGWINSZ = vim.fn.has('linux') == 1 and 0x5413 or 0x40087468
    local ws = ffi.new('markvim_winsize')
    for _, fd in ipairs({ 1, 2, 0 }) do
      if ffi.C.ioctl(fd, TIOCGWINSZ, ws) == 0 and ws.ws_xpixel > 0 and ws.ws_col > 0 and ws.ws_row > 0 then
        w, h = ws.ws_xpixel / ws.ws_col, ws.ws_ypixel / ws.ws_row
        return
      end
    end
  end)
  if not ok then
    w, h = cfg.width, cfg.height
  end
  cell_cache = { w, h }
  api.nvim_create_autocmd('VimResized', {
    group = api.nvim_create_augroup('markvim.image', { clear = true }),
    once = true,
    callback = function()
      cell_cache = nil
    end,
  })
  return w, h
end

---Virtual lines showing `entry` (a PNG) scaled to fit `opts.width` cells and
---`opts.max_height` rows. Returns nil when images cannot be shown.
---@param entry markvim.DiagramEntry
---@param opts {width: integer, max_height: integer, indent: integer}
---@return table[]|nil
function M.virt_lines(entry, opts)
  if not M.available() or not entry.path or not entry.width then
    return nil
  end
  local cw, ch = M.cell_size()
  local cols = math.ceil(entry.width / cw)
  local rows = math.ceil(entry.height / ch)
  local scale = math.min(1, opts.width / cols, opts.max_height / rows)
  cols = math.max(1, math.floor(cols * scale))
  rows = math.max(1, math.floor(rows * scale))
  local kitty = require('markvim.image.kitty')
  local id = kitty.ensure(entry, cols, rows)
  if not id then
    return nil
  end
  return kitty.placeholder_lines(id, cols, rows, opts.indent)
end

return M
