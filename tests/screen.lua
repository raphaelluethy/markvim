-- Screen harness: runs a child Neovim (with this plugin on the runtimepath) inside
-- a terminal buffer and returns the rendered screen as plain text.
--
--   nvim --headless --clean -l tests/screen.lua <file.md> [width] [height] [wait_ms] [keys...]
--
-- Also usable as a module from tests: require('tests.screen').run(opts)
local M = {}

local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
local ESC, BEL, NL = string.char(27), string.char(7), string.char(10)

---@param opts {file?: string, lines?: string[], width?: integer, height?: integer, wait?: integer, keys?: string[], init?: string, setup?: string, messages?: string}
---@return string[][] snapshots one list of screen lines per step
function M.run(opts)
  local width, height = opts.width or 70, opts.height or 16
  local wait = opts.wait or 600
  -- Size the (headless) UI so the terminal emulator matches the child's pty.
  vim.o.laststatus = 0
  vim.o.cmdheight = 1
  vim.o.columns = width
  vim.o.lines = height + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  -- The terminal emulator follows the window; the child's pty must match it.
  width = vim.api.nvim_win_get_width(0)
  height = vim.api.nvim_win_get_height(0)
  local term = vim.api.nvim_open_term(buf, {})
  local file = opts.file
  if opts.lines then
    file = vim.fn.tempname() .. '.md'
    vim.fn.writefile(opts.lines, file)
  end
  local setup = opts.setup or 'require("markvim").setup({})'
  local init = ('set rtp^=%s | set rtp+=%s/after | lua %s'):format(root, root, setup)
  local cmd = {
    'nvim',
    '--clean',
    '-u',
    'NONE',
    '-i',
    'NONE',
    '-n',
    '--cmd',
    'set background=dark laststatus=0 noshowcmd noruler shortmess+=I nowrap number',
    '--cmd',
    init,
  }
  if opts.init then
    table.insert(cmd, '--cmd')
    table.insert(cmd, opts.init)
  end
  if opts.messages then
    table.insert(cmd, '-c')
    table.insert(
      cmd,
      ('lua vim.defer_fn(function() vim.fn.writefile(vim.split(vim.fn.execute("messages"), string.char(10)), %q) end, %d)'):format(
        opts.messages,
        math.max(100, wait - 100)
      )
    )
  end
  table.insert(cmd, file)
  local job = vim.fn.jobstart(cmd, {
    pty = true,
    width = width,
    height = height,
    env = { TERM = 'xterm-256color', NVIM_NOTTYFAST = '1' },
    on_stdout = function(job_id, data)
      local chunk = table.concat(data, NL)
      -- Answer the background-color query so the child does not wait for it.
      if chunk:find(ESC .. ']11;?', 1, true) then
        vim.fn.chansend(job_id, ESC .. ']11;rgb:1e1e/1e1e/1e1e' .. BEL)
      end
      vim.api.nvim_chan_send(term, chunk)
    end,
  })
  local snaps = {}
  local function snap()
    vim.wait(wait, function()
      return false
    end)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, height, false)
    for i, l in ipairs(lines) do
      lines[i] = l:gsub('%s+$', '')
    end
    snaps[#snaps + 1] = lines
  end
  snap()
  for _, k in ipairs(opts.keys or {}) do
    -- Allow readable escapes on the command line: \r, \n, \e, <Esc>, <CR>.
    k = k:gsub('\\r', '\r'):gsub('\\n', '\n'):gsub('\\e', ESC):gsub('<Esc>', ESC):gsub('<CR>', '\r')
    vim.fn.chansend(job, k)
    snap()
  end
  vim.fn.jobstop(job)
  return snaps
end

if arg and arg[0] and arg[0]:match('screen%.lua$') then
  local keys = {}
  for i = 5, #arg do
    keys[#keys + 1] = arg[i]
  end
  local msgfile = vim.fn.tempname()
  local snaps = M.run({
    file = arg[1],
    width = tonumber(arg[2]),
    height = tonumber(arg[3]),
    wait = tonumber(arg[4]),
    keys = keys,
    messages = msgfile,
  })
  for i, s in ipairs(snaps) do
    io.write(('--- step %d ---\n'):format(i))
    for n, l in ipairs(s) do
      io.write(('%2d|%s\n'):format(n, l))
    end
  end
  if vim.fn.filereadable(msgfile) == 1 then
    local msgs = vim.fn.readfile(msgfile)
    if #msgs > 0 and table.concat(msgs) ~= '' then
      io.write('--- messages ---\n' .. table.concat(msgs, '\n') .. '\n')
    end
  end
  vim.cmd('qa!')
end

return M
