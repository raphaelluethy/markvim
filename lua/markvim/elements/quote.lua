local util = require('markvim.util')
local ts = require('markvim.ts')
local M = {}

---Column of the n-th `>` in the leading `[ >]*` part of a line, or nil.
local function nth_marker(line, n)
  local count = 0
  for i = 1, #line do
    local c = line:byte(i)
    if c == 62 then -- '>'
      count = count + 1
      if count == n then
        return i - 1
      end
    elseif c ~= 32 and c ~= 9 then
      return nil
    end
  end
  return nil
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.quote(ctx, node)
  local sr, sc, er, ec = node:range()
  local last = ec == 0 and er - 1 or er
  local level = ts.depth(node, 'block_quote') + 1
  local hl = 'MarkvimQuote'
  local first = ctx.line(sr)

  if ctx.cfg.callout.enabled then
    local bs, be, kind = first:find('%[!(%w+)%]', sc + 1)
    if bs and first:sub(sc + 1, bs - 1):match('^%s*>%s*$') then
      local lower = kind:lower()
      hl = require('markvim.hl').callout(lower)
      local e = be
      local fold = first:sub(be + 1, be + 1)
      if fold == '-' or fold == '+' then
        e = e + 1
      end
      local title = first:sub(e + 1)
      local icon = ctx.icons.callout[lower] or ctx.icons.callout.note or ''
      -- `[!NOTE] title` keeps the user's title (and its leading space);
      -- `[!NOTE]` alone gets a generated title.
      local text = icon
      if title:match('^%s*$') then
        text = (icon ~= '' and (icon .. ' ') or '') .. util.capitalize(lower)
      end
      ctx.add(sr, bs - 1, { end_col = e, conceal = '' })
      if text ~= '' then
        ctx.add(sr, bs - 1, { virt_text = { { text, hl } }, virt_text_pos = 'inline' })
      end
      if #title > 0 then
        ctx.add(sr, e, { end_col = #first, hl_group = hl })
      end
    end
  end

  if not ctx.cfg.quote.enabled then
    return
  end
  local bar = ctx.icons.quote
  for row = sr, last do
    local line = row == sr and first or ctx.line(row)
    local col = nth_marker(line, level)
    if col then
      ctx.add(row, col, { end_col = col + 1, virt_text = { { bar, hl } }, virt_text_pos = 'overlay' })
    end
  end
end

return M
