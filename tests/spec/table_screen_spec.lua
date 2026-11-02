local screen = dofile(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))) .. '/screen.lua')

describe('table screen rendering', function()
  it('wraps the reported Actor table inside aligned bounded columns', function()
    local snapshots = screen.run({
      width = 80,
      height = 20,
      wait = 800,
      lines = {
        '| Actor | Role |',
        '|---|---|',
        "| Stage Agents | Assess the request within their stage's boundary and permitted evidence |",
        '| Judge Agent | Reviews every completed stage; its validated verdict, not a heuristic, controls progression |',
        '| Reviewer | Submits, clarifies, resolves escalations, validates the final allocation. Every escalation returns here; the Judge cannot replace this authority. |',
        '',
        'after',
      },
      setup = 'require("markvim").setup({ mode = "preview", icons = "unicode" })',
      init = 'set wrap list listchars=space:· nonumber | filetype plugin on | autocmd FileType markdown lua vim.treesitter.start()',
    })
    local rendered = snapshots[1]
    local expected = {
      '┌──────────────┬───────────────────────────────────────────────────────────────┐',
      '│ Actor        │ Role                                                          │',
      '├──────────────┼───────────────────────────────────────────────────────────────┤',
      "│ Stage Agents │ Assess the request within their stage's boundary and          │",
      '│              │ permitted evidence                                            │',
      '│ Judge Agent  │ Reviews every completed stage; its validated verdict, not a   │',
      '│              │ heuristic, controls progression                               │',
      '│ Reviewer     │ Submits, clarifies, resolves escalations, validates the final │',
      '│              │ allocation. Every escalation returns here; the Judge cannot   │',
      '│              │ replace this authority.                                       │',
      '└──────────────┴───────────────────────────────────────────────────────────────┘',
    }
    for i, line in ipairs(expected) do
      eq(line, rendered[i], 'rendered table line ' .. i)
      eq(80, vim.fn.strdisplaywidth(rendered[i]), 'bounded table line ' .. i)
    end
    local joined = table.concat(rendered, '\n')
    ok(not joined:find('|', 1, true), 'no raw pipes leak through')
    ok(not joined:find('%-%-%-'), 'raw delimiter does not leak through')
  end)

  it('reflows formatter padding, inline markup, Unicode and missing edge pipes', function()
    local snapshots = screen.run({
      width = 80,
      height = 18,
      wait = 800,
      lines = {
        'Actor                                           | Role',
        '------------------------------------------------|:---:',
        '**Stage Agents**                                | Handles café 🚀 requests and preserves every detail while wrapping.',
        'Reviewer                                        | Final authority',
        '',
      },
      setup = 'require("markvim").setup({ mode = "preview", icons = "unicode" })',
      init = 'set wrap list listchars=space:· nonumber | filetype plugin on | autocmd FileType markdown lua vim.treesitter.start()',
    })
    local rendered = snapshots[1]
    eq('│ Stage Agents │   Handles café 🚀 requests and preserves every detail while   │', rendered[4])
    eq('│              │                           wrapping.                           │', rendered[5])
    eq('│ Reviewer     │                        Final authority                        │', rendered[6])
    for i = 1, 7 do
      eq(80, vim.fn.strdisplaywidth(rendered[i]), 'bounded padded table line ' .. i)
    end
    local joined = table.concat(rendered, '\n')
    ok(not joined:find('**', 1, true), 'inline delimiters stay concealed')
    ok(not joined:find('|', 1, true), 'missing edge pipes do not leak')
    ok(not joined:find('···', 1, true), 'formatter padding does not leak through listchars')
  end)

  it('renders an overflowing table that occupies the entire buffer', function()
    local snapshots = screen.run({
      width = 80,
      height = 12,
      wait = 800,
      lines = {
        '| A | B |',
        '|---|---|',
        '| Alpha | This is a long value that needs to wrap within its own column cleanly. |',
      },
      setup = 'require("markvim").setup({ mode = "preview", icons = "unicode" })',
      init = 'set wrap nonumber',
    })
    local rendered = snapshots[1]
    eq(
      '┌───────┬──────────────────────────────────────────────────────────────────────┐',
      rendered[1]
    )
    eq('│ Alpha │ This is a long value that needs to wrap within its own column        │', rendered[4])
    eq('│       │ cleanly.                                                             │', rendered[5])
    eq(
      '└───────┴──────────────────────────────────────────────────────────────────────┘',
      rendered[6]
    )
  end)
end)
