#!/usr/bin/env node
// markvim helper: render Mermaid source (stdin) with a Node library and write the
// result to stdout.
//
//   node mermaid.mjs <engine> <format> [options-json]
//
//   engine: beautiful-mermaid | pele
//   format: unicode | ascii (beautiful-mermaid only) | svg
//   options: {"fg":"#ccc","bg":"transparent","maxWidth":80,"fontFamily":"sans-serif","fontSize":14}
//
// Packages are resolved from $MARKVIM_NODE_PREFIX/node_modules when set
// (`:Markvim install node` installs them there). Exit codes: 0 ok, 1 render
// error, 2 missing package.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [engine, format = 'svg', optionsJson] = process.argv.slice(2);
if (!engine) {
  process.stderr.write('usage: mermaid.mjs <beautiful-mermaid|pele> <unicode|ascii|svg> [options-json]\n');
  process.exit(1);
}
let options = {};
try {
  options = optionsJson ? JSON.parse(optionsJson) : {};
} catch (e) {
  process.stderr.write(`invalid options json: ${e.message}\n`);
  process.exit(1);
}
const source = readFileSync(0, 'utf8');

// Entry file of a package under `base/node_modules`. Reads package.json
// ourselves: `require.resolve` fails on ESM-only packages whose "exports" has
// no "require" condition (beautiful-mermaid, pele).
function resolveEntry(base, name) {
  const dir = path.join(base, 'node_modules', name);
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(path.join(dir, 'package.json'), 'utf8'));
  } catch {
    return null;
  }
  const pick = (e) => {
    if (typeof e === 'string') return e;
    if (Array.isArray(e)) {
      for (const x of e) {
        const r = pick(x);
        if (r) return r;
      }
      return null;
    }
    if (e && typeof e === 'object') {
      for (const k of ['import', 'module', 'node', 'default', 'require']) {
        if (k in e) {
          const r = pick(e[k]);
          if (r) return r;
        }
      }
    }
    return null;
  };
  let exp = pkg.exports;
  if (exp && typeof exp === 'object' && !Array.isArray(exp) && '.' in exp) exp = exp['.'];
  const rel = pick(exp) || pkg.module || pkg.main || 'index.js';
  return path.join(dir, rel);
}

async function load(name) {
  const prefix = process.env.MARKVIM_NODE_PREFIX;
  const base = prefix || process.cwd();
  let resolved = resolveEntry(base, name);
  if (!resolved) {
    try {
      resolved = createRequire(path.join(base, path.sep)).resolve(name);
    } catch {
      process.stderr.write(`package "${name}" not found; run :Markvim install node (or npm install ${name})\n`);
      process.exit(2);
    }
  }
  return import(pathToFileURL(resolved).href);
}

function themeSvg(svg, fg, bg) {
  // librsvg does not resolve CSS custom properties; substitute them.
  const vars = { '--pele-bg': bg, '--pele-fg': fg, '--pele-accent': fg, '--pele-font': options.fontFamily || 'sans-serif' };
  let out = svg.replace(/var\((--pele-[a-z]+)(?:,\s*[^)]*)?\)/g, (m, name) => vars[name] ?? m);
  if (!/style="[^"]*--pele-fg/.test(out)) {
    out = out.replace(/<svg\b/, `<svg style="color:${fg};background:${bg}"`);
  }
  return out;
}

try {
  const fg = options.fg || '#cccccc';
  const bg = options.bg || 'transparent';
  if (engine === 'beautiful-mermaid') {
    const mod = await load('beautiful-mermaid');
    if (format === 'svg') {
      const svg = mod.renderMermaidSVG(source, { bg, fg, transparent: bg === 'transparent' });
      process.stdout.write(svg);
    } else {
      const pad = options.padding || {};
      const text = mod.renderMermaidASCII(source, {
        useAscii: format === 'ascii',
        colorMode: 'none',
        ...(pad.x != null ? { paddingX: pad.x } : {}),
        ...(pad.y != null ? { paddingY: pad.y } : {}),
        ...(pad.box != null ? { boxBorderPadding: pad.box } : {}),
        ...(options.maxWidth ? { maxWidth: options.maxWidth } : {}),
      });
      process.stdout.write(text.endsWith('\n') ? text : text + '\n');
    }
  } else if (engine === 'pele') {
    if (format !== 'svg') {
      process.stderr.write('pele renders SVG only\n');
      process.exit(1);
    }
    const mod = await load('pele');
    const { svg } = mod.render(source, {
      fontFamily: options.fontFamily || 'sans-serif',
      fontSize: options.fontSize || 14,
      ...(options.maxWidth ? { maxWidth: options.maxWidth } : {}),
    });
    process.stdout.write(themeSvg(svg, fg, bg));
  } else {
    process.stderr.write(`unknown engine "${engine}"\n`);
    process.exit(1);
  }
} catch (e) {
  process.stderr.write(`${(e && e.message) || e}`.split('\n')[0] + '\n');
  process.exit(1);
}
