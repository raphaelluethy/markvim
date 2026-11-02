local util = require('markvim.util')
local ts = require('markvim.ts')
local M = {}

---@param ctx markvim.Ctx
---@param node TSNode
function M.list_item(ctx, node)
  local marker = node:child(0)
  if not marker then
    return
  end
  local mtype = marker:type()
  local sr, sc, _, ec = marker:range()
  local line = ctx.line(sr)
  local cb = ctx.cfg.checkbox

  if cb.enabled then
    local box_s, box_e, icon, hl
    local task = node:child(1)
    local ttype = task and task:type()
    if ttype == 'task_list_marker_unchecked' or ttype == 'task_list_marker_checked' then
      local _, tsc, _, tec = task:range()
      box_s, box_e = tsc, tec
      if ttype == 'task_list_marker_checked' then
        icon, hl = ctx.icons.checked, 'MarkvimChecked'
      else
        icon, hl = ctx.icons.unchecked, 'MarkvimUnchecked'
      end
    elseif cb.custom then
      local raw = line:sub(ec + 1, ec + 3)
      local custom = cb.custom[raw]
      if custom and line:sub(ec + 4, ec + 4):match('^%s?$') then
        box_s, box_e = ec, ec + 3
        icon, hl = custom.icon, custom.hl or 'MarkvimTodo'
      end
    end
    if box_s then
      local e = box_e
      if line:sub(e + 1, e + 1) == ' ' then
        e = e + 1
      end
      ctx.add(sr, sc, { end_col = e, conceal = '' })
      ctx.add(sr, sc, { virt_text = { { icon .. ' ', hl } }, virt_text_pos = 'inline' })
      ctx.adjust(sr, sc, util.strwidth(icon) + 1 - (e - sc))
      return
    end
  end

  local cfg = ctx.cfg.bullet
  if not cfg.enabled then
    return
  end
  if mtype == 'list_marker_minus' or mtype == 'list_marker_plus' or mtype == 'list_marker_star' then
    local icons = cfg.icons or ctx.icons.bullet
    local depth = ts.depth(node, 'list')
    local icon = icons[((depth - 1) % #icons) + 1]
    ctx.add(sr, sc, {
      end_col = sc + 1,
      virt_text = { { icon, 'MarkvimBullet' } },
      virt_text_pos = 'overlay',
    })
  elseif cfg.ordered and (mtype == 'list_marker_dot' or mtype == 'list_marker_parenthesis') then
    ctx.add(sr, sc, { end_col = ec, hl_group = 'MarkvimOrdered' })
  end
end

return M
