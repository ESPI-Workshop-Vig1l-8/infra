// Imprime rapport.html en PDF A4 avec le Chromium de l'image mermaid-cli (appelé par build.sh).
const puppeteer = require('puppeteer');
(async () => {
  const [src, out] = process.argv.slice(2);
  const browser = await puppeteer.launch({ args: ['--no-sandbox'], executablePath: '/usr/bin/chromium-browser' });
  const page = await browser.newPage();
  await page.goto('file://' + src, { waitUntil: 'networkidle0' });
  await page.pdf({ path: out, preferCSSPageSize: true, printBackground: true, displayHeaderFooter: false });
  await browser.close();
  console.log('PDF écrit : ' + out);
})();
