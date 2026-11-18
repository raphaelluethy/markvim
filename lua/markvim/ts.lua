-- Tree-sitter helpers for Markdown nodes.
local M = {}

---@param buf integer
---@return vim.treesitter.LanguageTree|nil
function M.parser(buf)
  local parser = vim.treesitter.get_parser(buf, 'markdown', { error = false })
  return parser or nil
end

---Nesting depth of a node counted by ancestors of the given type.
---@param node TSNode
---@param kind string
---@return integer
function M.depth(node, kind)
  local depth = 0
  local parent = node:parent()
  while parent do
    if parent:type() == kind then
      depth = depth + 1
    end
    parent = parent:parent()
  end
  return depth
end

---Node text for a single-line node using a line cache.
---@param ctx markvim.Ctx
---@param node TSNode
---@return string
function M.text(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr == er then
    return ctx.line(sr):sub(sc + 1, ec)
  end
  return vim.treesitter.get_node_text(node, ctx.buf)
end

return M
