describe('headings', function()
  it('conceals the marker without an icon by default', function()
    local buf = H.buffer({ '# Title', 'text', '## Sub' })
    ok(H.has(buf, 0, { col = 0, end_col = 2, conceal = '' }), 'marker concealed')
    ok(not H.has(buf, 0, { col = 0, pos = 'inline' }), 'no icon')
    ok(H.has(buf, 0, { line_hl = 'MarkvimH1Bg' }, true), 'background')
    H.cleanup()
  end)
  it('inserts an icon when heading.icons = true', function()
    require('markvim.config').setup({ heading = { icons = true } })
    local buf = H.buffer({ '# Title', 'text', '## Sub' })
    ok(H.has(buf, 0, { col = 0, end_col = 2, conceal = '' }), 'marker concealed')
    ok(H.has(buf, 0, { col = 0, pos = 'inline' }), 'icon inserted')
    ok(H.has(buf, 0, { line_hl = 'MarkvimH1Bg' }, true), 'background')
    ok(H.has(buf, 2, { col = 0, end_col = 3, conceal = '' }), 'h2 marker concealed')
    require('markvim.config').setup({})
    H.cleanup()
  end)
  it('renders setext underline as a rule', function()
    local buf = H.buffer({ 'Title', '=====' })
    ok(H.has(buf, 1, { col = 0, end_col = 5, conceal = '' }))
    ok(H.has(buf, 1, { pos = 'inline' }))
    ok(H.has(buf, 0, { line_hl = 'MarkvimH1Bg' }, true))
    H.cleanup()
  end)
end)

describe('code blocks', function()
  it('hides fences and highlights content', function()
    local buf = H.buffer({ '```lua', 'print(1)', 'x = 2', '```', 'after' })
    ok(H.has(buf, 0, { conceal_lines = '' }), 'opening fence hidden')
    ok(H.has(buf, 3, { col = 0, end_col = 3, conceal = '' }), 'closing fence shown as spacing before text')
    ok(H.has(buf, 1, { line_hl = 'MarkvimCode' }, true), 'bg line 1')
    ok(H.has(buf, 2, { line_hl = 'MarkvimCode' }, true), 'bg line 2')
    ok(H.has(buf, 1, { pos = 'right_align' }, true), 'language label')
    eq(0, H.count(buf, 4), 'nothing after the block')
    H.cleanup()
  end)
  it('hides fences framed by blank lines and skips the background in floats', function()
    local buf = H.buffer({ 'before', '', '```lua', 'print(1)', '```', '', 'after' })
    ok(H.has(buf, 2, { conceal_lines = '' }), 'opening fence hidden')
    ok(H.has(buf, 4, { conceal_lines = '' }), 'closing fence hidden')
    ok(H.has(buf, 3, { line_hl = 'MarkvimCode' }, true), 'bg')
    H.cleanup()
    local lines = { '```lua', 'print(1)', '-- a comment wide enough for the label', '```', 'doc text' }
    local fbuf, win = vim.lsp.util.open_floating_preview(lines, 'markdown', {})
    vim.wait(50)
    ok(require('markvim').is_attached(fbuf), 'float attached')
    ok(not H.has(fbuf, 1, { line_hl = 'MarkvimCode' }, true), 'no bg in a float by default')
    ok(H.has(fbuf, 1, { pos = 'right_align' }, true), 'label kept')
    pcall(vim.api.nvim_win_close, win, true)
    H.cleanup()
    require('markvim.config').setup({ code = { background = 'always' } })
    fbuf, win = vim.lsp.util.open_floating_preview(lines, 'markdown', {})
    vim.wait(50)
    ok(H.has(fbuf, 1, { line_hl = 'MarkvimCode' }, true), 'bg in a float with background = always')
    pcall(vim.api.nvim_win_close, win, true)
    require('markvim.config').setup({})
    H.cleanup()
  end)
  it('moves the language label to eol when the first line is too wide', function()
    local wide = ('x'):rep(vim.api.nvim_win_get_width(0) + 5)
    local buf = H.buffer({ '```lua', wide, 'short', '```' })
    ok(H.has(buf, 2, { pos = 'right_align' }, true), 'label on the next row that fits')
    ok(not H.has(buf, 1, { pos = 'right_align' }, true), 'not on the wide row')
    H.cleanup()
    buf = H.buffer({ '```lua', wide, wide, '```' })
    ok(H.has(buf, 1, { pos = 'eol' }, true), 'label at eol when nothing fits')
    H.cleanup()
  end)
  it('handles an unclosed block at end of file', function()
    local buf = H.buffer({ '```', 'a', 'b' })
    ok(H.has(buf, 0, { conceal_lines = '' }))
    ok(H.has(buf, 2, { line_hl = 'MarkvimCode' }, true))
    H.cleanup()
  end)
end)

