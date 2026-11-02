-- Diagram renderer registry. A renderer turns diagram source into either text
-- (box-drawing/ASCII art shown as virtual lines) or a PNG image (shown through
-- the kitty graphics protocol). Everything runs asynchronously via vim.system.
--
-- Add your own with `require('markvim.diagram.renderers').register(spec)`.
local M = {}

---@class markvim.RenderOpts
---@field src string diagram source
---@field out string output file path (without extension)
---@field width integer available text width in cells
---@field dark boolean
---@field fg string hex color, e.g. '#cccccc'
---@field ascii boolean prefer pure ASCII output
---@field script string path to scripts/mermaid.mjs
---@field node_prefix string directory holding node_modules for node based renderers

---@class markvim.Renderer
---@field name string
---@field kind 'text'|'image'
---@field available fun(): boolean
---@field cmd fun(opts: markvim.RenderOpts): string[]
---@field stdin boolean|nil feed the source on stdin (default true)
---@field output 'stdout'|'file' where the result ends up ('file' means `opts.out .. '.' .. ext`)
---@field ext string|nil file extension for `output = 'file'`
---@field post nil|fun(opts: markvim.RenderOpts): string[] second stage reading stage one's stdout on stdin and writing the file
---@field env table<string, string>|nil

local exe_cache = {}
local function has_exe(name)
  local v = exe_cache[name]
  if v == nil then
    v = vim.fn.executable(name) == 1
    exe_cache[name] = v
  end
  return v
end

local function node_module(prefix, name)
  return has_exe('node') and vim.uv.fs_stat(prefix .. '/node_modules/' .. name .. '/package.json') ~= nil
end

local function svg_to_png(opts)
  if has_exe('rsvg-convert') then
    return { 'rsvg-convert', '-z', '2', '-o', opts.out .. '.png' }
  end
  return { 'magick', '-density', '192', '-background', 'none', 'svg:-', opts.out .. '.png' }
end

local function has_svg_converter()
  return has_exe('rsvg-convert') or has_exe('magick')
end

---@type table<string, markvim.Renderer>
M.specs = {}

---@param spec markvim.Renderer
function M.register(spec)
  M.specs[spec.name] = spec
end

local prefix_for -- set by init via M.set_prefix

function M.set_prefix(fn)
  prefix_for = fn
end

M.register({
  name = 'beautiful-mermaid',
  kind = 'text',
  output = 'stdout',
  available = function()
    return node_module(prefix_for(), 'beautiful-mermaid')
  end,
  cmd = function(o)
    return {
      'node',
      o.script,
      'beautiful-mermaid',
      o.ascii and 'ascii' or 'unicode',
      vim.json.encode({ maxWidth = o.width }),
    }
  end,
})

