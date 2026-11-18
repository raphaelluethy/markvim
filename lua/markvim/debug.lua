local api = vim.api
local M = {}

---Print state and last render statistics for a buffer.
function M.show(buf)
  local s = require('markvim.state').get(buf)
  if not s then
    print('markvim: not attached to buffer ' .. buf)
    return
  end
  local lines = {
    ('markvim buffer %d: enabled=%s mode=%s float=%s views=%d'):format(buf, s.enabled, s.mode, s.float, #s.views),
  }
  local st = s.stats
  if st.compute_ms then
    lines[#lines + 1] = ('last render: total %.2fms = viewport %.2f + compute %.2f (parse %.2f, inline %.2f, elements %.2f) + apply %.2f; %d marks, ranges %s'):format(
      st.total_ms,
      st.viewport_ms,
      st.compute_ms,
      st.phases.parse,
      st.phases.inline_parse,
      st.phases.elements,
      st.apply_ms,
      st.marks,
      vim.inspect(st.ranges, { newline = '', indent = '' })
    )
  end
  local row = api.nvim_win_get_cursor(0)[1] - 1
  for _, v in ipairs(s.views) do
    local n_main = #api.nvim_buf_get_extmarks(buf, v.ns, { row, 0 }, { row, -1 }, {})
    local n_fixed = #api.nvim_buf_get_extmarks(buf, v.ns_fixed, { row, 0 }, { row, -1 }, {})
    lines[#lines + 1] = ('view ns=%d hybrid=%s raw=%s marks on cursor row: %d main, %d fixed'):format(
      v.ns,
      v.hybrid,
      vim.inspect(vim.tbl_keys(v.raw), { newline = '', indent = '' }),
      n_main,
      n_fixed
    )
  end
  print(table.concat(lines, '\n'))
end

return M
