// Validate generated associations, asset integrity and filename/MIME resolution.
// Optional: --preview <path.html> writes a standalone light/dark contact sheet.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
Module._extensions['.ets'] = (module, filename) => {
  module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText, filename);
};
const maps = require(path.join(root, 'entry/src/main/ets/config/MaterialFileIcons.ets'));
const { resolveFileIconName: icon, resolveFileIconResourcePath: resource } =
  require(path.join(root, 'entry/src/main/ets/utils/FileIconUtils.ets'));
const raw = path.join(root, 'entry/src/main/resources/rawfile');
const assetDir = path.join(raw, 'file-icons/material');
const source = JSON.parse(fs.readFileSync(path.join(assetDir, 'SOURCE.json'), 'utf8'));
let assertions = 0;
function equal(actual, expected) { assert.equal(actual, expected); assertions++; }
for (const [name, expected] of maps.MATERIAL_FILE_NAMES) {
  equal(icon(`/workspace/${name}`), expected);
}
for (const [ext, expected] of maps.MATERIAL_FILE_EXTENSIONS) {
  equal(icon(`sample.${ext}`), expected);
}
for (const [name, mime, expected] of [
  ['main.py', '', 'python'], ['main.ts', '', 'typescript'], ['main.js', '', 'javascript'],
  ['Main.ets', '', 'typescript'], ['App.vue', '', 'vue'], ['index.d.ts', '', 'typescript-def'],
  ['Dockerfile.dev', '', 'docker'], ['README.zh-CN.md', '', 'readme'], ['.env.local', '', 'tune'],
  ['.gitignore', '', 'git'], ['PACKAGE.JSON', '', 'nodejs'], ['oh-package.json5', '', 'json'],
  ['app.hap', '', 'zip'], ['folder/REPORT.PDF', '', 'pdf'],
  ['C:\\folder\\MAIN.PY', '', 'python'], ['file:///tmp/a%20b.PDF?download=1#page', '', 'pdf'],
  ['https://example.com/a%ZZ.py?raw=true', '', 'python'], ['local#name.py', '', 'python'],
  ['report', 'application/pdf; charset=utf-8', 'pdf'], ['file.unknown', 'image/png', 'image'],
  ['upload', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'word'],
  ['upload', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'table'],
  ['upload', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 'powerpoint'],
  ['upload', 'audio/ogg', 'audio'], ['upload', 'video/webm', 'video'], ['upload', 'font/woff2', 'font'],
  ['upload', 'text/plain', 'document'], ['unknown.abcxyz', '', 'file'], ['', '', 'file'],
  ['constructor', '', 'file'], ['__proto__', '', 'file'], ['plot.svg', 'image/svg+xml', 'svg']
]) equal(icon(name, mime), expected);
equal(resource('config.toml', '', false), 'file-icons/material/toml_light.svg');
equal(resource('config.toml', '', true), 'file-icons/material/toml.svg');
const ids = new Set([...maps.MATERIAL_FILE_NAMES.values(), ...maps.MATERIAL_FILE_EXTENSIONS.values(),
  ...maps.MATERIAL_LIGHT_ICONS.values(), 'file', 'image', 'audio', 'video', 'font', 'document']);
for (const id of ids) {
  const bytes = fs.readFileSync(path.join(assetDir, `${id}.svg`));
  equal(crypto.createHash('sha256').update(bytes).digest('hex'), source.sha256[`${id}.svg`]);
}
equal(fs.readdirSync(assetDir).filter(name => name.endsWith('.svg')).length, source.iconCount);
assert.match(fs.readFileSync(path.join(assetDir, 'LICENSE.txt'), 'utf8'), /Copyright \(c\) 2025 Material Extensions/);
console.log(`${assertions} checks passed; ${source.iconCount} SVGs, ${(source.svgBytes / 1024).toFixed(1)} KiB.`);

const previewIndex = process.argv.indexOf('--preview');
if (previewIndex >= 0) {
  const examples = ['main.py', 'analysis.ipynb', 'index.js', 'main.ts', 'index.d.ts', 'Index.ets',
    'App.tsx', 'App.vue', 'main.go', 'main.rs', 'Main.java', 'main.cpp', 'main.swift', 'style.css',
    'index.html', 'data.json', 'config.yaml', 'config.toml', 'package.json', '.gitignore',
    'Dockerfile', '.env.local', 'README.zh-CN.md', 'notes.txt', 'report.pdf', 'report.docx',
    'budget.xlsx', 'slides.pptx', 'plot.svg', 'photo.png', 'music.mp3', 'video.mp4',
    'archive.zip', 'data.sqlite', 'model.onnx', 'unknown.abcxyz'];
  function panel(dark) {
    return `<section class="${dark ? 'dark' : 'light'}"><h2>${dark ? 'Dark' : 'Light'}</h2><div class="grid">` +
      examples.map(name => {
        const svg = fs.readFileSync(path.join(raw, resource(name, '', dark)), 'utf8');
        return `<div class="item"><div class="icon">${svg}</div><span>${name}</span></div>`;
      }).join('') + '</div></section>';
  }
  fs.writeFileSync(path.resolve(process.argv[previewIndex + 1]), `<!doctype html><meta charset="UTF-8">
<title>XCube · Material file icons</title><style>
*{box-sizing:border-box}body{margin:0;background:#ddd;font-family:system-ui,sans-serif}main{display:flex;gap:16px;padding:16px}section{padding:24px;border-radius:16px;flex:1}.light{background:#fafafa;color:#263238}.dark{background:#16191f;color:#e6edf3}h2{margin:0 0 18px;font-size:18px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px 12px}.item{display:flex;align-items:center;gap:8px;min-width:0}.icon{width:24px;height:24px;flex-shrink:0}.icon svg{width:100%;height:100%}span{font:12px ui-monospace,monospace;white-space:nowrap}
</style><main>${panel(false)}${panel(true)}</main>`);
  console.log(`Preview: ${path.resolve(process.argv[previewIndex + 1])}`);
}
