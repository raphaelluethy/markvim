-- Icon sets. `nerd` needs a Nerd Font; `unicode` works with any decent font;
-- `ascii` is the lowest common denominator.
local M = {}

local sets = {
  nerd = {
    heading = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    bullet = { '•', '◦', '▪' },
    unchecked = '󰄱',
    checked = '󰱒',
    link = '󰌹 ',
    web = '󰖟 ',
    image = '󰥶 ',
    wiki = '󱗖 ',
    email = '󰇮 ',
    footnote = '󰎚 ',
    file = '󰈙 ',
    quote = '▋',
    rule = '─',
    hard_break = '↵',
    diagram = '󱁉 ',
    pending = '󰔟 ',
    error = '󰅙 ',
    callout = {
      note = '󰋽',
      info = '󰋽',
      abstract = '󰨸',
      summary = '󰨸',
      tldr = '󰨸',
      todo = '󰗡',
      tip = '󰌶',
      hint = '󰌶',
      important = '󰅾',
      success = '󰄬',
      check = '󰄬',
      done = '󰄬',
      question = '󰘥',
      help = '󰘥',
      faq = '󰘥',
      warning = '󰀪',
      caution = '󰳦',
      attention = '󰀪',
      failure = '󰅖',
      fail = '󰅖',
      missing = '󰅖',
      danger = '󱐌',
      error = '󱐌',
      bug = '󰨰',
      example = '󰉹',
      quote = '󱆨',
      cite = '󱆨',
    },
    table = {
      h = '─',
      v = '│',
      tl = '┌',
      tr = '┐',
      bl = '└',
      br = '┘',
      t = '┬',
      b = '┴',
      l = '├',
      r = '┤',
      x = '┼',
    },
  },
  unicode = {
    heading = { '◉ ', '○ ', '✸ ', '✿ ', '▶ ', '▷ ' },
    bullet = { '•', '◦', '▪' },
    unchecked = '☐',
    checked = '☑',
    link = '🔗 ',
    web = '🌐 ',
    image = '🖼 ',
    wiki = '📄 ',
    email = '✉ ',
    footnote = '† ',
    file = '📄 ',
    quote = '▋',
    rule = '─',
    hard_break = '↵',
    diagram = '◆ ',
    pending = '… ',
    error = '✗ ',
    callout = {
      note = 'ℹ',
      info = 'ℹ',
      abstract = '≡',
      summary = '≡',
      tldr = '≡',
      todo = '☐',
      tip = '💡',
      hint = '💡',
      important = '❗',
      success = '✔',
      check = '✔',
      done = '✔',
      question = '?',
      help = '?',
      faq = '?',
      warning = '⚠',
      caution = '⛔',
      attention = '⚠',
      failure = '✖',
      fail = '✖',
      missing = '✖',
      danger = '⚡',
      error = '⚡',
      bug = '🐛',
      example = '≣',
      quote = '❝',
      cite = '❝',
    },
    table = {
      h = '─',
      v = '│',
      tl = '┌',
      tr = '┐',
      bl = '└',
      br = '┘',
      t = '┬',
      b = '┴',
      l = '├',
      r = '┤',
      x = '┼',
    },
  },
  ascii = {
    bullet = { '*', '-', '+', '.' },
    unchecked = '[ ]',
    checked = '[x]',
    link = '',
    web = '',
    image = '',
    wiki = '',
    email = '',
    footnote = '',
    file = '',
    quote = '|',
    rule = '-',
    hard_break = '\\',
    diagram = '',
    pending = '... ',
    error = 'x ',
    callout = {},
    table = { h = '-', v = '|', tl = '+', tr = '+', bl = '+', br = '+', t = '+', b = '+', l = '+', r = '+', x = '+' },
  },
}

---@param name 'nerd'|'unicode'|'ascii'
function M.get(name)
  return sets[name] or sets.nerd
end

local providers = {}
local loaders = {
  ['mini.icons'] = function()
    local ok, mini = pcall(require, 'mini.icons')
    if ok and _G.MiniIcons then
      return function(lang)
        local found, icon, hl = pcall(mini.get, 'filetype', lang)
        if found then
          return icon, hl
        end
      end
    end
  end,
  ['nvim-web-devicons'] = function()
    local ok, devicons = pcall(require, 'nvim-web-devicons')
    if ok then
      return function(lang)
        local icon, hl = devicons.get_icon_by_filetype(lang, { default = false })
        if not icon then
          icon, hl = devicons.get_icon(lang, lang, { default = false })
        end
        return icon, hl
      end
    end
  end,
}

local function get_provider(name)
  local load = loaders[name]
  if load and providers[name] == nil then
    providers[name] = load() or false
  end
  return providers[name]
end

---Icon and highlight for a code block language.
---@param lang string
---@param setting true|'mini.icons'|'nvim-web-devicons'|fun(lang: string): string?, string?
---@return string|nil icon, string|nil hl
function M.language(lang, setting)
  if type(setting) == 'function' then
    return setting(lang)
  end
  local provider
  if setting == true then
    provider = get_provider('mini.icons') or get_provider('nvim-web-devicons')
  else
    provider = get_provider(setting)
  end
  if provider then
    return provider(lang)
  end
end

return M
