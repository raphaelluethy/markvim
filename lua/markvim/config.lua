---@class markvim.Config
local defaults = {
  -- Master switch.
  enabled = true,
  -- Filetypes to attach to. LSP hover/signature floats use filetype `markdown`
  -- so they are covered by the default.
  filetypes = { 'markdown' },
  -- Default mode for file buffers: 'live' (cursor line raw, rest rendered),
  -- 'preview' (everything rendered) or 'split' (raw edit window + rendered split).
  mode = 'live',
  -- Mode used for floating windows (LSP hover, signature help, completion docs).
  float_mode = 'preview',
  -- Skip buffers larger than this many bytes.
  max_file_size = 4 * 1024 * 1024,
  -- Extra lines rendered above/below the visible area so small scrolls need no work.
  margin = 30,
  -- Debounce in milliseconds for re-rendering after text changes.
  debounce = { normal = 20, insert = 60 },
  -- Icon set: 'nerd' (Nerd Font), 'unicode' (plain unicode) or 'ascii'.
  icons = 'nerd',
  live = {
    -- What is shown raw around the cursor in live mode: 'line' (the cursor line)
    -- or 'block' (the whole code block / table / list item the cursor is in).
    context = 'line',
  },
  split = {
    -- 'right' | 'left' | 'above' | 'below'
    position = 'right',
    -- Fraction (0-1) or absolute columns/rows for the preview window.
    size = 0.5,
    -- Rendering of the edit side: 'raw' (nothing) or 'live'.
    edit = 'raw',
    -- Keep both windows scrolled together.
    scrollbind = true,
  },
  -- Window options applied to windows that show a rendered buffer; the previous
  -- values are restored when markvim is disabled for the buffer.
  win_options = {
    conceallevel = 3,
    -- live mode uses '' so the cursor line un-conceals; preview uses 'nvic'.
  },
  heading = {
    enabled = true,
    -- 'inline': the `#` markers are concealed (and replaced by the icon, if
    -- any); 'overlay': the icon is drawn over the markers.
    position = 'inline',
    -- Draw a background over the whole line ('full') or only the text ('block'); false disables.
    background = 'full',
    -- false: no icon, the markers are simply hidden. true: the icon set's
    -- heading icons. A list of 6 strings: your own icons per level.
    icons = false,
    -- Setext headings (underlined with === / ---): draw the underline as a rule.
    setext = true,
  },
  code = {
    enabled = true,
    -- 'hide': fence lines hidden (Neovim default); 'thin': fence lines become a
    -- thin border with the language label; 'none': leave fences alone.
    border = 'hide',
    -- Show the language label on code blocks.
    language = true,
    -- Prefix the label with the devicon (needs nvim-web-devicons or mini.icons).
    language_icon = false,
    -- 'right' or 'left' placement of the label when border = 'hide'.
    language_pos = 'right',
    -- Spaces of padding inserted at the left of code lines (visual only).
    left_pad = 0,
    -- Background behind code lines (MarkvimCode): 'buffer' (files only, never
    -- in floating windows such as LSP hovers), 'always', 'auto' (skipped only
    -- when a float contains nothing but one code block) or false.
    background = 'buffer',
    -- When a hidden fence line sits directly next to text (typical for LSP
    -- hovers), show it as an empty line so the block stays separated.
    spacing = true,
    -- Also highlight indented (4-space) code blocks.
    indented = true,
  },
  bullet = {
    enabled = true,
    icons = nil, -- override per nesting level
    ordered = true, -- highlight ordered list markers
  },
  checkbox = {
    enabled = true,
    -- Custom states beyond `[ ]` / `[x]`: raw marker -> { icon = ..., hl = ... }
    custom = {
      ['[-]'] = { icon = '󰥔', hl = 'MarkvimTodo' },
      ['[>]'] = { icon = '󰒭', hl = 'MarkvimTodo' },
      ['[~]'] = { icon = '󰰱', hl = 'MarkvimTodo' },
      ['[!]'] = { icon = '󰀦', hl = 'MarkvimCalloutWarning' },
      ['[?]'] = { icon = '󰘥', hl = 'MarkvimCalloutQuestion' },
    },
  },
  quote = { enabled = true },
  callout = { enabled = true },
  table = {
    enabled = true,
    -- 'full': top/bottom borders as virtual lines; 'normal': only inner borders.
    style = 'full',
    -- Pad cells so columns align.
    pad = true,
  },
  rule = { enabled = true },
  link = {
    enabled = true,
    -- Prefix links / images / wiki links / footnotes with an icon for their kind.
    icons = false,
  },
  inline = {
    enabled = true,
    -- Conceal inline html tags such as <br>.
    html = false,
    -- Show a marker for hard line breaks (two trailing spaces).
    hard_break = false,
  },
  html = {
    enabled = true,
    -- Conceal `<!-- comments -->`.
    comments = true,
  },
  diagram = {
    enabled = true,
    -- 'auto': images when the terminal supports them, else text; 'text'; 'image'; 'none'.
    backend = 'auto',
    -- Hide the diagram source when a rendering is available. In live mode the
    -- source shows again when the cursor is inside the block.
    hide_source = true,
    -- Max rows a rendered diagram may use (images are scaled down to fit).
    max_height = 30,
    -- Milliseconds before a renderer is killed.
    timeout = 20000,
    -- Renderers per code block language. Each entry is a list of renderer names
    -- tried in order (first available wins). See `markvim.diagram.renderers`.
    languages = {
      mermaid = { text = { 'beautiful-mermaid', 'mermaid-ascii' }, image = { 'pele', 'mmdc' } },
      pele = { text = { 'beautiful-mermaid', 'mermaid-ascii' }, image = { 'pele', 'mmdc' } },
      plantuml = { text = { 'plantuml' }, image = { 'plantuml' } },
      puml = { text = { 'plantuml' }, image = { 'plantuml' } },
      d2 = { text = { 'd2' }, image = { 'd2' } },
      dot = { text = { 'graph-easy' }, image = { 'dot' } },
      graphviz = { text = { 'graph-easy' }, image = { 'dot' } },
    },
    -- Directory for cached renderings.
    cache_dir = nil, -- default: stdpath('cache') .. '/markvim'
  },
  image = {
    -- 'auto' | 'kitty' | false
    backend = 'auto',
    -- Pixel size of a cell when it cannot be detected.
    cell = { width = 9, height = 18 },
  },
  -- Called after a buffer is attached.
  on_attach = nil,
}

local M = {}

---@type markvim.Config
M.options = nil

local function validate(opts)
  local ok_modes = { live = true, preview = true, split = true }
  if not ok_modes[opts.mode] then
    error(('markvim: invalid mode %q'):format(tostring(opts.mode)))
  end
  if not ok_modes[opts.float_mode] or opts.float_mode == 'split' then
    error(('markvim: invalid float_mode %q'):format(tostring(opts.float_mode)))
  end
end

---@param opts markvim.Config|nil
function M.setup(opts)
  local user = opts or (type(vim.g.markvim) == 'table' and vim.g.markvim) or {}
  M.options = vim.tbl_deep_extend('force', {}, defaults, user)
  validate(M.options)
  return M.options
end

---@return markvim.Config
function M.get()
  if not M.options then
    M.setup(nil)
  end
  return M.options
end

M.defaults = defaults

return M
