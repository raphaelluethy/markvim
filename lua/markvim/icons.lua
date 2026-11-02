-- Icon sets. `nerd` needs a Nerd Font; `unicode` works with any decent font;
-- `ascii` is the lowest common denominator.
local M = {}

M.sets = {
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
    code = '󰅩 ',
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
    border = { h = '─', tl = '╭', tr = '╮', bl = '╰', br = '╯' },
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
    code = '',
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
    border = { h = '─', tl = '╭', tr = '╮', bl = '╰', br = '╯' },
  },
  ascii = {
    heading = { '# ', '## ', '### ', '#### ', '##### ', '###### ' },
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
    code = '',
    diagram = '',
    pending = '... ',
    error = 'x ',
    callout = {},
    table = { h = '-', v = '|', tl = '+', tr = '+', bl = '+', br = '+', t = '+', b = '+', l = '+', r = '+', x = '+' },
    border = { h = '-', tl = '+', tr = '+', bl = '+', br = '+' },
  },
}

---@param name 'nerd'|'unicode'|'ascii'
function M.get(name)
  return M.sets[name] or M.sets.nerd
end

local provider -- cached devicons provider lookup

---Icon and highlight for a code block language, via mini.icons or
---nvim-web-devicons when installed. Loaded lazily and cached.
---@param lang string
---@return string|nil icon, string|nil hl
function M.language(lang)
  if provider == nil then
    local ok_mini, mini = pcall(require, 'mini.icons')
    if ok_mini and _G.MiniIcons then
      provider = function(l)
        local ok, icon, hl = pcall(mini.get, 'filetype', l)
        if ok and icon then
          return icon, hl
        end
      end
    else
      local ok_dev, dev = pcall(require, 'nvim-web-devicons')
      if ok_dev then
        provider = function(l)
          local icon, hl = dev.get_icon_by_filetype(l, { default = false })
          if not icon then
            icon, hl = dev.get_icon(l, l, { default = false })
          end
          return icon, hl
        end
      else
        provider = false
      end
    end
  end
  if provider then
    return provider(lang)
  end
  return nil, nil
end

return M
