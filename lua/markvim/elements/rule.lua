local util = require('markvim.util')
local M = {}

---@param ctx markvim.Ctx
---@param node TSNode
function M.rule(ctx, node)
  local sr = node:range()
  local line = ctx.line(sr)
  ctx.add(sr, 0, { end_col = #line, conceal = '' })
  ctx.add(sr, 0, {
    virt_text = { { util.fill(ctx.icons.rule, ctx.width), 'MarkvimRule' } },
    virt_text_pos = 'inline',
  })
end

return M