describe('lists', function()
  it('overlays bullets by depth and renders checkboxes', function()
    local buf = H.buffer({ '- a', '  - b', '- [ ] todo', '- [x] done', '- [-] custom', '1. one' })
    local icons = require('markvim.icons').get('nerd')
    ok(H.has(buf, 0, { col = 0, text = icons.bullet[1], pos = 'overlay' }), 'level 1 bullet')
    ok(H.has(buf, 1, { col = 2, text = icons.bullet[2], pos = 'overlay' }), 'level 2 bullet')
    ok(H.has(buf, 2, { col = 0, end_col = 6, conceal = '' }), 'unchecked concealed')
    ok(H.has(buf, 2, { text = icons.unchecked .. ' ' }), 'unchecked icon')
    ok(H.has(buf, 3, { text = icons.checked .. ' ' }), 'checked icon')
    ok(H.has(buf, 4, { text = '󰥔 ' }), 'custom checkbox')
    ok(H.has(buf, 5, { col = 0, end_col = 3, hl = 'MarkvimOrdered' }), 'ordered marker highlighted')
    H.cleanup()
  end)
end)

describe('quotes and callouts', function()
  it('draws bars and callout titles', function()
    local buf =
      H.buffer({ '> quote', '> more', '', '> [!TIP] custom title', '> body', '', '> [!warning]', '> > nested' })
    ok(H.has(buf, 0, { col = 0, text = '▋', pos = 'overlay' }))
    ok(H.has(buf, 1, { col = 0, text = '▋', pos = 'overlay' }))
    ok(H.has(buf, 3, { col = 2, end_col = 8, conceal = '' }), 'callout marker concealed')
    ok(H.has(buf, 3, { col = 2, pos = 'inline', text = '󰌶' }), 'tip icon without generated title')
    ok(H.has(buf, 6, { col = 2, pos = 'inline', text = '󰀪 Warning' }), 'generated title')
    ok(H.has(buf, 7, { col = 0, text = '▋' }), 'outer bar on nested line')
    ok(H.has(buf, 7, { col = 2, text = '▋' }), 'inner bar on nested line')
    H.cleanup()
  end)
end)

