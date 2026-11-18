-- markvim: entry point. Kept tiny on purpose; everything else loads on demand.
if vim.g.loaded_markvim then
  return
end
vim.g.loaded_markvim = true

if vim.fn.has('nvim-0.12') == 0 then
  vim.schedule(function()
    vim.notify('markvim requires Neovim 0.12+', vim.log.levels.WARN)
  end)
  return
end

local group = vim.api.nvim_create_augroup('markvim.attach', { clear = true })

-- Filetypes can be overridden before load through `vim.g.markvim = { filetypes = {...} }`
-- or later through `require('markvim').setup()`, which re-registers this autocmd.
local fts = (type(vim.g.markvim) == 'table' and vim.g.markvim.filetypes) or { 'markdown' }
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = fts,
  callback = function(ev)
    require('markvim').attach(ev.buf)
  end,
})

vim.api.nvim_create_user_command('Markvim', function(cmd)
  require('markvim.command').run(cmd)
end, {
  nargs = '*',
  bang = true,
  desc = 'markvim: enable | disable | toggle | live | preview | split | render | debug',
  complete = function(arg_lead, cmd_line)
    return require('markvim.command').complete(arg_lead, cmd_line)
  end,
})
