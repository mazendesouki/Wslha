// Professional brand icon generator for وصّلها.
// Renders an SVG (gradient square + white location pin + "وصّلها" wordmark)
// to crisp PNGs using @resvg/resvg-js with the Cairo Arabic brand font.
import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const FONT = readFileSync(new URL('./fonts/Cairo.ttf', import.meta.url));

// ── SVG builder ─────────────────────────────────────────────────────────────
// S = canvas size. `bleed` = true → full-bleed square (maskable / native bg).
// `withName` = include the "وصّلها" wordmark under the pin.
function buildSVG(S, { bleed = false, withName = true } = {}) {
  const k = S / 512; // everything below is authored in a 512 grid
  const r = (n) => +(n * k).toFixed(2);

  // background rounded square
  const pad = bleed ? 0 : r(14);
  const radius = bleed ? r(96) : r(112);
  const bgRect = `<rect x="${pad}" y="${pad}" width="${S - pad * 2}" height="${S - pad * 2}" rx="${radius}" fill="url(#bg)"/>`;

  // location pin — teardrop with a punched hole (evenodd)
  const cx = 256;
  const hy = withName ? 168 : 196;     // head centre (raise when name shown)
  const pr = withName ? 86 : 104;      // head radius
  const hr = pr * 0.40;                // hole radius
  const ty = hy + pr * 2.15;           // tip y
  const pin = [
    `M ${cx} ${ty}`,
    `L ${cx - pr} ${hy}`,
    `A ${pr} ${pr} 0 1 1 ${cx + pr} ${hy}`,
    `Z`,
    // hole (reverse winding via evenodd)
    `M ${cx + hr} ${hy}`,
    `A ${hr} ${hr} 0 1 0 ${cx - hr} ${hy}`,
    `A ${hr} ${hr} 0 1 0 ${cx + hr} ${hy}`,
    `Z`,
  ].join(' ');
  const pinPath = `<path d="${pin}" fill="#fff" fill-rule="evenodd"
      transform="scale(${k})" />`;

  // wordmark
  const name = withName
    ? `<text x="${S / 2}" y="${r(430)}" text-anchor="middle"
         font-family="Cairo" font-weight="800" font-size="${r(104)}"
         fill="#fff" direction="rtl">وصّلها</text>`
    : '';

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#3B6EF8"/>
        <stop offset="1" stop-color="#2952D9"/>
      </linearGradient>
    </defs>
    ${bgRect}
    ${pinPath}
    ${name}
  </svg>`;
}

function render(svg) {
  const resvg = new Resvg(svg, {
    font: { fontBuffers: [FONT], defaultFontFamily: 'Cairo', loadSystemFonts: false },
    shapeRendering: 2,
    textRendering: 2,
  });
  return resvg.render().asPng();
}

mkdirSync('public', { recursive: true });
mkdirSync('assets', { recursive: true });

// ── PWA icons (rounded, with brand name) ───────────────────────────────────
writeFileSync('public/icon-192.png',          render(buildSVG(192, { withName: true })));
writeFileSync('public/icon-512.png',          render(buildSVG(512, { withName: true })));
writeFileSync('public/apple-touch-icon.png',  render(buildSVG(180, { withName: true })));
// maskable: full-bleed so the platform mask never clips the name
writeFileSync('public/icon-maskable-512.png', render(buildSVG(512, { bleed: true, withName: true })));

// ── Native assets for @capacitor/assets ────────────────────────────────────
writeFileSync('assets/icon-only.png',       render(buildSVG(1024, { withName: true })));
writeFileSync('assets/icon-foreground.png', render(buildSVG(1024, { bleed: true, withName: true })));
writeFileSync('assets/icon-background.png', render(
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><rect width="1024" height="1024" fill="#3B6EF8"/></svg>`));

// ── Splash screens (centred lockup on solid brand bg) ──────────────────────
function splashSVG(bg) {
  // 2732² canvas; place the 512-grid lockup centred at ~38% scale
  const W = 2732, scale = 1040, x = (W - scale) / 2, y = (W - scale) / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}">
    <rect width="${W}" height="${W}" fill="${bg}"/>
    <g transform="translate(${x} ${y}) scale(${scale / 512})">
      <path d="M 256 ${168 + 86 * 2.15} L 170 168 A 86 86 0 1 1 342 168 Z
               M ${256 + 34.4} 168 A 34.4 34.4 0 1 0 ${256 - 34.4} 168 A 34.4 34.4 0 1 0 ${256 + 34.4} 168 Z"
            fill="#fff" fill-rule="evenodd"/>
      <text x="256" y="430" text-anchor="middle" font-family="Cairo"
            font-weight="800" font-size="104" fill="#fff" direction="rtl">وصّلها</text>
    </g>
  </svg>`;
}
writeFileSync('assets/splash.png',      render(splashSVG('#3B6EF8')));
writeFileSync('assets/splash-dark.png', render(splashSVG('#2952D9')));

console.log('Brand icons + splash generated (pin + وصّلها wordmark).');