describe('tables', function()
  it('leaves a malformed table with a multiline row unstyled and recovers after an edit', function()
    local buf = H.buffer({
      '|h|l|',
      '|---|---|',
      '|',
      '-:-:    || a :-:|:-:[a](b) a ',
    })
    ok(not H.has(buf, 1, { conceal = '' }), 'malformed table delimiter left raw')
    vim.api.nvim_buf_set_lines(buf, 2, -1, false, { '| c | d |' })
    require('markvim').render(buf)
    ok(H.has(buf, 1, { conceal = '', pos = 'inline' }), 'valid table rendered after the edit')
    H.cleanup()
  end)
  it('pads cells, replaces delimiter row and adds borders', function()
    local buf = H.buffer({ '| a | bbb |', '|---|:---:|', '| cc | d |' })
    ok(H.has(buf, 0, { col = 0, end_col = 2, conceal = '', text = '│ ', pos = 'inline' }), 'pipe replaced')
    ok(
      H.has(buf, 0, { col = 3, end_col = 6, conceal = '', text = '  │ ', pos = 'inline' }),
      'formatter whitespace compacted and short header cell padded'
    )
    ok(H.has(buf, 1, { col = 0, end_col = 11, conceal = '' }), 'delimiter row concealed')
    ok(
      H.has(
        buf,
        1,
        { col = 0, end_col = 11, conceal = '', text = '├────┼─────┤', pos = 'inline' }
      ),
      'delimiter row border'
    )
    ok(H.has(buf, 2, { col = 4, text = ' │  ', pos = 'inline' }), 'center padding')
    ok(H.has(buf, 2, { col = 8, text = '  │', pos = 'inline' }), 'center pad after')
    ok(H.has(buf, 0, { lines = 1, above = true }, true), 'top border')
    ok(H.has(buf, 2, { lines = 1 }, true), 'bottom border')
    H.cleanup()
  end)
  it('accounts for concealed inline markup when padding', function()
    local buf = H.buffer({ '| **b** | x |', '|---|---|', '| a | y |' })
    -- column 1: '**b**' is 5 wide raw, 1 wide rendered -> ' b ' = 3 == ' a ' = 3 -> no padding
    ok(H.has(buf, 2, { col = 3, end_col = 6, conceal = '', text = ' │ ', pos = 'inline' }), 'no padding needed')
    ok(H.has(buf, 1, { text = '├───┼───┤' }))
    H.cleanup()
  end)
  it('compacts formatter whitespace without changing content widths', function()
    local buf = H.buffer({
      '| Dimension                         | Question                         |',
      '|-----------------------------------|----------------------------------|',
      '| Clarity                           | Is scope clear?                  |',
    })
    ok(
      H.has(
        buf,
        1,
        { text = '├───────────┼─────────────────┤' }
      ),
      'border uses compact content widths'
    )
    ok(
      H.has(buf, 0, { col = 11, end_col = 38, conceal = '', text = ' │ ', pos = 'inline' }),
      'aligned source whitespace is replaced at the boundary'
    )
    H.cleanup()
  end)
  it('supports missing edge pipes and inline markup', function()
    local buf = H.buffer({ 'Name      | Value', '----------|:-----:', '**alpha** | x' })
    ok(H.has(buf, 0, { col = 4, end_col = 12, conceal = '', pos = 'inline' }), 'internal boundary replaced')
    ok(
      H.has(buf, 1, { col = 0, end_col = 18, conceal = '', text = '├──────┼──────┤' }),
      'delimiter replaced'
    )
    ok(H.has(buf, 2, { col = 0, end_col = 2, conceal = '' }), 'inline markup still concealed')
    ok(H.has(buf, 2, { col = 9, end_col = 12, conceal = '', pos = 'inline' }), 'body boundary replaced')
    H.cleanup()
  end)
  it('replaces an overflowing table with virtual lines and reveals it for live editing', function()
    local width = vim.api.nvim_win_get_width(0)
    local lines = {
      '| Actor | Role |',
      '|---|---|',
      '| Reviewer | ' .. ('long content '):rep(width) .. '|',
      '',
      'after',
    }
    local buf = H.buffer(lines)
    local function virtual_line_count()
      for _, mark in ipairs(H.marks(buf, 3)) do
        if mark.lines then
          return mark.lines
        end
      end
      return 0
    end
    ok(H.has(buf, 0, { conceal_lines = '' }), 'header source hidden')
    ok(H.has(buf, 2, { conceal_lines = '' }), 'body source hidden')
    ok(virtual_line_count() > 1, 'wrapped table attached to the following line')

    require('markvim.render').set_mode(buf, 'live')
    ok(not H.has(buf, 0, { conceal_lines = '' }), 'source revealed while cursor is in the table')
    eq(0, virtual_line_count(), 'virtual table hidden while editing')
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    require('markvim.render').cursor(buf)
    ok(H.has(buf, 0, { conceal_lines = '' }), 'rendering restored after leaving the table')
    ok(virtual_line_count() > 1, 'virtual table restored after leaving the table')
    H.cleanup()
  end)
end)

