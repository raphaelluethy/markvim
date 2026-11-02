local api = vim.api
local M = {}

M.strwidth = api.nvim_strwidth

---Repeat `s` to reach display width `width` (truncating if needed).
---@param s string
---@param width integer
---@return string
function M.fill(s, width)
  if width <= 0 then
    return ''
  end
  local w = api.nvim_strwidth(s)
  if w == 0 then
    return (' '):rep(width)
  end
  local out = s:rep(math.ceil(width / w))
  if api.nvim_strwidth(out) > width then
    out = vim.fn.strcharpart(out, 0, width)
  end
  return out
end

---Pad string with spaces on the right to display width `width`.
function M.rpad(s, width)
  local w = api.nvim_strwidth(s)
  if w >= width then
    return s
  end
  return s .. (' '):rep(width - w)
end

function M.lpad(s, width)
  local w = api.nvim_strwidth(s)
  if w >= width then
    return s
  end
  return (' '):rep(width - w) .. s
end

---Text width usable for content in a window (window width minus number/sign columns).
---@param win integer
---@return integer
function M.text_width(win)
  local ok, info = pcall(vim.fn.getwininfo, win)
  if ok and info and info[1] then
    return math.max(1, info[1].width - info[1].textoff)
  end
  return api.nvim_win_get_width(win)
end

---@param win integer
---@return boolean
function M.is_float(win)
  return api.nvim_win_get_config(win).relative ~= ''
end

---Monotonic clock in milliseconds.
function M.now()
  return vim.uv.hrtime() / 1e6
end

---Shallow copy a table.
function M.copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

---Capitalize the first letter.
function M.capitalize(s)
  return (s:gsub('^%l', string.upper))
end

---Merge overlapping/adjacent {top, bot} ranges (inclusive rows).
---@param ranges integer[][]
---@return integer[][]
function M.merge_ranges(ranges)
  table.sort(ranges, function(a, b)
    return a[1] < b[1]
  end)
  local out = {}
  for _, r in ipairs(ranges) do
    local last = out[#out]
    if last and r[1] <= last[2] + 1 then
      if r[2] > last[2] then
        last[2] = r[2]
      end
    else
      out[#out + 1] = { r[1], r[2] }
    end
  end
  return out
end

return M
