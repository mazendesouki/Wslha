// Pure-Node PNG icon generator for the وصّلها PWA.
// Draws a brand-gradient rounded square with a white location pin.
// No external deps — uses zlib for IDAT compression.
import zlib from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';

const BRAND_TOP = [0x3b, 0x6e, 0xf8]; // #3B6EF8 brand blue
const BRAND_BOT = [0x29, 0x52, 0xd9]; // #2952D9 brand blue dark
const WHITE = [0xff, 0xff, 0xff];

function lerp(a, b, t) {
  return [
    Math.round(a[0] + (b[0] - a[0]) * t),
    Math.round(a[1] + (b[1] - a[1]) * t),
    Math.round(a[2] + (b[2] - a[2]) * t),
  ];
}

// Signed distance helpers ----------------------------------------------------
function roundedRectAlpha(x, y, S, pad, r) {
  // returns coverage 0..1 for a rounded square centred in the SxS canvas
  const lo = pad, hi = S - pad;
  let dx = 0, dy = 0;
  if (x < lo + r) dx = lo + r - x; else if (x > hi - r) dx = x - (hi - r);
  if (y < lo + r) dy = lo + r - y; else if (y > hi - r) dy = y - (hi - r);
  if (x < lo || x > hi || y < lo || y > hi) {
    if (dx === 0 || dy === 0) {
      // outside straight edge
      if (x < lo) return Math.max(0, 1 - (lo - x));
      if (x > hi) return Math.max(0, 1 - (x - hi));
      if (y < lo) return Math.max(0, 1 - (lo - y));
      if (y > hi) return Math.max(0, 1 - (y - hi));
    }
  }
  const d = Math.hypot(dx, dy);
  if (d <= r - 1) return 1;
  if (d >= r) return Math.max(0, r - d + 1 > 0 ? r - d + 1 : 0);
  return r - d; // soft edge
}

// Pin shape: head circle (with hole) + tapering body to a point.
function pinAlpha(x, y, S) {
  const cx = S / 2;
  const headCy = S * 0.40;
  const headR = S * 0.165;
  const tipY = S * 0.74;
  // hole
  const holeR = headR * 0.42;
  const dHead = Math.hypot(x - cx, y - headCy);

  // body: linear taper from head bottom to tip
  let bodyInside = false;
  if (y >= headCy && y <= tipY) {
    const t = (y - headCy) / (tipY - headCy);
    const halfW = headR * 0.95 * (1 - t);
    if (Math.abs(x - cx) <= halfW) bodyInside = true;
  }

  const inHead = dHead <= headR;
  let inside = inHead || bodyInside;
  if (!inside) return 0;
  // punch hole in head
  const dHole = Math.hypot(x - cx, y - headCy);
  if (dHole <= holeR) return 0;
  return 1;
}

function makePNG(S) {
  const raw = Buffer.alloc((S * 4 + 1) * S);
  let p = 0;
  for (let y = 0; y < S; y++) {
    raw[p++] = 0; // filter: none
    for (let x = 0; x < S; x++) {
      // background gradient
      const t = y / (S - 1);
      const bg = lerp(BRAND_TOP, BRAND_BOT, t);
      let r = bg[0], g = bg[1], b = bg[2], a = 255;

      // rounded-square mask (transparent corners)
      const rr = roundedRectAlpha(x + 0.5, y + 0.5, S, S * 0.06, S * 0.22);
      a = Math.round(255 * Math.min(1, Math.max(0, rr)));

      // pin (white)
      const pin = pinAlpha(x + 0.5, y + 0.5, S);
      if (pin > 0 && a > 0) {
        r = WHITE[0]; g = WHITE[1]; b = WHITE[2];
      }

      raw[p++] = r; raw[p++] = g; raw[p++] = b; raw[p++] = a;
    }
  }

  const idat = zlib.deflateSync(raw, { level: 9 });

  const crcTable = (() => {
    const t = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }
  function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
    const t = Buffer.from(type, 'ascii');
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
    return Buffer.concat([len, t, data, crc]);
  }
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0; // 8-bit RGBA
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

mkdirSync('public', { recursive: true });
writeFileSync('public/icon-192.png', makePNG(192));
writeFileSync('public/icon-512.png', makePNG(512));
writeFileSync('public/apple-touch-icon.png', makePNG(180));
// maskable needs safe padding — our rounded square already has margin; reuse 512
writeFileSync('public/icon-maskable-512.png', makePNG(512));
console.log('Icons generated: 192, 512, apple-touch (180), maskable-512');