describe('inline and links', function()
  it('conceals delimiters and adds link icons', function()
    require('markvim.config').setup({ link = { icons = true } })
    local buf =
      H.buffer({ 'a `c` *e* **s** ~~x~~ [t](https://u) <https://a.b> ![i](p.png) [[w|alias]] [r][1] [^1] \\*' })
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local function col(s)
      return line:find(s, 1, true) - 1
    end
    ok(H.has(buf, 0, { col = col('`c`'), end_col = col('`c`') + 1, conceal = '' }), 'code span open')
    ok(H.has(buf, 0, { col = col('`c`'), end_col = col('`c`') + 3, hl = 'MarkvimCodeInline' }), 'code span hl')
    ok(H.has(buf, 0, { col = col('*e*'), end_col = col('*e*') + 1, conceal = '' }), 'emphasis')
    ok(H.has(buf, 0, { col = col('**s**'), end_col = col('**s**') + 2, conceal = '' }), 'strong')
    ok(H.has(buf, 0, { col = col('~~x~~'), end_col = col('~~x~~') + 2, conceal = '' }), 'strike')
    ok(H.has(buf, 0, { col = col('[t]'), text = '󰖟 ', pos = 'inline' }), 'web link icon')
    ok(H.has(buf, 0, { col = col('[t]') + 2, end_col = col('[t]') + 14, conceal = '' }), 'link tail concealed')
    ok(H.has(buf, 0, { col = col('<https'), text = '󰖟 ' }), 'autolink icon')
    ok(H.has(buf, 0, { col = col('![i]'), text = '󰥶 ' }), 'image icon')
    ok(H.has(buf, 0, { col = col('[[w'), text = '󱗖 ' }), 'wiki icon')
    ok(H.has(buf, 0, { col = col('[[w') + 2, end_col = col('[[w') + 4, conceal = '' }), 'wiki target concealed')
    ok(H.has(buf, 0, { col = col('[r]'), text = '󰌹 ' }), 'reference link icon')
    ok(H.has(buf, 0, { col = col('[^1]'), text = '󰎚 ' }), 'footnote icon')
    ok(H.has(buf, 0, { col = col('\\*'), end_col = col('\\*') + 1, conceal = '' }), 'escape concealed')
    require('markvim.config').setup({})
    H.cleanup()
  end)
end)

describe('rules and html', function()
  it('renders rules full width and conceals comments', function()
    local buf = H.buffer({ 'a', '---', '<!-- hidden -->', 'b <!-- c -->' })
    ok(H.has(buf, 1, { col = 0, end_col = 3, conceal = '' }))
    ok(H.has(buf, 1, { pos = 'inline' }))
    ok(H.has(buf, 2, { col = 0, end_col = 15, conceal = '' }))
    H.cleanup()
  end)
end)

