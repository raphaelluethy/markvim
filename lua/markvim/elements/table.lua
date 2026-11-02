local util = require('markvim.util')
local M = {}

---Boundaries (pipe columns) of a table row. Missing leading/trailing pipes
---get virtual boundaries so cells are always `bounds[i]+1 .. bounds[i+1]`.
local function row_bounds(row_node)
  local sr, sc, _, ec = row_node:range()
  local pipes = {}
  for child in row_node:iter_children() do
    if child:type() == '|' then
      local _, c = child:range()
      pipes[#pipes + 1] = c
    end
  end
  local bounds, real = {}, {}
  if #pipes == 0 or pipes[1] ~= sc then
    bounds[1], real[1] = sc - 1, false
  end
  for _, p in ipairs(pipes) do
    bounds[#bounds + 1], real[#real + 1] = p, true
  end
  if #pipes == 0 or pipes[#pipes] ~= ec - 1 then
    bounds[#bounds + 1], real[#real + 1] = ec, false
  end
  return sr, bounds, real
end

---@param ctx markvim.Ctx
---@param node TSNode
M['table'] = function(ctx, node)
  local cfg = ctx.cfg.table
  local rows, aligns = {}, {}
  for child in node:iter_children() do
    local t = child:type()
    if t == 'pipe_table_header' or t == 'pipe_table_row' or t == 'pipe_table_delimiter_row' then
      local sr, bounds, real = row_bounds(child)
      rows[#rows + 1] = { row = sr, bounds = bounds, real = real, delim = t == 'pipe_table_delimiter_row' }
      if t == 'pipe_table_delimiter_row' then
        local i = 0
        for cell in child:iter_children() do
          if cell:type() == 'pipe_table_delimiter_cell' then
            i = i + 1
            local l, r = false, false
            for a in cell:iter_children() do
              local at = a:type()
              if at == 'pipe_table_align_left' then
                l = true
              elseif at == 'pipe_table_align_right' then
                r = true
              end
            end
            aligns[i] = (l and r) and 'center' or (r and 'right') or 'left'
          end
        end
      end
    end
  end
  if #rows == 0 then
    return
  end

  local widths = {}
  for _, r in ipairs(rows) do
    for i = 1, #r.bounds - 1 do
      local w = r.delim and 0 or ctx.width_of(r.row, r.bounds[i] + 1, r.bounds[i + 1])
      if w > (widths[i] or 0) then
        widths[i] = w
      end
      widths[i] = widths[i] or 0
    end
  end

  local t = ctx.icons.table
  local hl = 'MarkvimTable'
  local _, indent = node:range()
  local function border(l, m, r)
    local parts = { (' '):rep(indent), l }
    for i = 1, #widths do
      parts[#parts + 1] = util.fill(t.h, widths[i])
      parts[#parts + 1] = i < #widths and m or r
    end
    return table.concat(parts)
  end

  for idx, r in ipairs(rows) do
    local row, bounds, real = r.row, r.bounds, r.real
    if r.delim then
      local s = real[1] and bounds[1] or bounds[1] + 1
      local e = real[#real] and bounds[#bounds] + 1 or bounds[#bounds]
      local parts = { t.l }
      for i = 1, #widths do
        parts[#parts + 1] = util.fill(t.h, widths[i])
        parts[#parts + 1] = i < #widths and t.x or t.r
      end
      ctx.add(row, s, { end_col = e, conceal = '' })
      ctx.add(row, s, { virt_text = { { table.concat(parts), hl } }, virt_text_pos = 'inline' })
    else
      for i = 1, #bounds do
        if real[i] then
          ctx.add(row, bounds[i], {
            end_col = bounds[i] + 1,
            virt_text = { { t.v, hl } },
            virt_text_pos = 'overlay',
          })
        end
      end
      if cfg.pad then
        for i = 1, #bounds - 1 do
          local pad = (widths[i] or 0) - ctx.width_of(row, bounds[i] + 1, bounds[i + 1])
          if pad > 0 then
            local align = aligns[i] or 'left'
            local before, after = 0, pad
            if align == 'right' then
              before, after = pad, 0
            elseif align == 'center' then
              before = math.floor(pad / 2)
              after = pad - before
            end
            if before > 0 then
              ctx.add(row, bounds[i] + 1, { virt_text = { { (' '):rep(before), hl } }, virt_text_pos = 'inline' })
            end
            if after > 0 then
              ctx.add(row, bounds[i + 1], { virt_text = { { (' '):rep(after), hl } }, virt_text_pos = 'inline' })
            end
          end
        end
      end
      if cfg.style == 'full' then
        if idx == 1 then
          ctx.fix(row, 0, { virt_lines = { { { border(t.tl, t.t, t.tr), hl } } }, virt_lines_above = true })
        end
        if idx == #rows then
          ctx.fix(row, 0, { virt_lines = { { { border(t.bl, t.b, t.br), hl } } } })
        end
      end
    end
  end
  ctx.blocks[#ctx.blocks + 1] = { rows[1].row, rows[#rows].row }
end

return M
