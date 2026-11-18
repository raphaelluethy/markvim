# markvim architecture

## Goals

Render markdown in-buffer with minimal overhead, support live/preview/split
modes, attach to any markdown buffer (files, LSP floats, chat UIs), render
diagrams, use the user's colorscheme, and load lazily. Requires Neovim 0.12 or newer.

## Rendering model

```
events ──► render.render(buf)
             │  viewport(): visible rows of every window showing buf (+ margin)
             │  compute():  shared markdown parser  ── block query ─┐
             │              private markdown_inline tree ── inline query ─┤► element modules ► Ctx marks
             └  apply():    per view: clear ns, set extmarks (skip raw rows)
```

* **Mark computation** lives in `lua/markvim/compute.lua`. It builds queries
  for enabled Markdown sections and calls the element functions in
  `lua/markvim/elements/`. Elements record marks in the context
  (`ctx.add` for marks hidden on raw rows and `ctx.fix` for always-visible
  marks) and width adjustments that tables use to align cells after conceals.
  `render.lua` applies those marks and manages buffers and windows.
* **Marks** are persistent extmarks. Each *view* owns two namespaces: `ns`
  (conceals, icons, overlays; removed on the cursor row in live mode) and
  `ns_fixed` (backgrounds, virtual lines; always shown).
* **Live mode** caches the marks of the last render per row. On `CursorMoved`
  it clears `ns` on the new cursor row(s) and re-sets the cached marks on the
  rows the cursor left. Diagram blocks (and, with `live.context='block'`, code
  blocks/tables) expand the raw region to the whole block. If the buffer
  changed since the cache was built, nothing is restored; the debounced
  render fixes everything.
* **Split mode** opens a second window on the same buffer and scopes the
  preview namespaces to it with `nvim__ns_set(ns, {wins={win}})`. No mirror
  buffer; edits are visible instantly in both windows.
* **Floats**: `vim.lsp.util.open_floating_preview` sets `filetype=markdown`
  after the lines are in the buffer and before it measures the window. Our
  `FileType` handler renders synchronously, so `conceal_lines` marks shrink the
  float height correctly.

## Why not a decoration provider

Ephemeral marks in `on_win`/`on_range` would give per-window cursor handling
for free, but in 0.12 ephemeral `virt_lines`, `conceal_lines` and inline
`virt_text` are not rendered (verified with a child Neovim in a terminal
buffer, see `tests/screen.lua`). Tables, diagrams and icons need all three.

## Treesitter costs that matter

`LanguageTree` keeps one tree per injected `markdown_inline` region. If the
whole file has been parsed (e.g. by `gO`), the shared parser's child holds
thousands of trees and every edit costs O(trees) in Lua (`_edit` loops over
all trees and regions); iterating `trees()` per render costs ~2 ms at 11k
trees. markvim therefore parses inline markup with a **private**
`markdown_inline` LanguageTree whose included regions are exactly the
`inline`/`pipe_table_cell` nodes in the viewport (minus their named children,
like the injection machinery does). The tree receives no edit notifications,
so it is invalidated when the buffer's changedtick changes. A forced render at
the same viewport (e.g. after a width change) reuses the inline trees without
rediscovering regions.

The shared markdown (block) tree is reused through `parser:parse()`. With no
range argument it only parses the root and leaves injections to Neovim's
highlighter; if the root is already valid no reparse is needed.
tree-sitter-markdown's block reparse after an edit can still dominate total
latency in large documents.

Neovim's bundled markdown highlight query already conceals inline delimiters,
link syntax and (with `conceal_lines`) fence lines. markvim re-emits the
conceals it depends on (so width calculations are exact). When
`code.border` is `hide` or `thin`, `compat.lua` removes the runtime query's
fence-line conceals so markvim can decide how to display each fence.

## Diagrams

`diagram/init.lua` hashes `(renderer, kind, theme, width, source)`, checks the
memory and disk cache, otherwise queues a `vim.system` job (max 2 parallel;
optional second stage e.g. SVG→PNG). On completion every waiting buffer is
invalidated and re-rendered. Text art becomes `virt_lines`; images become
kitty Unicode placeholder cells (`image/kitty.lua`: `a=t,t=f` transmit for
local terminals, `t=d` chunks for remote/tmux, `a=p,U=1` virtual placement,
`U+10EEEE` + row/column diacritics with the image id as foreground color).
Virtual lines attached to a `conceal_lines` row are not drawn, so the art is
anchored below the row preceding the block (or above the following one).

## Benchmarks

`bench/gen.lua` builds a 17 500-line file with every element type;
`bench/run.lua` prints compute/apply timings per phase. Numbers (0.12.6,
Apple Silicon): viewport compute 1.1–1.3 ms (elements ~0.9, inline ~0.2),
apply 0.12–0.2 ms, no-op render 0.006 ms, cursor move 0.11 ms, edit + render
excluding tree-sitter's re-parse 1.8 ms, ~5.5 MB Lua heap. Startup: the
plugin file costs 0.06 ms; first attach loads ~17 modules and compiles 3
queries (~9 ms once per session).

## Testing

* `tests/run.lua` — headless unit tests on extmark details (`tests/spec/*`).
* `tests/screen.lua` — runs a child `nvim --clean` with the plugin inside a
  terminal buffer and dumps the screen; used for visual verification of live,
  preview, split, thin borders and diagrams.
