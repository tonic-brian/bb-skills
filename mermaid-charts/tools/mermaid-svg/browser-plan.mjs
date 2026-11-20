// Prints, as one line of JSON, the browser `mermaid_svg.py setup` is about to install: its build, the URL it comes
// from, where Puppeteer's own `browsers install` would put it, and where mermaid-cli's launch will look for it. It
// downloads nothing. It runs from the install folder, so Puppeteer reads that folder's .puppeteerrc.cjs, as it does
// when it renders.
import {Browser, computeExecutablePath, detectBrowserPlatform, getDownloadUrl} from '@puppeteer/browsers';
import puppeteer from 'puppeteer';
import {PUPPETEER_REVISIONS} from 'puppeteer-core/internal/revisions.js';

const configuration = await puppeteer.configuration();
const browser = Browser.CHROMEHEADLESSSHELL;
// The build Puppeteer's own `browsers install` command picks for the headless shell.
const buildId = configuration[browser]?.version || PUPPETEER_REVISIONS[browser];
const platform = detectBrowserPlatform();
const cacheDir = configuration.cacheDirectory;

console.log(JSON.stringify({
  browser,
  buildId,
  platform,
  url: getDownloadUrl(browser, platform, buildId).href,
  cacheDirectory: cacheDir,
  installPath: computeExecutablePath({browser, buildId, platform, cacheDir}),
  // mermaid-cli launches the headless shell; this is where that launch will look for it.
  executablePath: await puppeteer.executablePath({headless: 'shell'}),
  skipsChrome: configuration.chrome?.skipDownload === true,
  skipsFirefox: configuration.firefox?.skipDownload === true,
}));
