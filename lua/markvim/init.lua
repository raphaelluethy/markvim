---@class markvim
local M = {}

local function bufnr(buf)
  if not buf or buf == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return buf
end

---Configure markvim. Optional: the plugin works with defaults and attaches to
---`markdown` buffers automatically.
---@param opts markvim.Config|nil
function M.setup(opts)
  local config = require('markvim.config')
  config.setup(opts)
  -- Re-register the FileType autocmd in case `filetypes` changed.
  local group = vim.api.nvim_create_augroup('markvim.attach', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = config.get().filetypes,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  -- Attach to already-open buffers of the configured filetypes.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(config.get().filetypes, vim.bo[buf].filetype) then
      M.attach(buf)
    end
  end
end

---Attach markvim to a buffer and render it.
---@param buf integer|nil
function M.attach(buf)
  return require('markvim.render').attach(bufnr(buf))
end

---Detach from a buffer and remove all rendering.
---@param buf integer|nil
function M.detach(buf)
  return require('markvim.render').detach(bufnr(buf))
end

---@param buf integer|nil
function M.enable(buf)
  return require('markvim.render').set_enabled(bufnr(buf), true)
end

---@param buf integer|nil
function M.disable(buf)
  return require('markvim.render').set_enabled(bufnr(buf), false)
end

---@param buf integer|nil
function M.toggle(buf)
  return require('markvim.render').toggle(bufnr(buf))
end

---Switch rendering mode for a buffer.
---@param mode 'live'|'preview'|'split'
---@param buf integer|nil
function M.set_mode(mode, buf)
  return require('markvim.render').set_mode(bufnr(buf), mode)
end

---Force a synchronous render of the visible area.
---@param buf integer|nil
function M.render(buf)
  return require('markvim.render').render(bufnr(buf), true)
end

---Open the diagram under the cursor (or at `row`, 0-based) in a floating panel.
---@param buf integer|nil
---@param row integer|nil
---@return boolean opened
function M.open_diagram(buf, row)
  return require('markvim.diagram').open_at(bufnr(buf), row)
end

---Current mode of an attached buffer ('live' | 'preview' | 'split'), or nil.
---@param buf integer|nil
---@return string|nil
function M.mode(buf)
  local s = require('markvim.state').get(bufnr(buf))
  return s and s.mode or nil
end

---@param buf integer|nil
---@return boolean
function M.is_attached(buf)
  return require('markvim.state').get(bufnr(buf)) ~= nil
end

---Render arbitrary markdown lines into a scratch buffer (for plugin authors:
---chat UIs, custom hovers, ...). Returns the buffer; show it in any window.
---@param lines string[]
---@param opts {buf?: integer, mode?: 'preview'|'live'}|nil
---@return integer buf
function M.render_lines(lines, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = vim.bo[buf].bufhidden ~= '' and vim.bo[buf].bufhidden or 'wipe'
  vim.b[buf].markvim_mode = opts.mode or 'preview'
  vim.bo[buf].filetype = 'markdown' -- triggers attach
  return buf
end

return M
