/**
 * Shared browser plumbing for the local end-to-end runs.
 *
 * The tile interception is the part worth explaining. The map's base layer is
 * OpenStreetMap (and CARTO's dark basemap when the console is in dark mode),
 * and neither is reachable from a CI runner or from this audit container — the
 * egress policy refuses the CONNECT. Left alone, every map screenshot shows an
 * empty grey page with markers floating on nothing, and "the map renders" means
 * nothing at all.
 *
 * So tile requests are answered locally with a generated PNG carrying its own
 * z/x/y. That is better evidence than the real thing, not worse:
 *
 *   - the base layer is visibly present, so a screenshot shows a real map;
 *   - every tile the app asks for is recorded, so the run can assert the map is
 *     actually over Plateau State rather than centred in the Atlantic;
 *   - the test does not depend on a third party's uptime or rate limit.
 *
 * It does NOT prove OpenStreetMap's tiles render, which needs the real
 * endpoint. What it proves is that Leaflet is initialised, positioned and
 * asking for the right ground.
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const pathJoin = path.join;
const fsExists = (p) => fs.existsSync(p);
const readFile = (p) => fs.readFileSync(p);
const CONTENT_TYPES = {
  '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.symbols': 'text/plain', '.map': 'application/json',
};
const contentTypeFor = (p) => CONTENT_TYPES[path.extname(p)] || 'application/octet-stream';

const puppeteer = require(path.join(
  __dirname, '..', '..', 'hq-dashboard-next', 'node_modules', 'puppeteer',
));

const TILE_HOSTS = /(?:tile\.openstreetmap\.org|basemaps\.cartocdn\.com)/;

/** CRC32, for the PNG chunks. */
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/**
 * A 256×256 PNG: a flat ground with a one-pixel border, so tile seams are
 * visible in a screenshot and a missing tile is obvious.
 */
