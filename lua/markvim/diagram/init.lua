-- Diagram pipeline: fenced code blocks in a configured language are rendered
-- asynchronously by an external tool into text art or a PNG, cached on disk and
-- shown as virtual lines. Loaded lazily the first time such a block is visible.
local api = vim.api
local uv = vim.uv
local config = require('markvim.config')
local renderers = require('markvim.diagram.renderers')
local state = require('markvim.state')
local util = require('markvim.util')

local M = {}

local MAX_JOBS = 2

---@class markvim.DiagramEntry
---@field status 'pending'|'ready'|'error'
---@field kind 'text'|'image'
---@field lines string[]|nil text art
---@field path string|nil image file
---@field width integer|nil image pixel width
---@field height integer|nil image pixel height
---@field err string|nil

---@type table<string, markvim.DiagramEntry>
local cache = {}
---@type table<string, table<integer, boolean>>
local waiting = {}
local running = 0
local queue = {}

-- lua/markvim/diagram/init.lua -> plugin root (four levels up).
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))))
local script = root .. '/scripts/mermaid.mjs'

---The most telling line of a renderer's stderr: Node prints its stack frame
---first and the message later, so prefer a line mentioning an error.
local function error_line(msg)
  for line in msg:gmatch('[^\n]+') do
    if line:find('[Ee]rror') or line:find('[Ff]ail') then
      return line:gsub('^%s+', '')
    end
  end
  return msg:match('[^\n]+') or msg
end

local function node_prefix()
  return vim.fn.stdpath('data') .. '/markvim'
end
renderers.set_prefix(node_prefix)

local function cache_dir()
  local dir = config.get().diagram.cache_dir or (vim.fn.stdpath('cache') .. '/markvim')
  if not uv.fs_stat(dir) then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

local function read_file(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0) or nil
  uv.fs_close(fd)
  return data
end

local function write_file(path, data)
  local fd = uv.fs_open(path, 'w', 420)
  if not fd then
    return false
  end
  uv.fs_write(fd, data, 0)
  uv.fs_close(fd)
  return true
end