describe('diagrams', function()
  it('replaces oversized art with a placeholder and opens it in a panel', function()
    local diagram = require('markvim.diagram')
    diagram.clear()
    require('markvim.config').setup({
      diagram = { languages = { fake = { text = { 'echo' }, image = {} } }, backend = 'text', max_height = 2 },
    })
    local buf = H.buffer({ 'before', '```fake', 'A', 'B', 'C ' .. vim.uv.hrtime(), '```', 'after', 'far away' })
    vim.wait(2000, function()
      return H.has(buf, 0, { lines = 1 }, true)
    end, 20)
    ok(H.has(buf, 0, { lines = 1, above = false }, true), 'one placeholder line')
    local marks = vim.api.nvim_buf_get_extmarks(
      buf,
      require('markvim.state').get(buf).views[1].ns_fixed,
      { 0, 0 },
      { 0, -1 },
      { details = true }
    )
    ok(marks[1][4].virt_lines[1][1][1]:find('fake diagram, %d+×3'), 'placeholder text')
    local blocks = require('markvim.state').get(buf).diagram_blocks
    eq(1, #blocks, 'diagram registered')
    ok(blocks[1].large, 'marked large')
    ok(not require('markvim').open_diagram(buf, 7), 'row away from the block does not open')
    local before = #vim.api.nvim_tabpage_list_wins(0)
    ok(require('markvim').open_diagram(buf, 2), 'opens')
    eq(before + 1, #vim.api.nvim_tabpage_list_wins(0), 'a float was opened')
    local fwin = vim.api.nvim_get_current_win()
    eq('C', vim.api.nvim_buf_get_lines(0, 2, 3, false)[1]:sub(1, 1), 'art shown in the panel')
    vim.api.nvim_win_close(fwin, true)
    require('markvim.config').setup({})
    H.cleanup()
  end)
  it('opens oversized art in one panels.nvim panel per buffer', function()
    local root =
      vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p'))))
    local panels_path = vim.env.PANELS_NVIM or vim.fs.joinpath(vim.fs.dirname(root), 'panels.nvim')
    if not vim.uv.fs_stat(panels_path) then
      return print('\n  (skipped: panels.nvim not found at ' .. panels_path .. ')')
    end
    vim.opt.rtp:prepend(panels_path)
    local panels = require('panels')
    panels.setup({ backend = 'float' })
    local diagram = require('markvim.diagram')
    diagram.clear()
    require('markvim.config').setup({
      diagram = { languages = { fake = { text = { 'echo' }, image = {} } }, backend = 'text', max_height = 2 },
    })
    local buf = H.buffer({ '```fake', 'A', 'B', 'C ' .. vim.uv.hrtime(), '```' })
    vim.wait(2000, function()
      local s = require('markvim.state').get(buf)
      return s and s.diagram_blocks and #s.diagram_blocks == 1
    end, 20)
    local src = vim.api.nvim_get_current_win()
    ok(require('markvim').open_diagram(buf, 1), 'opens')
    local list = panels.list('markvim:diagram')
    eq(1, #list, 'one panel')
    local p = list[1]
    eq('fake diagram', p.title)
    eq(p.win, vim.api.nvim_get_current_win(), 'focused')
    p:hide()
    vim.api.nvim_set_current_win(src)
    ok(require('markvim').open_diagram(buf, 1), 'opens again')
    eq(1, #panels.list('markvim:diagram'), 'reused')
    ok(p:is_open())
    require('markvim').detach(buf)
    ok(not p:is_valid(), 'closed when markvim detaches')
    vim.opt.rtp:remove(panels_path)
    package.loaded.panels = nil
    require('markvim.config').setup({})
    H.cleanup()
  end)
  it('renders text art asynchronously and hides the source', function()
    local diagram = require('markvim.diagram')
    diagram.clear()
    require('markvim.config').setup({
      diagram = { languages = { fake = { text = { 'echo' }, image = {} } }, backend = 'text' },
    })
    -- unique source so the on-disk cache from a previous run does not short-circuit the async path
    local buf = H.buffer({ 'before', '```fake', 'A --> B', 'B --> C ' .. vim.uv.hrtime(), '```', 'after' })
    -- first render: pending indicator, source rendered as a normal code block
    ok(H.has(buf, 2, { pos = 'eol' }, true), 'pending indicator')
    ok(H.has(buf, 2, { line_hl = 'MarkvimCode' }, true), 'code background while pending')
    vim.wait(2000, function()
      return H.has(buf, 0, { lines = 2 }, true)
    end, 20)
    ok(H.has(buf, 0, { lines = 2, above = false }, true), 'art attached below the previous row')
    for row = 1, 4 do
      ok(H.has(buf, row, { conceal_lines = '' }), 'source row ' .. row .. ' hidden')
    end
    local marks = vim.api.nvim_buf_get_extmarks(
      buf,
      require('markvim.state').get(buf).views[1].ns_fixed,
      { 0, 0 },
      { 0, -1 },
      { details = true }
    )
    eq('A --> B', marks[1][4].virt_lines[1][1][1])
    os.remove(vim.fn.glob(vim.fn.stdpath('cache') .. '/markvim/*.txt', false, true)[1] or '')
    -- live mode: cursor inside the block reveals the whole source
    require('markvim.render').set_mode(buf, 'live')
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    require('markvim.render').cursor(buf)
    for row = 1, 4 do
      ok(not H.has(buf, row, { conceal_lines = '' }), 'source row ' .. row .. ' revealed')
    end
    ok(H.has(buf, 0, { lines = 2 }, true), 'art still shown')
    require('markvim.config').setup({})
    H.cleanup()
  end)
end)
