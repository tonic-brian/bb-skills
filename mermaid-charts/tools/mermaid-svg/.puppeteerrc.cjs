// Puppeteer's settings for mermaid-svg. `mermaid_svg.py setup` copies this file into the install folder, and every
// tool runs from there, so Puppeteer's search for its configuration ends here, in the folder it started from. A
// PUPPETEER_* variable would override it, so mermaid_svg.py runs the tools without any, except for the one download:
// PUPPETEER_CACHE_DIR then points at a folder of its own, which moves into browsers/ once the download is whole.
const {join} = require('node:path');

module.exports = {
  // The browser lives in the install folder, never in ~/.cache/puppeteer.
  cacheDirectory: join(__dirname, 'browsers'),
  // chrome-headless-shell is the one browser mermaid-cli renders with. Never the full Chrome, never Firefox.
  chrome: {skipDownload: true},
  'chrome-headless-shell': {skipDownload: false},
  firefox: {skipDownload: true},
};