function tilePng(dark) {
  const size = 256;
  const ground = dark ? [26, 32, 38] : [233, 229, 220];
  const line = dark ? [46, 56, 64] : [208, 201, 188];

  const raw = Buffer.alloc(size * (size * 3 + 1));
  let p = 0;
  for (let y = 0; y < size; y++) {
    raw[p++] = 0; // filter: none
    for (let x = 0; x < size; x++) {
      const edge = x === 0 || y === 0 || x === size - 1 || y === size - 1;
      const c = edge ? line : ground;
      raw[p++] = c[0];
      raw[p++] = c[1];
      raw[p++] = c[2];
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 2;   // truecolour
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 6 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const LIGHT_TILE = tilePng(false);
const DARK_TILE = tilePng(true);

/**
 * Launch a browser whose pages serve map tiles locally and record every tile
 * asked for. Returns { browser, newPage, tiles, problems, dialogs, state }.
 *
 * The three collectors can be passed IN, which is what lets a long run replace
 * its browser part-way through without losing what it has recorded. A Flutter
 * release build in CanvasKit mode holds a large GPU-side surface per page, and
 * a run that signs in as eight accounts in turn exhausted this container before
 * the eighth: the browser died and the run ended on a TargetCloseError, with the
 * screens it had already captured intact but its report never written. Replacing
 * the browser between roles costs a few seconds of startup and removes that
 * whole failure mode — but only if the tile log and the error log survive it,
 * since those are the run's evidence.
 */
async function launch({
  viewport,
  canvaskitDir = null,
  /**
   * Give the browser a synthetic camera and microphone, and auto-grant them.
   *
   * The live stream — the control that turns on a phone's camera and mic and
   * offers them to HQ over WebRTC — had never been pressed by any test, because
   * a headless browser has no capture device and `getUserMedia` rejects. That is
   * the single feature in this app with the largest gap between what it does
   * and what had been verified about it, so it is worth the two flags.
   *
   * Off by default: every other pass should keep failing a permission prompt
   * the way a real device would if the user declined.
   */
  fakeMedia = false,
  /** Every tile the app requested: { z, x, y, dark }. */
  tiles = [],
  /** Anything the browser complained about, tagged with the screen. */
  problems = [],
  /** Native confirm/alert/prompt dialogs, which block the page until answered. */
  dialogs = [],
  state = { screen: 'startup' },
} = {}) {
  const browser = await puppeteer.launch({
    headless: true,
    // CI installs the Chrome that puppeteer-core expects. A container that
    // already has a Chromium — and cannot download another — sets this
    // instead, so these harnesses can be reproduced outside CI rather than
    // only read about.
    ...(process.env.PUPPETEER_EXECUTABLE_PATH
      ? { executablePath: process.env.PUPPETEER_EXECUTABLE_PATH }
      : {}),
    args: [
      '--no-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none',
      ...(fakeMedia
        ? ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream']
        : []),
    ],
    defaultViewport: viewport,
  });

  async function newPage() {
    const page = await browser.newPage();
    await page.setRequestInterception(true);

    // ONE request handler. Registering a second one elsewhere does not layer:
    // both fire, both try to resolve the same request, and whichever calls
    // `continue()` first lets it out to the network. That is how map tiles
    // escaped this interception and failed with CORS errors in the mobile run,
    // while this handler believed it was serving them.
    page.on('request', (req) => {
      const url = req.url();

      // A Flutter release build fetches CanvasKit from gstatic, which the
      // egress policy refuses. The same files ship in build/web/canvaskit.
      if (canvaskitDir) {
        const ck = url.match(/gstatic\.com\/flutter-canvaskit\/[^/]+\/(.+)$/);
        if (ck) {
          const local = pathJoin(canvaskitDir, ck[1]);
          if (fsExists(local)) {
            return req.respond({
              status: 200,
              contentType: contentTypeFor(local),
              body: readFile(local),
            });
          }
        }
      }

      if (TILE_HOSTS.test(url)) {
        const dark = url.includes('cartocdn');
        const m = url.match(/\/(\d+)\/(\d+)\/(\d+)\.png/);
        if (m) tiles.push({ z: +m[1], x: +m[2], y: +m[3], dark });
        return req.respond({
          status: 200,
          contentType: 'image/png',
          body: dark ? DARK_TILE : LIGHT_TILE,
        });
      }
      req.continue();
    });

    page.on('console', (m) => {
      if (m.type() === 'error') {
        problems.push({ screen: state.screen, kind: 'console', text: m.text().slice(0, 300) });
      }
    });
    page.on('pageerror', (e) => {
      // The stack matters as much as the message: a minified TypeError with no
      // stack cannot be attributed to anything, and an unattributed error gets
      // reported as either "the app is broken" or "it is probably fine",
      // neither of which is a finding.
      problems.push({
        screen: state.screen,
        kind: 'pageerror',
        text: String(e).slice(0, 300),
        stack: (e && e.stack ? String(e.stack) : '').slice(0, 1200),
        // Whether a synthetic keystroke was in flight. Minified line numbers
        // change with every build, so a stack-line allowlist rots silently;
        // WHEN an error fires is stable.
        whileTyping: !!state.typing,
      });
    });

    // A NATIVE DIALOG BLOCKS THE PAGE, AND EVERYTHING AFTER IT.
    //
    // `AgencyAccessManager` asks `confirm('Revoke portal access for …?')`
    // before deactivating a liaison. A `confirm()` stops the page's main
    // thread until something answers it, so every `page.evaluate` that follows
    // times out — the run dies on
    // `ProtocolError: Runtime.callFunctionOn timed out`, forty checks in, with
    // nothing in the log to say a dialog was ever on screen. It took a console
    // sweep that reached the whole screen to find this: the previous sweep
    // stopped at the first control that changed anything and never got to the
    // revoke button.
    //
    // DISMISSED, not accepted. Accepting it would revoke a liaison's access
    // mid-run and change the data the checks after it read — a harness must
    // not take a destructive action it was not asked to take. Recorded so a
    // control that opens a dialog counts as having DONE something rather than
    // being reported dead.
    page.on('dialog', async (d) => {
      dialogs.push({
        screen: state.screen,
        type: d.type(),
        message: d.message().slice(0, 200),
      });
      try {
        await d.dismiss();
      } catch {
        /* already gone: the page navigated out from under it */
      }
    });

    return page;
  }

  return { browser, newPage, tiles, problems, state, dialogs };
}

/**
 * Longitude/latitude of a tile's north-west corner, so a run can say where the
 * map actually is rather than trusting the centre it was configured with.
 */
function tileToLatLon(z, x, y) {
  const n = 2 ** z;
  const lon = (x / n) * 360 - 180;
  const latRad = Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n)));
  return { lat: (latRad * 180) / Math.PI, lon };
}

module.exports = { launch, tileToLatLon, TILE_HOSTS };
