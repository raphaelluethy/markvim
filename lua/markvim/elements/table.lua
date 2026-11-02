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

---Return the semantic content of a cell and its compact display width.
---Markdown ignores whitespace next to a pipe, but formatters often use a large
---amount of it to align the source. Keep at most one visual space on each side
---so that source formatting cannot make an otherwise small table wrap.
local function cell_span(ctx, row, start_col, end_col)
  local text = ctx.line(row):sub(start_col + 1, end_col)
  local leading = #(text:match('^[ \t]*') or '')
  local trailing = #(text:match('[ \t]*$') or '')
  local content_start = start_col + leading
  local content_end = end_col - trailing
  if content_end < content_start then
    content_end = content_start
  end
  local left = leading > 0 and 1 or 0
  local right = trailing > 0 and 1 or 0
  return {
    start_col = start_col,
    end_col = end_col,
    content_start = content_start,
    content_end = content_end,
    left = left,
    right = right,
    width = left + ctx.width_of(row, content_start, content_end) + right,
  }
end

local function char_len(text, byte)
  local b = text:byte(byte)
  if not b or b < 0x80 then
    return 1
  elseif b < 0xE0 then
    return 2
  elseif b < 0xF0 then
    return 3
  end
  return 4
end

---Materialize the inline rendering already collected for a cell. Overflow
---tables use virtual lines, so their source extmarks cannot render the content
---directly; replaying conceal and inline virtual text keeps emphasis/link
---delimiters out while preserving their visible text and icons.
local function rendered_text(ctx, row, start_col, end_col)
  local inserts, concealed = {}, {}
  for _, mark in ipairs(ctx.main[row] or {}) do
    local col, opts = mark[1], mark[2]
    if opts.virt_text and opts.virt_text_pos == 'inline' and col >= start_col and col <= end_col then
      local parts = inserts[col] or {}
      for _, chunk in ipairs(opts.virt_text) do
        parts[#parts + 1] = chunk[1]
      end
      inserts[col] = parts
    end
    if opts.conceal ~= nil and opts.end_col and opts.end_col > start_col and col < end_col then
      concealed[#concealed + 1] = { math.max(start_col, col), math.min(end_col, opts.end_col) }
    end
  end
  local function hidden(col)
    for _, range in ipairs(concealed) do
      if col >= range[1] and col < range[2] then
        return range[2]
      end
    end
  end
  local line, out, col = ctx.line(row), {}, start_col
  while col < end_col do
    if inserts[col] then
      out[#out + 1] = table.concat(inserts[col])
    end
    local until_col = hidden(col)
    if until_col then
      col = until_col
    else
      local len = char_len(line, col + 1)
      out[#out + 1] = line:sub(col + 1, math.min(end_col, col + len))
      col = col + len
    end
  end
  if inserts[end_col] then
    out[#out + 1] = table.concat(inserts[end_col])
  end
  return table.concat(out)
end

local function split_word(word, width)
  local lines, current = {}, ''
  local byte = 1
  while byte <= #word do
    local len = char_len(word, byte)
    local char = word:sub(byte, byte + len - 1)
    if current ~= '' and vim.api.nvim_strwidth(current .. char) > width then
      lines[#lines + 1] = current
      current = char
    else
      current = current .. char
    end
    byte = byte + len
  end
  if current ~= '' then
    lines[#lines + 1] = current
  end
  return lines
end

---Word-wrap text to a display width, splitting an individual long word by
---Unicode codepoint only when needed.
local function wrap_text(text, width)
  local lines, current = {}, ''
  for word in text:gmatch('%S+') do
    local candidate = current == '' and word or (current .. ' ' .. word)
    if vim.api.nvim_strwidth(candidate) <= width then
      current = candidate
    else
      if current ~= '' then
        lines[#lines + 1] = current
        current = ''
      end
      if vim.api.nvim_strwidth(word) <= width then
        current = word
      else
        local pieces = split_word(word, width)
        for i = 1, #pieces - 1 do
          lines[#lines + 1] = pieces[i]
        end
        current = pieces[#pieces] or ''
      end
    end
  end
  if current ~= '' or #lines == 0 then
    lines[#lines + 1] = current
  end
  return lines
end

---Max-min allocation: short columns keep their natural width and the remaining
---space goes to columns that actually need it.
local function bounded_widths(desired, available)
  local count = #desired
  local edge = available >= 4 * count + 1 and 1 or 0
  local budget = available - (count + 1) - 2 * edge * count
  local widths, active, remaining = {}, {}, budget
  for i = 1, count do
    desired[i] = math.max(1, desired[i] or 0)
    active[#active + 1] = i
  end
  while #active > 0 do
    local share = math.max(1, math.floor(remaining / #active))
    local next_active, settled = {}, false
    for _, i in ipairs(active) do
      if desired[i] <= share then
        widths[i] = desired[i]
        remaining = remaining - widths[i]
        settled = true
      else
        next_active[#next_active + 1] = i
      end
    end
    if not settled then
      for n, i in ipairs(active) do
        widths[i] = share + (n <= remaining - share * #active and 1 or 0)
      end
      break
    end
    active = next_active
  end
  return widths, edge
end

local function aligned(text, width, align)
  local missing = math.max(0, width - vim.api.nvim_strwidth(text))
  if align == 'right' then
    return (' '):rep(missing) .. text
  elseif align == 'center' then
    local before = math.floor(missing / 2)
    return (' '):rep(before) .. text .. (' '):rep(missing - before)
  end
  return text .. (' '):rep(missing)
end

local function virtual_table_lines(rows, aligns, widths, edge, indent, icons, hl, full)
  local lines = {}
  local function border(left, middle, right)
    local parts = { (' '):rep(indent), left }
    for i, width in ipairs(widths) do
      parts[#parts + 1] = util.fill(icons.h, width + edge * 2)
      parts[#parts + 1] = i < #widths and middle or right
    end
    return { { table.concat(parts), hl } }
  end
  local function content(row)
    local wrapped, height = {}, 1
    for i, width in ipairs(widths) do
      local cell = row.cells and row.cells[i]
      wrapped[i] = wrap_text(cell and cell.text or '', width)
      height = math.max(height, #wrapped[i])
    end
    for line = 1, height do
      local parts = { (' '):rep(indent), icons.v }
      for i, width in ipairs(widths) do
        local text = wrapped[i][line] or ''
        parts[#parts + 1] = (' '):rep(edge) .. aligned(text, width, aligns[i] or 'left') .. (' '):rep(edge) .. icons.v
      end
      lines[#lines + 1] = { { table.concat(parts), hl } }
    end
  end

  if full then
    lines[#lines + 1] = border(icons.tl, icons.t, icons.tr)
  end
  for _, row in ipairs(rows) do
    if row.delim then
      lines[#lines + 1] = border(icons.l, icons.x, icons.r)
    else
      content(row)
    end
  end
  if full then
    lines[#lines + 1] = border(icons.bl, icons.b, icons.br)
  end
  return lines
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

  local widths, source_widths, content_widths = {}, {}, {}
  for _, r in ipairs(rows) do
    for i = 1, #r.bounds - 1 do
      local w = 0
      if not r.delim then
        r.cells = r.cells or {}
        r.cells[i] = cell_span(ctx, r.row, r.bounds[i] + 1, r.bounds[i + 1])
        r.cells[i].text = rendered_text(ctx, r.row, r.cells[i].content_start, r.cells[i].content_end)
        w = r.cells[i].width
        content_widths[i] = math.max(content_widths[i] or 0, vim.api.nvim_strwidth(r.cells[i].text))
        source_widths[i] = math.max(source_widths[i] or 0, ctx.width_of(r.row, r.bounds[i] + 1, r.bounds[i + 1]))
      end
      if w > (widths[i] or 0) then
        widths[i] = w
      end
      widths[i] = widths[i] or 0
    end
  end

  local t = ctx.icons.table
  local hl = 'MarkvimTable'
  local _, indent = node:range()
  local total, source_total = indent + #widths + 1, indent + #widths + 1
  for i = 1, #widths do
    content_widths[i] = content_widths[i] or 0
    total = total + content_widths[i] + 2
    source_total = source_total + (source_widths[i] or 0)
  end
  local overflow = total > ctx.width or source_total > ctx.width
  if overflow then
    local available = math.max(1, ctx.width - indent)
    local virtual_widths, edge
    if total <= ctx.width then
      virtual_widths, edge = content_widths, 1
    else
      virtual_widths, edge = bounded_widths(content_widths, available)
    end
    local virtual = virtual_table_lines(rows, aligns, virtual_widths, edge, indent, t, hl, cfg.style == 'full')
    local block = { rows[1].row, rows[#rows].row }
    ctx.raw_blocks[#ctx.raw_blocks + 1] = block
    ctx.blocks[#ctx.blocks + 1] = block

    local line_count = vim.api.nvim_buf_line_count(ctx.buf)
    local anchor, above
    if block[1] > 0 and not ctx.hidden[block[1] - 1] then
      anchor, above = block[1] - 1, false
    elseif block[2] + 1 < line_count and not ctx.hidden[block[2] + 1] then
      anchor, above = block[2] + 1, true
    end
    if anchor then
      for row = block[1], block[2] do
        ctx.add(row, 0, { conceal_lines = '' })
        ctx.hidden[row] = true
      end
      ctx.add_conditional(anchor, 0, { virt_lines = virtual, virt_lines_above = above }, block)
    else
      -- A buffer containing only the table has no visible line to anchor
      -- virtual lines to. Keep the shortest source row as an inline anchor,
      -- hide every other source row and render the first table line in place.
      local anchor_row, shortest
      for row = block[1], block[2] do
        local width = vim.api.nvim_strwidth(ctx.line(row))
        if not shortest or width < shortest then
          anchor_row, shortest = row, width
        end
      end
      for row = block[1], block[2] do
        if row ~= anchor_row then
          ctx.add(row, 0, { conceal_lines = '' })
          ctx.hidden[row] = true
        end
      end
      local first = table.remove(virtual, 1)
      local opts = {
        end_col = #ctx.line(anchor_row),
        conceal = '',
        virt_text = first,
        virt_text_pos = 'inline',
        priority = 250,
      }
      if #virtual > 0 then
        ctx.add_conditional(anchor_row, 0, { virt_lines = virtual }, block)
      end
      ctx.add_conditional(anchor_row, 0, opts, block)
    end
    return
  end

  local pad = cfg.pad
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
      ctx.add(row, s, {
        end_col = e,
        conceal = '',
        virt_text = { { border(t.l, t.x, t.r):sub(indent + 1), hl } },
        virt_text_pos = 'inline',
        priority = 200,
      })
    else
      -- Padding of each cell, split into before/after by alignment.
      local before, after = {}, {}
      for i = 1, #bounds - 1 do
        local missing = pad and (widths[i] or 0) - r.cells[i].width or 0
        local align = aligns[i] or 'left'
        if align == 'right' then
          before[i], after[i] = missing, 0
        elseif align == 'center' then
          before[i] = math.floor(missing / 2)
          after[i] = missing - before[i]
        else
          before[i], after[i] = 0, missing
        end
      end
      -- Use one mark for the whitespace, raw pipe and virtual replacement at
      -- each boundary. Besides compacting formatter whitespace, keeping conceal
      -- and virtual text together avoids ordering collisions with Tree-sitter
      -- highlights and other decorations on the pipe.
      for i = 1, #bounds do
        local chunks = {}
        local previous = r.cells[i - 1]
        local following = r.cells[i]
        if i > 1 and after[i - 1] > 0 then
          chunks[#chunks + 1] = { (' '):rep(after[i - 1]), hl }
        end
        if previous and previous.right > 0 then
          chunks[#chunks + 1] = { ' ', hl }
        end
        if real[i] then
          chunks[#chunks + 1] = { t.v, hl }
        end
        if following and following.left > 0 then
          chunks[#chunks + 1] = { ' ', hl }
        end
        if i < #bounds and before[i] > 0 then
          chunks[#chunks + 1] = { (' '):rep(before[i]), hl }
        end
        local start_col = previous and previous.content_end or (real[i] and bounds[i]) or following.start_col
        local end_col = following and following.content_start or (real[i] and bounds[i] + 1) or previous.end_col
        if #chunks > 0 or end_col > start_col then
          local opts = {
            virt_text = chunks,
            virt_text_pos = 'inline',
            priority = 200,
          }
          if end_col > start_col then
            opts.end_col = end_col
            opts.conceal = ''
          end
          ctx.add(row, start_col, opts)
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
