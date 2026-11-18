local api = vim.api
local M = {}

local subcommands =
  { 'toggle', 'enable', 'disable', 'live', 'preview', 'split', 'render', 'open', 'debug', 'install', 'health' }

---@param cmd vim.api.keyset.create_user_command.command_args
function M.run(cmd)
  local args = cmd.fargs
  local sub = args[1] or 'toggle'
  local buf = api.nvim_get_current_buf()
  local mv = require('markvim')
  if sub == 'enable' then
    mv.enable(buf)
  elseif sub == 'disable' then
    mv.disable(buf)
  elseif sub == 'toggle' then
    mv.toggle(buf)
  elseif sub == 'live' or sub == 'preview' or sub == 'split' then
    if not mv.is_attached(buf) then
      if not mv.attach(buf) then
        vim.notify('markvim: cannot attach to this buffer', vim.log.levels.WARN)
        return
      end
    end
    mv.enable(buf)
    if sub ~= 'live' and not cmd.bang and mv.mode(buf) == sub then
      mv.set_mode('live', buf) -- toggle back
    else
      mv.set_mode(sub, buf)
    end
  elseif sub == 'render' then
    mv.render(buf)
  elseif sub == 'open' then
    if not mv.open_diagram(buf) then
      vim.notify('markvim: no diagram under the cursor', vim.log.levels.INFO)
    end
  elseif sub == 'debug' then
    require('markvim.debug').show(buf)
  elseif sub == 'install' then
    require('markvim.diagram').install(args[2])
  elseif sub == 'health' then
    vim.cmd('checkhealth markvim')
  else
    vim.notify(('markvim: unknown subcommand %q'):format(sub), vim.log.levels.ERROR)
  end
end

function M.complete(lead, line)
  local words = vim.split(line, '%s+', { trimempty = true })
  if #words > 2 or (#words == 2 and lead == '') then
    if words[2] == 'install' then
      return vim.tbl_filter(function(s)
        return s:find(lead, 1, true) == 1
      end, { 'node', 'all' })
    end
    return {}
  end
  return vim.tbl_filter(function(s)
    return s:find(lead, 1, true) == 1
  end, subcommands)
end

return M
