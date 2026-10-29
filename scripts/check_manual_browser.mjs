// Test-host-only desktop/mobile audit. Native publication has no browser dependency.
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const site = path.resolve(process.argv[2] || '.roc-pdf-tmp/manual-build/site');
const output = path.resolve(process.argv[3] || '.roc-pdf-tmp/manual-review');
const chrome = process.env.CHROME || (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : '/usr/bin/google-chrome');
await fs.mkdir(output, { recursive: true });
const profile = await fs.mkdtemp(path.join(os.tmpdir(), 'roc-pdf-manual-browser-'));
const child = spawn(chrome, ['--headless', '--disable-gpu', '--no-sandbox', '--no-first-run',
  `--user-data-dir=${profile}`, '--remote-debugging-port=0', 'about:blank'], { stdio: 'ignore' });
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let ws;
try {
  let port;
  for (let attempt = 0; attempt < 200; attempt++) {
    try { port = (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; break; }
    catch { await pause(50); }
  }
  assert.ok(port, 'Chrome did not expose its test endpoint');
  const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(response => response.json());
  ws = new WebSocket(targets.find(target => target.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let next = 0;
  const pending = new Map();
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(JSON.stringify(message.error))); else resolve(message.result);
    }
  };
  const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++next; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => {
    const result = await command('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  await command('Page.enable');
  const records = [];
  const pages = (await fs.readdir(site)).filter(name => name.endsWith('.html')).sort();
  for (const width of [1280, 390]) {
    await command('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: width === 390 });
    for (const name of pages) {
      await command('Page.navigate', { url: pathToFileURL(path.join(site, name)).href });
      for (let attempt = 0; attempt < 100; attempt++) {
        if (await evaluate(`document.readyState === "complete" && location.pathname.endsWith(${JSON.stringify('/' + name)})`)) break;
        await pause(25);
      }
      await evaluate('document.fonts.ready.then(() => true)');
      const facts = await evaluate(`(() => ({
        width: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        title: document.querySelector('h1')?.textContent,
        images: [...document.images].map(image => ({loaded: image.complete && image.naturalWidth > 0, alt: image.alt})),
        colours: [...new Set([...document.querySelectorAll('pre span')].map(span => getComputedStyle(span).color))],
        transparent: [...document.querySelectorAll('pre span')].every(span => getComputedStyle(span).backgroundColor === 'rgba(0, 0, 0, 0)'),
        tables: document.querySelectorAll('table').length
      }))()`);
      assert.ok(facts.title, `${name}: missing title`);
      assert.ok(facts.scrollWidth <= facts.width + 1, `${name}: overflow at ${width}: ${JSON.stringify(facts)}`);
      assert.ok(facts.images.every(image => image.loaded && image.alt), `${name}: unloaded/unlabelled figure`);
      assert.ok(facts.transparent, `${name}: token backgrounds obscure source`);
      if (name === 'authoring.html') {
        assert.ok(facts.colours.length >= 3 && facts.tables >= 1, 'authoring lost highlighting or capability table: ' + JSON.stringify(facts));
      }
      records.push({ page: name, viewport: width, ...facts });
      if (['index.html', 'authoring.html', 'gallery.html'].includes(name)) {
        const screenshot = await command('Page.captureScreenshot', { format: 'png' });
        await fs.writeFile(path.join(output, `${width}-${name}.png`), Buffer.from(screenshot.data, 'base64'));
      }
      if (name === 'index.html' && width === 390) {
        assert.equal(await evaluate(`(() => { const summary=document.querySelector('#toc summary'); const before=summary.parentElement.open; summary.click(); const changed=summary.parentElement.open!==before; summary.click(); return changed && summary.parentElement.open===before; })()`), true, 'mobile contents control failed');
      }
    }
  }
  await command('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }] });
  await command('Page.navigate', { url: pathToFileURL(path.join(site, 'authoring.html')).href });
  await pause(250);
  const dark = await evaluate('getComputedStyle(document.body).backgroundColor');
  assert.ok(dark !== 'rgb(255, 255, 255)', 'dark colour scheme did not apply');
  const screenshot = await command('Page.captureScreenshot', { format: 'png' });
  await fs.writeFile(path.join(output, '390-dark-authoring.png'), Buffer.from(screenshot.data, 'base64'));
  const report = { node: process.version, chrome: execFileSync(chrome, ['--version'], { encoding: 'utf8' }).trim(),
    chrome_sha256: createHash('sha256').update(await fs.readFile(chrome)).digest('hex'), records };
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`PASS browser: ${pages.length} pages at desktop/mobile widths, figures, source colours, tables and contents; ${output}`);
} finally {
  ws?.close(); child.kill();
  await pause(100);
  await fs.rm(profile, { recursive: true, force: true });
}
