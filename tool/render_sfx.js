// Renders the sounds of web/sfx.js to assets/sfx/*.wav for the app.
// Run: NODE_PATH=$(npm root -g) node tool/render_sfx.js web/sfx.js assets/sfx
// (needs Playwright with Chromium).
const { chromium } = require('playwright');
const fs = require('fs');
const [sfxPath, outDir] = process.argv.slice(2);
const src = fs.readFileSync(sfxPath, 'utf8');
const names = ['card','draw','deal','shuffle','flip','turn','start','skip','reverse','penalty','wild','last','caught','swap','knockout','win','lose','tick','nope'];
(async () => {
  const b = await chromium.launch();
  for (const name of names) {
    const p = await b.newPage();
    await p.setContent('<html></html>');
    const data = await p.evaluate(async ({ src, name }) => {
      const rate = 22050;
      let off;
      window.AudioContext = function () {
        off = new OfflineAudioContext(1, Math.round(rate * 2.2), rate);
        Object.defineProperty(off, 'state', { get: () => 'running' });
        off.resume = () => Promise.resolve();
        return off;
      };
      eval(src);
      window.lastCardSfx.play(name);
      const buf = await off.startRendering();
      const ch = buf.getChannelData(0);
      // Trim trailing silence, keep a short tail.
      let end = ch.length - 1;
      while (end > 0 && Math.abs(ch[end]) < 0.0008) end--;
      end = Math.min(ch.length, end + Math.round(rate * 0.03));
      const out = new Int16Array(end);
      for (let i = 0; i < end; i++) out[i] = Math.max(-1, Math.min(1, ch[i])) * 32767;
      return { rate, samples: Array.from(out) };
    }, { src, name });
    const n = data.samples.length;
    const buf = Buffer.alloc(44 + n * 2);
    buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
    buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
    buf.writeUInt32LE(data.rate, 24); buf.writeUInt32LE(data.rate * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
    buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
    data.samples.forEach((s, i) => buf.writeInt16LE(s, 44 + i * 2));
    fs.writeFileSync(`${outDir}/${name}.wav`, buf);
    console.log(name, (n / data.rate).toFixed(2) + 's');
    await p.close();
  }
  await b.close();
})();