---Width/height of a PNG from its IHDR chunk.
---@return integer|nil, integer|nil
function M.png_size(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local head = uv.fs_read(fd, 24, 0)
  uv.fs_close(fd)
  if not head or #head < 24 or head:sub(1, 8) ~= '\137PNG\r\n\26\n' then
    return nil
  end
  local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  return u32(head, 17), u32(head, 21)
end

local function split_lines(text)
  local lines = vim.split(text:gsub('\r', ''), '\n', { plain = true })
  while #lines > 0 and lines[#lines]:match('^%s*$') do
    lines[#lines] = nil
  end
  local first = 1
  while first <= #lines and lines[first]:match('^%s*$') do
    first = first + 1
  end
  if first > 1 then
    lines = vim.list_slice(lines, first)
  end
  return lines
end

local function finish(key, entry)
  entry.status = entry.err and 'error' or 'ready'
  local bufs = waiting[key]
  waiting[key] = nil
  if bufs then
    local render = require('markvim.render')
    for buf in pairs(bufs) do
      if api.nvim_buf_is_valid(buf) then
        render.invalidate(buf)
      end
    end
  end
end

local function next_job()
  if running >= MAX_JOBS then
    return
  end
  local job = table.remove(queue, 1)
  if job then
    running = running + 1
    job()
  end
end

---@param spec markvim.Renderer
---@param opts markvim.RenderOpts
local function run(key, spec, opts, entry, out_base)
  local cfg = config.get().diagram
  local env = { MARKVIM_NODE_PREFIX = opts.node_prefix }
  for k, v in pairs(spec.env or {}) do
    env[k] = v
  end
  local sysopts = function(stdin, text)
    return { stdin = stdin, text = text, timeout = cfg.timeout, env = env, cwd = cache_dir() }
  end
  local function done(err)
    running = running - 1
    entry.err = err
    vim.schedule(function()
      finish(key, entry)
      next_job()
    end)
  end
  local function collect(stdout)
    local ext = spec.ext or (spec.kind == 'text' and 'txt' or 'png')
    local path = out_base .. '.' .. ext
    if spec.output == 'stdout' then
      if spec.kind == 'text' then
        entry.lines = split_lines(stdout)
        write_file(path, table.concat(entry.lines, '\n'))
      else
        if not write_file(path, stdout) then
          return done('cannot write ' .. path)
        end
      end
    else
      if spec.kind == 'text' then
        local data = read_file(path)
        if not data then
          return done('renderer produced no output')
        end
        entry.lines = split_lines(data)
      end
    end
    if spec.kind == 'image' then
      entry.path = path
      entry.width, entry.height = M.png_size(path)
      if not entry.width then
        return done('renderer produced no PNG')
      end
    end
    done(nil)
  end
  local ok, err = pcall(function()
    vim.system(
      spec.cmd(opts),
      sysopts(spec.stdin ~= false and opts.src or nil, spec.kind == 'text' and not spec.post),
      function(res)
        if res.code ~= 0 then
          local msg = (res.stderr or ''):gsub('%s+$', '')
          msg = msg ~= '' and msg or ('exit code ' .. res.code)
          return done(error_line(msg))
        end
        if spec.post then
          local post_ok, post_err = pcall(function()
            vim.system(spec.post(opts), sysopts(res.stdout, false), function(res2)
              if res2.code ~= 0 then
                local msg = (res2.stderr or ''):gsub('%s+$', '')
                return done(msg ~= '' and error_line(msg) or ('exit code ' .. res2.code))
              end
              collect(res2.stdout)
            end)
          end)
          if not post_ok then
            done(tostring(post_err))
          end
          return
        end
        collect(res.stdout or '')
      end
    )
  end)
  if not ok then
    done(tostring(err))
  end
end

local function normal_fg()
  local hl = api.nvim_get_hl(0, { name = 'Normal', link = false })
  if hl.fg then
    return ('#%06x'):format(hl.fg)
  end
  return vim.o.background == 'dark' and '#d0d0d0' or '#202020'
end

---Get (or start producing) the rendering for a diagram.
---@param spec markvim.Renderer
---@param src string
---@param ctx markvim.Ctx
---@param width integer
---@return markvim.DiagramEntry
function M.get(spec, src, ctx, width)
  local dark = vim.o.background == 'dark'
  local ascii = ctx.cfg.icons == 'ascii'
  local key_src = table.concat({
    spec.name,
    spec.kind,
    dark and 'd' or 'l',
    ascii and 'a' or 'u',
    spec.kind == 'text' and tostring(width) or '',
    spec.kind == 'text' and vim.json.encode(ctx.cfg.diagram.text or {}) or '',
    src,
  }, '\0')
  local key = vim.fn.sha256(key_src):sub(1, 24)
  local entry = cache[key]
  if entry then
    if entry.status == 'pending' then
      waiting[key] = waiting[key] or {}
      waiting[key][ctx.buf] = true
    end
    return entry
  end
  entry = { status = 'pending', kind = spec.kind }
  cache[key] = entry
  -- Disk cache hit?
  local out_base = cache_dir() .. '/' .. key
  local ext = spec.ext or (spec.kind == 'text' and 'txt' or 'png')
  local path = out_base .. '.' .. ext
  if uv.fs_stat(path) then
    if spec.kind == 'text' then
      local data = read_file(path)
      if data then
        entry.lines = split_lines(data)
        entry.status = 'ready'
        return entry
      end
    else
      entry.width, entry.height = M.png_size(path)
      if entry.width then
        entry.path = path
        entry.status = 'ready'
        return entry
      end
    end
  end
  waiting[key] = { [ctx.buf] = true }
  local opts = {
    src = src,
    out = out_base,
    width = width,
    dark = dark,
    fg = normal_fg(),
    ascii = ascii,
    script = script,
    node_prefix = node_prefix(),
    text = ctx.cfg.diagram.text,
  }
  queue[#queue + 1] = function()
    run(key, spec, opts, entry, out_base)
  end
  next_job()
  return entry
end

---Pick the backend kind for the current configuration/terminal.
---@return 'text'|'image'|nil
local function backend(cfg)
  local b = cfg.backend
  if b == 'none' then
    return nil
  end
  if b == 'auto' or b == 'image' then
    return require('markvim.image').available() and 'image' or 'text'
  end
  return b
end

local function is_fence(line)
  return line:match('^%s*```') ~= nil or line:match('^%s*~~~') ~= nil
end

---Render a diagram code block. Returns true when the block was fully handled
---(source hidden) and false when the normal code block rendering should also run.
---@param ctx markvim.Ctx
---@param node TSNode
---@param lang string
---@param rows {top: integer, bottom: integer, first: integer, last: integer, has_close: boolean}
---@return boolean
function M.render_block(ctx, node, lang, rows)
  local cfg = ctx.cfg.diagram
  local langs = cfg.languages[lang]
  if not langs or rows.first > rows.last then
    return false
  end
  local src_lines = {}
  for row = rows.first, rows.last do
    src_lines[#src_lines + 1] = ctx.line(row)
  end
  local src = table.concat(src_lines, '\n')
  if src:match('^%s*$') then
    return false
  end
  local kind = backend(cfg)
  if not kind then
    return false
  end
  local spec = renderers.pick(langs[kind] or {}, kind)
  if not spec and kind == 'image' then
    kind = 'text'
    spec = renderers.pick(langs.text or {}, 'text')
  end
  if not spec then
    return false
  end
  local _, indent = node:range()
  local width = math.max(20, ctx.width - indent)
  local entry = M.get(spec, src, ctx, width)
  ctx.raw_blocks[#ctx.raw_blocks + 1] = { rows.top, rows.bottom }
  ctx.blocks[#ctx.blocks + 1] = { rows.top, rows.bottom }

  if entry.status ~= 'ready' then
    local label
    if entry.status == 'error' then
      label = { { ctx.icons.error .. 'diagram error: ' .. (entry.err or '?'), 'MarkvimDiagramError' } }
    else
      label = { { ctx.icons.pending .. 'rendering ' .. lang .. '…', 'MarkvimDiagramPending' } }
    end
    ctx.fix(rows.first, 0, { virt_text = label, virt_text_pos = 'eol' })
    return false
  end

  local virt
  if entry.kind == 'text' then
    local hl = 'MarkvimDiagram'
    local pad = (' '):rep(indent)
    virt = {}
    local max = cfg.max_height
    local art_w = 0
    for _, l in ipairs(entry.lines) do
      local w = api.nvim_strwidth(l)
      if w > art_w then
        art_w = w
      end
    end
    local block = { top = rows.top, bottom = rows.bottom, lang = lang, entry = entry }
    ctx.diagrams[#ctx.diagrams + 1] = block
    if cfg.overflow == 'panel' and (#entry.lines > max or art_w > width) then
      block.large = true
      local key = cfg.keys and cfg.keys.open
      local hint = key and (' · ' .. key .. ' to open') or ' · :Markvim open'
      virt[1] = {
        {
          pad .. ctx.icons.diagram .. ('%s diagram, %d×%d'):format(lang, art_w, #entry.lines) .. hint,
          'MarkvimDiagramPending',
        },
      }
    else
      for i, l in ipairs(entry.lines) do
        if i > max then
          virt[#virt + 1] = { { pad .. ('… %d more lines'):format(#entry.lines - max), 'MarkvimDiagramPending' } }
          break
        end
        virt[#virt + 1] = { { pad .. l, hl } }
      end
    end
  else
    virt = require('markvim.image').virt_lines(entry, { width = width, max_height = cfg.max_height, indent = indent })
    if not virt then
      ctx.fix(rows.first, 0, {
        virt_text = { { ctx.icons.error .. 'image backend unavailable', 'MarkvimDiagramError' } },
        virt_text_pos = 'eol',
      })
      return false
    end
  end
  if #virt == 0 then
    return false
  end

  local hide = cfg.hide_source
  local anchor, above
  if hide then
    local line_count = api.nvim_buf_line_count(ctx.buf)
    if rows.top > 0 and not ctx.hidden[rows.top - 1] and not is_fence(ctx.line(rows.top - 1)) then
      anchor, above = rows.top - 1, false
    elseif
      rows.bottom + 1 < line_count
      and not ctx.hidden[rows.bottom + 1]
      and not is_fence(ctx.line(rows.bottom + 1))
    then
      anchor, above = rows.bottom + 1, true
    else
      hide = false
    end
  end
  if hide then
    for row = rows.top, rows.bottom do
      ctx.add(row, 0, { conceal_lines = '' })
      ctx.hidden[row] = true
    end
  else
    anchor, above = rows.last, false
  end
  ctx.fix(anchor, 0, { virt_lines = virt, virt_lines_above = above })
  return hide
end

---Fallback panel when panels.nvim is not installed: a plain float.
local function fallback_panel(title, lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local cols, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local width, height = math.floor(cols * 0.9), math.floor(rows * 0.9)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((rows - height) / 2) - 1,
    col = math.floor((cols - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = false
  for _, lhs in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', lhs, function()
      pcall(api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true })
  end
  return { buf = buf, win = win }
end

---Open the rendered art of a diagram in a floating panel (panels.nvim when
---installed, else a plain float).
---@param buf integer
---@param block {lang: string, entry: table}
function M.open(buf, block)
  local s = state.get(buf)
  local entry = block.entry
  if entry.kind ~= 'text' or not entry.lines then
    return vim.notify('markvim: only text diagrams can be opened in a panel', vim.log.levels.INFO)
  end
  local title = block.lang .. ' diagram'
  local ok, panels = pcall(require, 'panels')
  if ok then
    if s and s.panel and (s.panel.layer_id or (s.panel.buf and api.nvim_buf_is_valid(s.panel.buf))) then
      s.panel.opts.title = title
      s.panel:set_lines(entry.lines)
      s.panel:show({ focus = true })
      return s.panel
    end
    local panel = panels.open({ title = title, lines = entry.lines, label = 'markvim', wrap = false })
    if s then
      s.panel = panel
    end
    return panel
  end
  return fallback_panel(title, entry.lines)
end

---Open the diagram at a row (the block itself or its neighbouring rows).
---@param buf integer
---@param row integer|nil 0-based; defaults to the cursor row
---@return boolean opened
function M.open_at(buf, row)
  local s = state.get(buf)
  if not s then
    return false
  end
  row = row or (api.nvim_win_get_cursor(0)[1] - 1)
  for _, block in ipairs(s.diagram_blocks or {}) do
    if row >= block.top - 1 and row <= block.bottom + 1 then
      M.open(buf, block)
      return true
    end
  end
  return false
end

---Install node based renderers (pele, beautiful-mermaid) into stdpath('data').
---@param what string|nil 'node' (default) | 'all'
function M.install(what)
  what = what or 'node'
  if what ~= 'node' and what ~= 'all' then
    vim.notify('markvim: unknown install target ' .. what, vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable('npm') == 0 then
    vim.notify('markvim: npm not found; install Node.js first', vim.log.levels.ERROR)
    return
  end
  local prefix = node_prefix()
  vim.fn.mkdir(prefix, 'p')
  vim.notify('markvim: installing pele and beautiful-mermaid into ' .. prefix .. ' …', vim.log.levels.INFO)
  vim.system(
    { 'npm', 'install', '--prefix', prefix, '--no-audit', '--no-fund', 'pele', 'beautiful-mermaid' },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code == 0 then
          renderers.reset_cache()
          vim.notify('markvim: node renderers installed', vim.log.levels.INFO)
          for buf in pairs(require('markvim.state').buffers) do
            require('markvim.render').invalidate(buf)
          end
        else
          vim.notify('markvim: npm install failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
        end
      end)
    end
  )
end

---Drop in-memory cache (disk cache stays). Used by tests.
function M.clear()
  cache = {}
  waiting = {}
end

M._cache = cache
M.renderers = renderers

return M
