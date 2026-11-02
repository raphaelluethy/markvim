-- Small compatibility shims around Neovim's runtime queries.
local M = {}

local patched = false

---Neovim's bundled markdown highlight query hides fence lines with
---`conceal_lines`. markvim decides per block whether a fence line is hidden,
---shown as spacing or drawn as a border, so drop those directives from the
---active query. Returns true the first time (callers restart highlighters).
---@return boolean patched_now
function M.keep_fence_lines()
  if patched then
    return false
  end
  patched = true
  pcall(function()
    local files = vim.treesitter.query.get_files('markdown', 'highlights')
    if #files == 0 then
      return
    end
    local parts = {}
    for _, f in ipairs(files) do
      parts[#parts + 1] = table.concat(vim.fn.readfile(f), '\n')
    end
    local text = table.concat(parts, '\n'):gsub('%(#set! conceal_lines ""%)', '')
    vim.treesitter.query.set('markdown', 'highlights', text)
  end)
  return true
end

---Restart the treesitter highlighter of a buffer so it picks up changed queries.
function M.restart_highlighter(buf)
  if vim.treesitter.highlighter.active[buf] then
    vim.treesitter.stop(buf)
    vim.treesitter.start(buf)
  end
end

return M
