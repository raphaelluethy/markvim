-- Placeholder; real implementation lives in markvim.diagram and is wired here.
local M = {}

---@return boolean handled
function M.code(ctx, node, lang, rows)
  local ok, diagram = pcall(require, 'markvim.diagram')
  if not ok then
    return false
  end
  return diagram.render_block(ctx, node, lang, rows)
end

return M
