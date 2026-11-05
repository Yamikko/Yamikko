// render.js — sert preview.html + scene.json et capture des PNG avec Playwright.
// usage : NODE_PATH=<node_modules> node render.js <scene.json> <outDir> <nodeModulesDir> [views]
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const [sceneFile, outDir, nm, only] = process.argv.slice(2);
const types = { '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const f = u === '/scene.json' ? sceneFile : u.startsWith('/node_modules/') ? path.join(nm, u.slice(14)) : path.join(__dirname, u);
  fs.readFile(f, (e, d) => { if (e) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); res.end(d); });
}).listen(0);
const NAMES = ['Common', 'Rare', 'Epic', 'Legendary', 'Mythic'];
const views = { lineup: { cam: '-8,8.5,-40,0,3.0,0', fov: 28, w: 1600, h: 900 } };
NAMES.forEach((n, i) => { const x = (2 - i) * 7; views[n] = { cam: `${x - 5.2},6.2,${-10.5},${x},3.5,0`, fov: 36, w: 640, h: 720, only: "Cabinet_" + n }; });
NAMES.forEach((n, i) => { const x = (2 - i) * 7; views['profile_' + n] = { cam: `${x - 30},3.6,0,${x},3.6,0`, fov: 16, w: 700, h: 700, only: 'Cabinet_' + n }; });
(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage();
  page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
  page.on('pageerror', e => console.log('pageerror:', e.message));
  const port = server.address().port;
  for (const [name, v] of Object.entries(views)) {
    if (only && !only.split(',').includes(name)) continue;
    const w = v.w || 1024, h = v.h || 576;
    await page.setViewportSize({ width: w, height: h });
    await page.goto(`http://localhost:${port}/preview.html?scene=/scene.json&cam=${v.cam}&fov=${v.fov}&w=${w}&h=${h}${v.only ? '&only=' + v.only : ''}`);
    await page.waitForFunction(() => window.__done === true, null, { timeout: 60000 });
    await page.screenshot({ path: path.join(outDir, `${name}.png`) });
    console.log('rendu', name);
  }
  await browser.close(); server.close();
})();
