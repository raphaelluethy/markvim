local M = {}

---@param ctx markvim.Ctx
---@param node TSNode
function M.html(ctx, node)
  if not ctx.cfg.html.comments then
    return
  end
  local sr, sc, er, ec = node:range()
  local last = ec == 0 and er - 1 or er
  local first = ctx.line(sr)
  if not first:sub(sc + 1):match('^<!%-%-') then
    return
  end
  if sr == last then
    local _, e = first:find('%-%->', sc + 1)
    ctx.add(sr, sc, { end_col = e or #first, conceal = '' })
    ctx.add(sr, sc, { end_col = e or #first, hl_group = 'MarkvimHtml' })
  else
    for row = sr, last do
      ctx.add(row, 0, { conceal_lines = '' })
    end
  end
end

return M
