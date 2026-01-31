/**
 * Fetches the Ajv UMD build from jsDelivr and writes it to static/js/ajv.min.js
 * so the validation worker can load Ajv same-origin (avoids CDN/CSP issues).
 * Run: node scripts/fetch-ajv-umd.js
 */
const https = require('https');
const fs = require('fs');
const path = require('path');

const URL =
  'https://cdn.jsdelivr.net/npm/ajv@8.17.1/dist/ajv.min.js';
const outDir = path.resolve(__dirname, '..', 'static', 'js');
const outFile = path.join(outDir, 'ajv.min.js');

if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

https
  .get(URL, (res) => {
    if (res.statusCode !== 200) {
      console.error('Failed to fetch Ajv:', res.statusCode);
      process.exit(1);
    }
    const chunks = [];
    res.on('data', (chunk) => chunks.push(chunk));
    res.on('end', () => {
      fs.writeFileSync(outFile, Buffer.concat(chunks));
      console.log('Wrote static/js/ajv.min.js');
    });
  })
  .on('error', (err) => {
    console.error(err);
    process.exit(1);
  });
