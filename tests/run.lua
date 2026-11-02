-- Minimal test runner: nvim --headless --clean -l tests/run.lua [pattern]
-- Specs live in tests/spec/*_spec.lua and use the tiny `describe/it/eq` API below.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.cmd('runtime plugin/markvim.lua')

local T = { passed = 0, failed = 0, failures = {} }
local current

function _G.describe(name, fn)
  current = name
  fn()
end

function _G.it(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    T.passed = T.passed + 1
    io.write('.')
  else
    T.failed = T.failed + 1
    io.write('F')
    T.failures[#T.failures + 1] = ('%s :: %s\n%s'):format(current, name, err)
  end
end

function _G.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(('%sexpected %s, got %s'):format(msg and (msg .. ': ') or '', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function _G.ok(value, msg)
  if not value then
    error(msg or 'expected truthy value', 2)
  end
end

-- Helpers ------------------------------------------------------------------
_G.H = {}

---Create a markdown buffer with lines, show it in the current window, attach and render.
---@return integer buf, markvim.BufState state
function H.buffer(lines, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  -- Default to preview so the cursor row is rendered too; pass mode = 'live' to test hybrid behaviour.
  vim.b[buf].markvim_mode = opts.mode or 'preview'
  vim.bo[buf].filetype = 'markdown'
  local s = require('markvim.state').get(buf)
  assert(s, 'markvim did not attach')
  require('markvim.render').render(buf, true)
  return buf, s
end

---Marks on a row from a view namespace (details included), sorted by col.
function H.marks(buf, row, fixed)
  local s = require('markvim.state').get(buf)
  local ns = fixed and s.views[1].ns_fixed or s.views[1].ns
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
  local out = {}
  for _, m in ipairs(marks) do
    local d = m[4]
    out[#out + 1] = {
      col = m[3],
      end_col = d.end_col,
      conceal = d.conceal,
      conceal_lines = d.conceal_lines,
      hl = d.hl_group,
      line_hl = d.line_hl_group,
      text = d.virt_text and table.concat(vim.tbl_map(function(c)
        return c[1]
      end, d.virt_text)) or nil,
      pos = d.virt_text_pos,
      lines = d.virt_lines and #d.virt_lines or nil,
      above = d.virt_lines_above,
    }
  end
  table.sort(out, function(a, b)
    return a.col < b.col
  end)
  return out
end

---Does any mark on the row match the (partial) spec?
function H.has(buf, row, spec, fixed)
  for _, m in ipairs(H.marks(buf, row, fixed)) do
    local match = true
    for k, v in pairs(spec) do
      if m[k] ~= v then
        match = false
        break
      end
    end
    if match then
      return true
    end
  end
  return false
end

function H.count(buf, row, fixed)
  return #H.marks(buf, row, fixed)
end

function H.cleanup()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if require('markvim.state').get(buf) then
      require('markvim.render').detach(buf)
    end
  end
end

-- Run -----------------------------------------------------------------------
local pattern = arg[1]
local files = vim.fn.glob(root .. '/tests/spec/*_spec.lua', false, true)
table.sort(files)
for _, f in ipairs(files) do
  if not pattern or f:find(pattern, 1, true) then
    io.write(vim.fs.basename(f) .. ' ')
    local ok, err = xpcall(dofile, debug.traceback, f)
    if not ok then
      T.failed = T.failed + 1
      T.failures[#T.failures + 1] = f .. '\n' .. err
    end
    io.write('\n')
  end
end
io.write(('\n%d passed, %d failed\n'):format(T.passed, T.failed))
for _, f in ipairs(T.failures) do
  io.write('\n' .. f .. '\n')
end
vim.cmd(T.failed > 0 and 'cquit 1' or 'qa!')
