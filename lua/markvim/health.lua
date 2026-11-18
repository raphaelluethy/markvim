local M = {}

function M.check()
  local health = vim.health
  health.start('markvim')
  if vim.fn.has('nvim-0.12') == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim 0.12 or newer is required')
  end
  for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
    if pcall(vim.treesitter.language.inspect, lang) then
      health.ok('treesitter parser: ' .. lang)
    else
      health.error('missing treesitter parser: ' .. lang)
    end
  end
  local ok, cfg = pcall(require('markvim.config').get)
  if ok then
    health.ok(
      ('config: mode=%s float_mode=%s icons=%s code.border=%s diagram.backend=%s'):format(
        cfg.mode,
        cfg.float_mode,
        cfg.icons,
        cfg.code.border,
        cfg.diagram.backend
      )
    )
  else
    health.error('invalid config: ' .. tostring(cfg))
  end
  local n = 0
  for _ in pairs(require('markvim.state').buffers) do
    n = n + 1
  end
  health.info(('attached buffers: %d'):format(n))

  health.start('markvim: diagram renderers')
  local renderers = require('markvim.diagram').renderers
  for _, r in ipairs(renderers.report()) do
    if r.available then
      health.ok(('%s (%s)'):format(r.name, r.kind))
    else
      health.info(('%s (%s): not available'):format(r.name, r.kind))
    end
  end
  local prefix = renderers.node_prefix .. '/node_modules'
  if vim.uv.fs_stat(prefix) then
    health.ok('node renderers installed in ' .. prefix)
  else
    health.info('node renderers (pele, beautiful-mermaid) not installed; run :Markvim install node')
  end

  health.start('markvim: images')
  local image = require('markvim.image')
  local info = image.detect()
  local w, h = image.cell_size()
  health.info(
    ('terminal: %s, kitty graphics with placeholders: %s%s%s'):format(
      info.name,
      info.supported and 'yes' or 'no',
      info.tmux and ', tmux' or '',
      info.remote and ', remote' or ''
    )
  )
  health.info(('cell size: %.1f x %.1f px'):format(w, h))
  if not info.supported then
    health.info('diagrams fall back to text renderers; set MARKVIM_IMAGES=1 to force images')
  end
end

return M
