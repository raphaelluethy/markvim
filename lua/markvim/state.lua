-- Per-buffer state. Deliberately a plain table so hot paths index it directly.
---@class markvim.View
---@field ns integer namespace for marks that are hidden on the cursor line (live mode)
---@field ns_fixed integer namespace for marks that always stay (backgrounds, virtual lines)
---@field wins integer[]|nil windows the view is scoped to; nil = all windows
---@field hybrid boolean whether the cursor line is shown raw
---@field rows table<integer, markvim.Mark[]> cached marks per row from the last render
---@field raw table<integer, boolean> rows currently shown raw
---@field tick integer changedtick the cache belongs to

---@class markvim.BufState
---@field buf integer
---@field enabled boolean
---@field mode 'live'|'preview'|'split'
---@field float boolean
---@field views markvim.View[]
---@field rendered {ranges: integer[][], tick: integer}|nil
---@field timer uv.uv_timer_t|nil
---@field parser vim.treesitter.LanguageTree|nil shared markdown parser
---@field inline vim.treesitter.LanguageTree|nil private markdown_inline tree for visible regions
---@field inline_tick integer|nil
---@field inline_ranges integer[][]|nil row ranges of the cached inline parse
---@field inline_trees table<integer, TSTree>|nil cached inline trees
---@field split {win: integer, src_win: integer}|nil
---@field win_opts table<integer, table> saved window options
---@field stats table
---@field diagrams table<string, boolean> pending diagram keys
---@field diagram_blocks table[]|nil text diagrams in the last render ({top, bottom, lang, entry, large})
---@field panel panels.Panel|table|nil panel showing a diagram (panels.nvim, or the fallback float)
---@field open_key string|nil buffer-local key that opens diagrams

local M = {}

---@type table<integer, markvim.BufState>
M.buffers = {}

---@param buf integer
---@return markvim.BufState|nil
function M.get(buf)
  return M.buffers[buf]
end

---@param buf integer
---@return markvim.BufState
function M.new(buf)
  local s = {
    buf = buf,
    enabled = true,
    mode = 'live',
    float = false,
    views = {},
    rendered = nil,
    timer = nil,
    parser = nil,
    inline = nil,
    inline_tick = nil,
    split = nil,
    win_opts = {},
    stats = {},
    diagrams = {},
  }
  M.buffers[buf] = s
  return s
end

---@param buf integer
function M.remove(buf)
  local s = M.buffers[buf]
  if s and s.timer then
    s.timer:stop()
    if not s.timer:is_closing() then
      s.timer:close()
    end
  end
  M.buffers[buf] = nil
end

return M
