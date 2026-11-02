local util = require('markvim.util')
local ts = require('markvim.ts')
local M = {}

local function conceal(ctx, row, scol, ecol)
  if ecol > scol then
    ctx.add(row, scol, { end_col = ecol, conceal = '' })
    ctx.adjust(row, scol, -(ecol - scol))
  end
end

local function icon_at(ctx, row, col, icon, hl)
  if ctx.cfg.link.icons and icon and icon ~= '' then
    ctx.add(row, col, { virt_text = { { icon, hl } }, virt_text_pos = 'inline' })
    ctx.adjust(row, col, util.strwidth(icon))
  end
end

local function icon_for(ctx, dest)
  local icons = ctx.icons
  if not dest then
    return icons.link
  end
  if dest:match('^https?://') or dest:match('^www%.') then
    return icons.web
  elseif dest:match('^mailto:') then
    return icons.email
  elseif dest:match('^#') then
    return icons.link
  elseif dest:match('%.%a+$') then
    return icons.file
  end
  return icons.link
end

local function children(node)
  local out = {}
  for child in node:iter_children() do
    out[child:type()] = child
  end
  return out
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.link(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local c = children(node)
  local text, dest = c.link_text, c.link_destination
  if not text then
    return
  end
  local _, tsc, _, tec = text:range()
  conceal(ctx, sr, sc, tsc)
  conceal(ctx, sr, tec, ec)
  ctx.add(sr, tsc, { end_col = tec, hl_group = 'MarkvimLink' })
  icon_at(ctx, sr, sc, icon_for(ctx, dest and ts.text(ctx, dest) or nil), 'MarkvimLink')
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.image(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local c = children(node)
  local desc = c.image_description
  if desc then
    local _, dsc, _, dec = desc:range()
    conceal(ctx, sr, sc, dsc)
    conceal(ctx, sr, dec, ec)
    ctx.add(sr, dsc, { end_col = dec, hl_group = 'MarkvimImage' })
  else
    conceal(ctx, sr, sc, ec)
  end
  icon_at(ctx, sr, sc, ctx.icons.image, 'MarkvimImage')
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.shortcut(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local c = children(node)
  local text = c.link_text
  if not text then
    return
  end
  local line = ctx.line(sr)
  local _, tsc, _, tec = text:range()
  local inner = line:sub(tsc + 1, tec)
  if inner:sub(1, 1) == '!' then
    return -- callout, handled by the quote element
  end
  if line:sub(sc, sc) == '[' and line:sub(ec + 1, ec + 1) == ']' then
    -- [[wiki link]] or [[target|alias]]
    conceal(ctx, sr, sc - 1, tsc)
    conceal(ctx, sr, tec, ec + 1)
    local bar = inner:find('|', 1, true)
    if bar then
      conceal(ctx, sr, tsc, tsc + bar)
      ctx.add(sr, tsc + bar, { end_col = tec, hl_group = 'MarkvimLink' })
    else
      ctx.add(sr, tsc, { end_col = tec, hl_group = 'MarkvimLink' })
    end
    icon_at(ctx, sr, sc - 1, ctx.icons.wiki, 'MarkvimLink')
    return
  end
  if inner:sub(1, 1) == '^' then
    -- footnote reference [^1]
    conceal(ctx, sr, sc, tsc + 1)
    conceal(ctx, sr, tec, ec)
    ctx.add(sr, tsc + 1, { end_col = tec, hl_group = 'MarkvimLink' })
    icon_at(ctx, sr, sc, ctx.icons.footnote, 'MarkvimLink')
    return
  end
  conceal(ctx, sr, sc, tsc)
  conceal(ctx, sr, tec, ec)
  ctx.add(sr, tsc, { end_col = tec, hl_group = 'MarkvimLink' })
  icon_at(ctx, sr, sc, ctx.icons.link, 'MarkvimLink')
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.ref_link(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local c = children(node)
  local text = c.link_text
  if not text then
    return
  end
  local _, tsc, _, tec = text:range()
  conceal(ctx, sr, sc, tsc)
  conceal(ctx, sr, tec, ec)
  ctx.add(sr, tsc, { end_col = tec, hl_group = 'MarkvimLink' })
  icon_at(ctx, sr, sc, ctx.icons.link, 'MarkvimLink')
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.autolink(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  conceal(ctx, sr, sc, sc + 1)
  conceal(ctx, sr, ec - 1, ec)
  ctx.add(sr, sc + 1, { end_col = ec - 1, hl_group = 'MarkvimUrl' })
  local icon = node:type() == 'email_autolink' and ctx.icons.email or ctx.icons.web
  icon_at(ctx, sr, sc, icon, 'MarkvimLink')
end

return M
