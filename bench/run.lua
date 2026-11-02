-- Benchmark: nvim --headless --clean -l bench/run.lua <file.md> [iterations]
-- Measures compute (parse + query + mark building) and apply (extmark) costs
-- for the viewport at several offsets, plus the cursor-move (hybrid) path.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(root)
vim.cmd('runtime plugin/markvim.lua')
local file, iters = arg[1], tonumber(arg[2]) or 50
vim.o.lines, vim.o.columns = 50, 120

local function ms(t)
  return t / 1e6
end

local t_open = vim.uv.hrtime()
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
local render = require('markvim.render')
local state = require('markvim.state')
local s = assert(state.get(buf), 'not attached')
local t_attached = vim.uv.hrtime()
local lines = vim.api.nvim_buf_line_count(buf)
io.write(('file: %s (%d lines)\n'):format(vim.fs.basename(file), lines))
io.write(
  ('open + attach + first render: %.2f ms (compute %.2f, apply %.2f, %d marks)\n'):format(
    ms(t_attached - t_open),
    s.stats.compute_ms or 0,
    s.stats.apply_ms or 0,
    s.stats.marks or 0
  )
)

-- Full parse cost (first parse of the whole document happens lazily; measure it explicitly).
local parser = vim.treesitter.get_parser(buf, 'markdown')
local t0 = vim.uv.hrtime()
parser:parse(true)
io.write(('full treesitter parse: %.2f ms\n'):format(ms(vim.uv.hrtime() - t0)))

local function bench_at(row)
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd('normal! zt')
  -- warm up
  render.render(buf, true)
  local total_c, total_a, marks = 0, 0, 0
  for _ = 1, iters do
    render.render(buf, true)
    total_c = total_c + s.stats.compute_ms
    total_a = total_a + s.stats.apply_ms
    marks = s.stats.marks
  end
  io.write(
    ('  viewport at row %6d: compute %.3f ms, apply %.3f ms (%d marks, rows %s) [viewport %.3f, parse %.3f, inline %.3f, elements %.3f]\n'):format(
      row,
      total_c / iters,
      total_a / iters,
      marks,
      vim.inspect(s.stats.ranges, { newline = '', indent = '' }),
      s.stats.viewport_ms,
      s.stats.phases.parse,
      s.stats.phases.inline_parse,
      s.stats.phases.elements
    )
  )
end
io.write('forced full viewport render (avg over ' .. iters .. '):\n')
for _, row in ipairs({ 0, math.floor(lines / 2), math.max(0, lines - 60) }) do
  if row < lines then
    bench_at(row)
  end
end

-- No-op render (nothing changed): should be nearly free.
t0 = vim.uv.hrtime()
for _ = 1, iters do
  render.render(buf, false)
end
io.write(('no-op render (cached): %.4f ms\n'):format(ms(vim.uv.hrtime() - t0) / iters))

-- Cursor moves in live mode.
s.mode = 'live'
render.set_mode(buf, 'live')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
render.render(buf, true)
t0 = vim.uv.hrtime()
local row = 1
for _ = 1, iters * 4 do
  row = row % 30 + 1
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  render.cursor(buf)
end
io.write(('cursor move (hybrid update): %.4f ms\n'):format(ms(vim.uv.hrtime() - t0) / (iters * 4)))

-- Edit + re-render. The first number includes tree-sitter-markdown's re-parse
-- of the block tree, which the built-in highlighter performs on redraw anyway;
-- the second measures only markvim's work after that parse.
local n_edit = math.max(3, math.floor(iters / 5))
t0 = vim.uv.hrtime()
for i = 1, n_edit do
  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { 'edited line ' .. i .. ' with **bold** text' })
  render.render(buf, false)
end
io.write(('edit one line + render (incl. treesitter re-parse): %.3f ms\n'):format(ms(vim.uv.hrtime() - t0) / n_edit))
local total = 0
for i = 1, n_edit do
  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { 'edited line ' .. i .. ' with *italic* text' })
  parser:parse({ { 0, 0, 60, 0 } }) -- what the highlighter does on redraw
  vim.fn.line('w$') -- the redraw also validates botline (triggers the highlighter's conceal_lines pass)
  local t1 = vim.uv.hrtime()
  render.render(buf, false)
  total = total + (vim.uv.hrtime() - t1)
end
io.write(
  ('edit one line + render (markvim only): %.3f ms [last: viewport %.3f, parse %.3f, inline %.3f, elements %.3f, apply %.3f]\n'):format(
    ms(total) / n_edit,
    s.stats.viewport_ms,
    s.stats.phases.parse,
    s.stats.phases.inline_parse,
    s.stats.phases.elements,
    s.stats.apply_ms
  )
)

collectgarbage('collect')
io.write(('lua memory: %.1f MB\n'):format(collectgarbage('count') / 1024))
vim.cmd('qa!')
