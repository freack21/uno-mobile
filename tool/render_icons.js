// Renders tool/icon.svg into the PNG icons used by the web/PWA build.
// Usage (needs Playwright): node tool/render_icons.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const svg = fs.readFileSync(path.join(__dirname, 'icon.svg'), 'utf8');
const font = fs.readFileSync(path.join(root, 'assets/fonts/Fredoka.ttf')).toString('base64');

// [file, size, scale of the card artwork]. Maskable icons keep the artwork
// inside the 80% safe zone; "any" icons can use more of the canvas.
const targets = [
  ['web/icons/Icon-192.png', 192, 1],
  ['web/icons/Icon-512.png', 512, 1],
  ['web/icons/Icon-maskable-192.png', 192, 0.78],
  ['web/icons/Icon-maskable-512.png', 512, 0.78],
  ['web/icons/apple-touch-icon.png', 180, 0.9],
  ['web/favicon.png', 64, 1.08],
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const [file, size, scale] of targets) {
    const art = svg.replace(
      'id="cards" transform="translate(256 262)"',
      `id="cards" transform="translate(256 262) scale(${scale})"`,
    );
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<style>
      @font-face { font-family: Fredoka; src: url(data:font/ttf;base64,${font}); font-weight: 300 700; }
      html, body { margin: 0; background: #14161B; }
      svg { width: ${size}px; height: ${size}px; display: block; }
    </style>${art}`);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(root, file), omitBackground: false });
    console.log('wrote', file);
  }
  await browser.close();
})();
