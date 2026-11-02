-- Highlight groups. Everything links to the user's colorscheme (treesitter
-- `@markup.*` groups and standard UI groups); only heading backgrounds are
-- computed, by blending the heading foreground into the Normal background.
local api = vim.api
local M = {}

local links = {
  MarkvimH1 = '@markup.heading.1.markdown',
  MarkvimH2 = '@markup.heading.2.markdown',
  MarkvimH3 = '@markup.heading.3.markdown',
  MarkvimH4 = '@markup.heading.4.markdown',
  MarkvimH5 = '@markup.heading.5.markdown',
  MarkvimH6 = '@markup.heading.6.markdown',
  MarkvimCodeInline = '@markup.raw.markdown_inline',
  MarkvimCodeInfo = 'Comment',
  MarkvimCodeBorder = 'FloatBorder',
  MarkvimBullet = '@markup.list.markdown',
  MarkvimOrdered = '@markup.list.markdown',
  MarkvimChecked = '@markup.list.checked.markdown',
  MarkvimUnchecked = '@markup.list.unchecked.markdown',
  MarkvimTodo = '@markup.raw.markdown_inline',
  MarkvimQuote = '@markup.quote.markdown',
  MarkvimRule = 'LineNr',
  MarkvimTable = '@punctuation.special.markdown',
  MarkvimTableHead = '@markup.heading.markdown',
  MarkvimLink = '@markup.link.label.markdown_inline',
  MarkvimUrl = '@markup.link.url.markdown_inline',
  MarkvimImage = '@markup.link.label.markdown_inline',
  MarkvimStrike = '@markup.strikethrough.markdown_inline',
  MarkvimMath = '@markup.math.markdown_inline',
  MarkvimHtml = 'Comment',
  MarkvimHardBreak = 'NonText',
  MarkvimDiagram = 'Normal',
  MarkvimDiagramPending = 'Comment',
  MarkvimDiagramError = 'DiagnosticError',
  MarkvimCalloutNote = 'DiagnosticInfo',
  MarkvimCalloutTip = 'DiagnosticOk',
  MarkvimCalloutImportant = 'DiagnosticHint',
  MarkvimCalloutWarning = 'DiagnosticWarn',
  MarkvimCalloutCaution = 'DiagnosticError',
  MarkvimCalloutQuestion = 'DiagnosticWarn',
  MarkvimCalloutQuote = '@markup.quote.markdown',
}

---@param group string
---@return vim.api.keyset.get_hl_info
local function get(group)
  return api.nvim_get_hl(0, { name = group, link = false })
end

---Blend `fg` into `bg` with ratio `alpha` (0 = bg, 1 = fg).
local function blend(fg, bg, alpha)
  local function ch(c, shift)
    return bit.band(bit.rshift(c, shift), 0xff)
  end
  local r = ch(fg, 16) * alpha + ch(bg, 16) * (1 - alpha)
  local g = ch(fg, 8) * alpha + ch(bg, 8) * (1 - alpha)
  local b = ch(fg, 0) * alpha + ch(bg, 0) * (1 - alpha)
  return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

local function define_backgrounds()
  local normal = get('Normal')
  local base_bg = normal.bg
  for i = 1, 6 do
    local name = 'MarkvimH' .. i .. 'Bg'
    local h = get('MarkvimH' .. i)
    local fg = h.fg
    if vim.o.termguicolors and fg and base_bg then
      api.nvim_set_hl(0, name, { bg = blend(fg, base_bg, 0.18), default = true })
    elseif vim.o.termguicolors and fg then
      api.nvim_set_hl(0, name, { bg = blend(fg, 0x000000, 0.25), default = true })
    else
      api.nvim_set_hl(0, name, { link = 'CursorLine', default = true })
    end
  end
  -- Code block background: a faint tint of the Normal foreground over the
  -- Normal background, so it stays subtle on light and dark themes alike.
  -- Override with `hi MarkvimCode` (e.g. link it to ColorColumn).
  if vim.o.termguicolors and base_bg and normal.fg then
    api.nvim_set_hl(0, 'MarkvimCode', { bg = blend(normal.fg, base_bg, 0.08), default = true })
  else
    api.nvim_set_hl(0, 'MarkvimCode', { link = 'ColorColumn', default = true })
  end
end

local defined = false

---Define all highlight groups. Safe to call repeatedly (ColorScheme).
function M.setup()
  for name, target in pairs(links) do
    api.nvim_set_hl(0, name, { link = target, default = true })
  end
  define_backgrounds()
  if not defined then
    defined = true
    api.nvim_create_autocmd('ColorScheme', {
      group = api.nvim_create_augroup('markvim.hl', { clear = true }),
      callback = function()
        -- Links survive a colorscheme change only if the scheme does not clear
        -- them; re-apply everything (cheap).
        for name, target in pairs(links) do
          api.nvim_set_hl(0, name, { link = target, default = true })
        end
        -- Backgrounds are computed from the new palette: force-redefine.
        for i = 1, 6 do
          api.nvim_set_hl(0, 'MarkvimH' .. i .. 'Bg', {})
        end
        define_backgrounds()
      end,
    })
  end
end

---Highlight group name for a callout type (falls back to Note).
---@param kind string lower-case callout name
---@return string
function M.callout(kind)
  local map = {
    note = 'MarkvimCalloutNote',
    info = 'MarkvimCalloutNote',
    abstract = 'MarkvimCalloutNote',
    summary = 'MarkvimCalloutNote',
    tldr = 'MarkvimCalloutNote',
    todo = 'MarkvimCalloutNote',
    tip = 'MarkvimCalloutTip',
    hint = 'MarkvimCalloutTip',
    success = 'MarkvimCalloutTip',
    check = 'MarkvimCalloutTip',
    done = 'MarkvimCalloutTip',
    important = 'MarkvimCalloutImportant',
    example = 'MarkvimCalloutImportant',
    warning = 'MarkvimCalloutWarning',
    caution = 'MarkvimCalloutCaution',
    attention = 'MarkvimCalloutWarning',
    question = 'MarkvimCalloutQuestion',
    help = 'MarkvimCalloutQuestion',
    faq = 'MarkvimCalloutQuestion',
    failure = 'MarkvimCalloutCaution',
    fail = 'MarkvimCalloutCaution',
    missing = 'MarkvimCalloutCaution',
    danger = 'MarkvimCalloutCaution',
    error = 'MarkvimCalloutCaution',
    bug = 'MarkvimCalloutCaution',
    quote = 'MarkvimCalloutQuote',
    cite = 'MarkvimCalloutQuote',
  }
  return map[kind] or 'MarkvimCalloutNote'
end

return M
