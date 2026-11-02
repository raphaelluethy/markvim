local M = {}

local function conceal(ctx, row, scol, ecol)
  if ecol > scol then
    ctx.add(row, scol, { end_col = ecol, conceal = '' })
    ctx.adjust(row, scol, -(ecol - scol))
  end
end

-- Delimiters come as one node per character (`**` is two nodes); merge
-- adjacent ones into a single conceal mark.
local function conceal_delimiters(ctx, node, kind, hl)
  local sr, sc, er, ec = node:range()
  local prow, pstart, pend
  for child in node:iter_children() do
    if child:type() == kind then
      local dsr, dsc, der, dec = child:range()
      if dsr == der then
        if prow == dsr and pend == dsc then
          pend = dec
        else
          if prow then
            conceal(ctx, prow, pstart, pend)
          end
          prow, pstart, pend = dsr, dsc, dec
        end
      end
    end
  end
  if prow then
    conceal(ctx, prow, pstart, pend)
  end
  if hl and sr == er then
    ctx.add(sr, sc, { end_col = ec, hl_group = hl })
  end
end

---@param ctx markvim.Ctx
---@param node TSNode
function M.code_span(ctx, node)
  conceal_delimiters(ctx, node, 'code_span_delimiter', 'MarkvimCodeInline')
end

function M.emphasis(ctx, node)
  conceal_delimiters(ctx, node, 'emphasis_delimiter')
end

function M.strong(ctx, node)
  conceal_delimiters(ctx, node, 'emphasis_delimiter')
end

function M.strike(ctx, node)
  -- `~~x~~` parses as nested strikethrough nodes; handle only the outermost
  -- and let conceal_delimiters merge the adjacent delimiter characters.
  local parent = node:parent()
  if parent and parent:type() == 'strikethrough' then
    return
  end
  local sr, sc, er, ec = node:range()
  local inner = node:named_child(0)
  while inner and inner:type() == 'emphasis_delimiter' do
    inner = inner:next_named_sibling()
  end
  if inner and inner:type() == 'strikethrough' then
    local isr, isc, ier, iec = inner:range()
    -- opening run: sc .. first non-delimiter of the inner node
    local open_end, close_start = isc, iec
    for child in inner:iter_children() do
      if child:type() == 'emphasis_delimiter' then
        local dsr, dsc, der, dec = child:range()
        if dsr == isr and dsc == open_end then
          open_end = dec
        elseif der == ier then
          close_start = math.min(close_start, dsc)
        end
      end
    end
    if sr == isr then
      ctx.add(sr, sc, { end_col = open_end, conceal = '' })
      ctx.adjust(sr, sc, -(open_end - sc))
    end
    if er == ier then
      ctx.add(er, close_start, { end_col = ec, conceal = '' })
      ctx.adjust(er, close_start, -(ec - close_start))
    end
    if sr == er then
      ctx.add(sr, sc, { end_col = ec, hl_group = 'MarkvimStrike' })
    end
    return
  end
  conceal_delimiters(ctx, node, 'emphasis_delimiter', 'MarkvimStrike')
end

function M.escape(ctx, node)
  local sr, sc = node:range()
  conceal(ctx, sr, sc, sc + 1)
end

function M.latex(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr == er then
    ctx.add(sr, sc, { end_col = ec, hl_group = 'MarkvimMath' })
  end
end

function M.html_tag(ctx, node)
  if not ctx.cfg.inline.html then
    return
  end
  local sr, sc, er, ec = node:range()
  if sr == er then
    conceal(ctx, sr, sc, ec)
  end
end

function M.hard_break(ctx, node)
  if not ctx.cfg.inline.hard_break then
    return
  end
  local sr, sc = node:range()
  ctx.add(sr, sc, {
    virt_text = { { ctx.icons.hard_break, 'MarkvimHardBreak' } },
    virt_text_pos = 'overlay',
  })
end

return M
