# markvim

Fast in-buffer markdown rendering for Neovim 0.12+. One engine for markdown
files, LSP hover/signature floats and any other markdown buffer, with three
modes:

- **live** – everything is rendered except the line under the cursor, which is
  shown as raw markdown (Obsidian-style live preview). Works in insert mode too.
- **preview** – everything is rendered, including the cursor line.
- **split** – your buffer stays raw in one window and a fully rendered preview of
  the *same buffer* opens next to it, scrolled in sync. No copy, no second buffer.

Rendered elements: headings (background, optional icons), code blocks (hidden
fences or thin borders, language label), bullets, checkboxes (incl. custom
`[-] [>] [~] [!] [?]`), block quotes, GitHub/Obsidian callouts, tables (aligned
cells, box-drawing borders), rules, links (wiki links, footnotes, optional icons,
images), inline code/emphasis/strikethrough, HTML comments, and **diagrams**:
Mermaid (incl. ```` ```pele ```` blocks), PlantUML, D2 and Graphviz rendered as
box-drawing text or as real images in terminals that implement the kitty
graphics protocol with Unicode placeholders (kitty, Ghostty, iTerm2).

Everything links to your colorscheme's `@markup.*`/UI highlight groups; heading
backgrounds are blended from the heading colors. Nothing is hard-coded.

## Requirements

- Neovim **0.12** or newer (uses window-scoped namespaces and `conceal_lines`).
- The bundled `markdown` and `markdown_inline` treesitter parsers (ship with
  Neovim). Treesitter highlighting for markdown is on by default in 0.12 and
  markvim builds on its conceals.
- A Nerd Font is optional. Set `icons = 'unicode'` or `'ascii'` to use a regular
  font.
- Icon providers, diagram renderers, and panels.nvim are optional and installed
  separately.

## Install

`vim.pack` (built in):

```lua
vim.pack.add({ 'https://github.com/raphaelluethy/markvim' })
```

lazy.nvim:

```lua
{ 'raphaelluethy/markvim', ft = 'markdown', opts = {} }
```

No `setup()` call is needed. The plugin file only registers a `FileType`
autocommand and the `:Markvim` command (~0.06 ms at startup); all code loads the
first time a markdown buffer is shown, and element renderers, the diagram
pipeline and the image backend load only when they are first needed.
Open a Markdown file to start in live mode. Use `:Markvim preview` to render
the cursor line too, or `:Markvim split` to keep the source visible beside it.

## Usage

| Command | Effect |
| --- | --- |
| `:Markvim` / `:Markvim toggle` | toggle rendering for the current buffer |
| `:Markvim enable` / `:Markvim disable` | turn rendering on or off for the current buffer |
| `:Markvim live` | live mode (cursor line raw) |
| `:Markvim preview` | preview mode; again to go back to live |
| `:Markvim split` | split mode; again (or close the window) to go back |
| `:Markvim render` | force a re-render |
| `:Markvim open` | open the diagram under the cursor in a floating panel (also `<CR>`) |
| `:Markvim debug` | timings of the last render and marks under the cursor |
| `:Markvim install node` | install the Node based mermaid renderers (`pele`, `beautiful-mermaid`) |
| `:checkhealth markvim` | parsers, renderers, terminal image support |

Repeat `:Markvim preview` or `:Markvim split` to return to live mode. Use
`:Markvim! preview` or `:Markvim! split` to force the named mode.

Lua API (`require('markvim')`): `setup(opts)`, `attach(buf)`, `detach(buf)`,
`enable(buf)`, `disable(buf)`, `toggle(buf)`, `set_mode('live'|'preview'|'split', buf)`,
`render(buf)`, `is_attached(buf)`, `mode(buf)`, `open_diagram(buf, row)`, and `render_lines(lines, {mode=})` which
renders arbitrary markdown into a scratch buffer you can show in any window —
handy for chat UIs, custom hovers or documentation popups.

Per-buffer mode override: set `vim.b.markvim_mode = 'preview'` before the
filetype is set (that is what `render_lines` does).

### LSP hover and friends

`vim.lsp.util.open_floating_preview()` (used by `vim.lsp.buf.hover()`,
signature help and most completion plugins' documentation windows) sets
`filetype=markdown` on its buffer. markvim attaches through that `FileType`
event, renders synchronously before Neovim computes the float size (so hidden
fence lines shrink the float), and uses `float_mode` (default `preview`). Nothing
to configure.

## Configuration

All options with their defaults (`:h markvim-config`):

```lua
require('markvim').setup({
  enabled = true,
  filetypes = { 'markdown' },
  mode = 'live',             -- 'live' | 'preview' | 'split' for file buffers
  float_mode = 'preview',    -- for floating windows (hover, signature help)
  max_file_size = 4 * 1024 * 1024,
  margin = 30,               -- rows rendered beyond the visible area
  debounce = { normal = 20, insert = 60 }, -- ms after a text change
  icons = 'nerd',            -- 'nerd' | 'unicode' | 'ascii'
  live = { context = 'line' }, -- 'line' | 'block': what is shown raw around the cursor
  split = { position = 'right', size = 0.5, edit = 'raw', scrollbind = true },
  win_options = { conceallevel = 3 },
  heading = { enabled = true, position = 'inline', background = 'full', icons = false, setext = true },
  code = { enabled = true, border = 'hide', language = true, language_icon = false, language_pos = 'right',
           left_pad = 0, background = 'buffer', spacing = true, indented = true },
  bullet = { enabled = true, icons = nil, ordered = true },
  checkbox = {
    enabled = true,
    custom = {
      ['[-]'] = { icon = '󰥔', hl = 'MarkvimTodo' },
      ['[>]'] = { icon = '󰒭', hl = 'MarkvimTodo' },
      ['[~]'] = { icon = '󰰱', hl = 'MarkvimTodo' },
      ['[!]'] = { icon = '󰀪', hl = 'MarkvimCalloutWarning' },
      ['[?]'] = { icon = '󰘥', hl = 'MarkvimCalloutQuestion' },
    },
  },
  quote = { enabled = true },
  callout = { enabled = true },
  table = { enabled = true, style = 'full', pad = true },
  rule = { enabled = true },
  link = { enabled = true, icons = false },
  inline = { enabled = true, html = false, hard_break = false },
  html = { enabled = true, comments = true },
  diagram = {
    enabled = true,
    backend = 'text',        -- 'text' | 'image' (falls back to text) | 'none'
    hide_source = true,      -- show only the rendering; cursor inside reveals the source
    max_height = 40,         -- taller/wider art: see overflow
    overflow = 'panel',      -- 'panel': placeholder + floating panel (<CR>) | 'truncate'
    panel = 'auto',          -- 'auto': use panels.nvim if installed | 'float': built-in Neovim float
    keys = { open = '<CR>' },-- opens the diagram under the cursor in a panel; false disables
    text = { padding_x = 3, padding_y = 2, box_padding = 0 }, -- beautiful-mermaid spacing
    timeout = 20000,
    languages = {
      mermaid  = { text = { 'beautiful-mermaid', 'mermaid-ascii' }, image = { 'pele', 'mmdc' } },
      pele     = { text = { 'beautiful-mermaid', 'mermaid-ascii' }, image = { 'pele', 'mmdc' } },
      plantuml = { text = { 'plantuml' }, image = { 'plantuml' } },
      puml     = { text = { 'plantuml' }, image = { 'plantuml' } },
      d2       = { text = { 'd2' }, image = { 'd2' } },
      dot      = { text = { 'graph-easy' }, image = { 'dot' } },
      graphviz = { text = { 'graph-easy' }, image = { 'dot' } },
    },
    cache_dir = nil,         -- default stdpath('cache')/markvim
  },
  image = { backend = 'auto', cell = { width = 9, height = 18 } },
  on_attach = nil,
})
```

`code.border = 'thin'` draws the fence lines as borders with the language label
(Neovim's own query hides fence lines; markvim patches that query at runtime for
this style).

Set `code.language_icon = true` to use an available icon provider, or set it to
`'mini.icons'` or `'nvim-web-devicons'` to choose one. With `setup()`, it can also
be a Lua function that takes a language name and returns an icon and optional
highlight group. The default, `false`, leaves language labels as text.

### Highlight groups

All groups are `default` links you can override: `MarkvimH1..6`,
`MarkvimH1Bg..6Bg` (blended), `MarkvimCode`, `MarkvimCodeInline`,
`MarkvimCodeInfo`, `MarkvimCodeBorder`, `MarkvimBullet`, `MarkvimOrdered`,
`MarkvimChecked`, `MarkvimUnchecked`, `MarkvimTodo`, `MarkvimQuote`,
`MarkvimRule`, `MarkvimTable`, `MarkvimLink`, `MarkvimUrl`,
`MarkvimImage`, `MarkvimStrike`, `MarkvimMath`, `MarkvimHtml`, `MarkvimHardBreak`,
`MarkvimDiagram`, `MarkvimDiagramPending`, `MarkvimDiagramError`,
`MarkvimCallout{Note,Tip,Important,Warning,Caution,Question,Quote}`.

## Diagrams

A fenced block whose language has an entry in `diagram.languages` is rendered
asynchronously by the first available renderer, cached in
`stdpath('cache')/markvim` and shown as virtual lines in place of the source.
While a renderer runs, the block is shown as a normal code block with a
`rendering …` note; errors show the tool's first stderr line.
Open text art in a floating window with `:Markvim open` or `<CR>`. Set
`diagram.panel = 'float'` to use Neovim's built-in window even when panels.nvim
is installed.

| Language | Text renderers | Image renderers |
| --- | --- | --- |
| `mermaid`, `pele` | `beautiful-mermaid` (Node, Unicode/ASCII), `mermaid-ascii` | `pele` (Node, SVG → PNG via `rsvg-convert` or `magick`), `mmdc` |
| `plantuml`, `puml` | `plantuml -tutxt` | `plantuml -tpng` |
| `d2` | `d2 … out.txt` | `d2 … out.png` |
| `dot`, `graphviz` | `graph-easy --as=boxart` | `dot -Tpng` |

`:Markvim install node` runs `npm install --prefix stdpath('data')/markvim pele beautiful-mermaid`.
Images need a terminal with kitty graphics + Unicode placeholders (kitty,
Ghostty, iTerm2; WezTerm lacks placeholders); otherwise text renderers are used.
Force with `MARKVIM_IMAGES=1`/`0` or `image.backend`.

Add your own renderer:

```lua
require('markvim.diagram').renderers.register({
  name = 'mytool', kind = 'text', output = 'stdout',
  available = function() return vim.fn.executable('mytool') == 1 end,
  cmd = function(opts) return { 'mytool', '--width', tostring(opts.width) } end,
})
require('markvim').setup({ diagram = { languages = { mylang = { text = { 'mytool' }, image = {} } } } })
```

## Performance

Measured on a generated 17 500-line document (`bench/run.lua`), Apple Silicon,
Neovim 0.12.6:

| Operation | Cost |
| --- | --- |
| render the visible area (80 rows, ~220 marks) | ~1.2 ms compute + 0.15 ms extmarks |
| scroll inside the rendered margin / no change | 0.006 ms |
| cursor move in live mode | 0.1 ms |
| re-render after an edit (markvim's share) | ~1.8 ms |
| memory (Lua) | ~5 MB |

How: only the visible rows (plus `margin`) are queried and decorated; inline
markup is parsed with a private `markdown_inline` tree restricted to the visible
paragraphs, so cost does not grow with file size; marks are cached per row so a
cursor move only touches two rows; split mode reuses the same buffer through
window-scoped namespaces. Details in `doc/ARCHITECTURE.md`.

The one cost markvim cannot remove is tree-sitter-markdown's own re-parse after
an edit in very large files (tens of ms at 17k lines); Neovim's highlighter pays
it on redraw and markvim's debounced render reuses the result.

## Comparison

- `render-markdown.nvim` and `markview.nvim` are mature and feature-rich; both
  render with persistent extmarks and re-render on events. markvim is
  built for Neovim 0.12+, which lets it use window-scoped namespaces for a copy-free split
  preview, parse inline markup per viewport, and ship a diagram pipeline (text
  *and* images) without a separate image plugin.
- `snacks.image`/`image.nvim`/`diagram.nvim` render images only; markvim falls
  back to box-drawing text where images are not available.
- `markdown-preview.nvim`/`peek.nvim` render in a browser.

## Development

```sh
nvim --headless --clean -l tests/run.lua            # unit tests (extmark level)
nvim --headless --clean -l tests/screen.lua FILE.md 100 24 1000 "jj" ":Markvim split\r"
nvim --headless --clean -l bench/gen.lua /tmp/big.md 500 && nvim --headless --clean -l bench/run.lua /tmp/big.md
stylua lua plugin tests bench
```

`tests/screen.lua` runs a child Neovim with the plugin in a terminal buffer and
prints the screen as text, which is how the visual behaviour is verified.

## License

Copyright © 2026 Raphael Lüthy. Markvim is licensed under the GNU General
Public License, version 3 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE).

The terminal image backend includes the Unicode row and column lookup table
from the [kitty graphics protocol](https://github.com/kovidgoyal/kitty/blob/a79dd3996ac55e1c89c8cc916e3a598739761455/gen/rowcolumn-diacritics.txt).
