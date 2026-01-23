#!/usr/bin/env node
/**
 * Postinstall script to copy prismjs-gleam language definition
 * to prismjs/components/ so Docusaurus can find it.
 */

const fs = require('fs');
const path = require('path');

const gleamSource = path.join(__dirname, '../node_modules/prismjs-gleam/gleam.js');
const gleamDest = path.join(__dirname, '../node_modules/prismjs/components/prism-gleam.js');

if (fs.existsSync(gleamSource)) {
  fs.copyFileSync(gleamSource, gleamDest);
  console.log('✓ Copied prismjs-gleam to prismjs/components/prism-gleam.js');
} else {
  console.warn('⚠ prismjs-gleam not found, skipping Gleam language setup');
}
