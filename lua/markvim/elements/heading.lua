local util = require('markvim.util')
local M = {}

---@param ctx markvim.Ctx
---@param node TSNode
function M.heading(ctx, node)
  local cfg = ctx.cfg.heading
  local sr = node:range()
  local line = ctx.line(sr)
  if node:type() == 'atx_heading' then
    local marker = node:child(0)
    if not marker then
      return
    end
    local level = tonumber(marker:type():match('atx_h(%d)_marker')) or 1
    local _, msc, _, mec = marker:range()
    local after = mec
    if line:sub(mec + 1, mec + 1) == ' ' then
      after = mec + 1
    end
    local hl = 'MarkvimH' .. level
    local icon
    if cfg.icons == true then
      icon = ctx.icons.heading[level]
    elseif type(cfg.icons) == 'table' then
      icon = cfg.icons[level]
    end
    if ctx.cfg.icons == 'ascii' then
      icon = nil
    end
    if icon and icon ~= '' then
      if cfg.position == 'overlay' then
        ctx.add(sr, msc, {
          end_col = after,
          virt_text = { { util.lpad(icon, after - msc), hl } },
          virt_text_pos = 'overlay',
        })
      else
        ctx.add(sr, msc, { end_col = after, conceal = '' })
        ctx.add(sr, msc, { virt_text = { { icon, hl } }, virt_text_pos = 'inline' })
        ctx.adjust(sr, msc, util.strwidth(icon) - (after - msc))
      end
    elseif cfg.position == 'inline' and ctx.cfg.icons ~= 'ascii' then
      ctx.add(sr, msc, { end_col = after, conceal = '' })
      ctx.adjust(sr, msc, -(after - msc))
    end
    if cfg.background then
      local bg = 'MarkvimH' .. level .. 'Bg'
      if cfg.background == 'full' then
        ctx.fix(sr, 0, { line_hl_group = bg })
      else
        ctx.fix(sr, msc, { end_col = #line, hl_group = bg })
      end
    end
  else
    -- setext heading: paragraph + underline
    local count = node:named_child_count()
    local underline = count > 0 and node:named_child(count - 1) or nil
    if not underline then
      return
    end
    local level = underline:type() == 'setext_h1_underline' and 1 or 2
    local usr = underline:range()
    if cfg.setext and ctx.cfg.icons ~= 'ascii' then
      local uline = ctx.line(usr)
      ctx.add(usr, 0, { end_col = #uline, conceal = '' })
      ctx.add(usr, 0, {
        virt_text = { { util.fill(ctx.icons.rule, ctx.width), 'MarkvimH' .. level } },
        virt_text_pos = 'inline',
      })
    end
    if cfg.background then
      local bg = 'MarkvimH' .. level .. 'Bg'
      for row = sr, usr - 1 do
        ctx.fix(row, 0, { line_hl_group = bg })
      end
    end
  end
end

return M