M.register({
  name = 'mermaid-ascii',
  kind = 'text',
  output = 'stdout',
  available = function()
    return has_exe('mermaid-ascii')
  end,
  cmd = function(o)
    local cmd = { 'mermaid-ascii' }
    if o.ascii then
      cmd[#cmd + 1] = '--ascii'
    end
    return cmd
  end,
})

M.register({
  name = 'pele',
  kind = 'image',
  output = 'file',
  ext = 'png',
  available = function()
    return node_module(prefix_for(), 'pele') and has_svg_converter()
  end,
  cmd = function(o)
    return { 'node', o.script, 'pele', 'svg', vim.json.encode({ fg = o.fg, bg = 'transparent', fontSize = 14 }) }
  end,
  post = svg_to_png,
})

M.register({
  name = 'beautiful-mermaid-svg',
  kind = 'image',
  output = 'file',
  ext = 'png',
  available = function()
    return node_module(prefix_for(), 'beautiful-mermaid') and has_svg_converter()
  end,
  cmd = function(o)
    return { 'node', o.script, 'beautiful-mermaid', 'svg', vim.json.encode({ fg = o.fg, bg = 'transparent' }) }
  end,
  post = svg_to_png,
})

M.register({
  name = 'mmdc',
  kind = 'image',
  output = 'file',
  ext = 'png',
  available = function()
    return has_exe('mmdc')
  end,
  cmd = function(o)
    return {
      'mmdc',
      '-q',
      '-i',
      '-',
      '-o',
      o.out .. '.png',
      '-b',
      'transparent',
      '-t',
      o.dark and 'dark' or 'default',
      '-s',
      '2',
    }
  end,
})

M.register({
  name = 'plantuml',
  kind = 'text',
  output = 'stdout',
  available = function()
    return has_exe('plantuml')
  end,
  cmd = function(o)
    return { 'plantuml', o.ascii and '-ttxt' or '-tutxt', '-pipe' }
  end,
})

M.register({
  name = 'plantuml-png',
  kind = 'image',
  output = 'stdout',
  ext = 'png',
  available = function()
    return has_exe('plantuml')
  end,
  cmd = function(o)
    local cmd = { 'plantuml', '-tpng', '-pipe' }
    if o.dark then
      cmd[#cmd + 1] = '-darkmode'
    end
    return cmd
  end,
})

M.register({
  name = 'd2',
  kind = 'text',
  output = 'file',
  ext = 'txt',
  available = function()
    return has_exe('d2')
  end,
  cmd = function(o)
    local cmd = { 'd2' }
    if o.ascii then
      cmd[#cmd + 1] = '--ascii-mode=standard'
    end
    cmd[#cmd + 1] = '-'
    cmd[#cmd + 1] = o.out .. '.txt'
    return cmd
  end,
})

M.register({
  name = 'd2-png',
  kind = 'image',
  output = 'file',
  ext = 'png',
  available = function()
    return has_exe('d2')
  end,
  cmd = function(o)
    return { 'd2', '--theme', o.dark and '200' or '0', '--pad', '16', '--scale', '2', '-', o.out .. '.png' }
  end,
})

M.register({
  name = 'graph-easy',
  kind = 'text',
  output = 'stdout',
  available = function()
    return has_exe('graph-easy')
  end,
  cmd = function(o)
    return { 'graph-easy', o.ascii and '--as=ascii' or '--as=boxart' }
  end,
})

M.register({
  name = 'dot',
  kind = 'image',
  output = 'stdout',
  ext = 'png',
  available = function()
    return has_exe('dot')
  end,
  cmd = function(o)
    return {
      'dot',
      '-Tpng',
      '-Gbgcolor=transparent',
      '-Gdpi=144',
      '-Ncolor=' .. o.fg,
      '-Nfontcolor=' .. o.fg,
      '-Ecolor=' .. o.fg,
      '-Gcolor=' .. o.fg,
      '-Gfontcolor=' .. o.fg,
    }
  end,
})

-- Test renderer: echoes the source back as "art". Used by the test-suite.
M.register({
  name = 'echo',
  kind = 'text',
  output = 'stdout',
  available = function()
    return has_exe('cat')
  end,
  cmd = function()
    return { 'cat' }
  end,
})

-- Image renderer names are looked up as `<name>` and `<name>-png`/`-svg`.
local image_aliases = { plantuml = 'plantuml-png', d2 = 'd2-png' }

---First available renderer of `kind` among `names`.
---@param names string[]
---@param kind 'text'|'image'
---@return markvim.Renderer|nil
function M.pick(names, kind)
  for _, name in ipairs(names) do
    local spec = M.specs[name]
    if kind == 'image' and (not spec or spec.kind ~= 'image') then
      spec = M.specs[image_aliases[name] or (name .. '-png')]
    end
    if spec and spec.kind == kind and spec.available() then
      return spec
    end
  end
  return nil
end

---Availability report for :checkhealth.
function M.report()
  local out = {}
  for name, spec in pairs(M.specs) do
    out[#out + 1] = { name = name, kind = spec.kind, available = spec.available() }
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function M.reset_cache()
  exe_cache = {}
end

return M
