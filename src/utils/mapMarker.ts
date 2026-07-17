// ─────────────────────────────────────────────────────────────
// Lightweight top-down car marker for Google Maps: a small rotated
// SVG icon (cheap — no WebGL/3D layer) plus a position tween so the
// marker glides between GPS updates instead of jumping.
// The rides.astro page runs a `define:vars` inline script and can't
// import this module — it embeds the SAME logic inline. Keep both
// in sync if you change something here.
// ─────────────────────────────────────────────────────────────

const CAR_SIZE = 44; // متوسط الحجم — كان 30

export function carIconUrl(headingDeg: number, color = '#16a34a'): string {
  const c = CAR_SIZE / 2;
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" width="${CAR_SIZE}" height="${CAR_SIZE}" viewBox="0 0 ${CAR_SIZE} ${CAR_SIZE}">
      <g transform="rotate(${headingDeg} ${c} ${c})">
        <ellipse cx="${c}" cy="${c + 1.5}" rx="8.1" ry="4.4" fill="rgba(0,0,0,.18)"/>
        <path d="M${c} 6 C${c + 5.1} 6 ${c + 8.1} 11.7 ${c + 8.1} 19.1 L${c + 8.1} 30.8
                 C${c + 8.1} 34.5 ${c + 5.1} 36.7 ${c} 36.7 C${c - 5.1} 36.7 ${c - 8.1} 34.5 ${c - 8.1} 30.8
                 L${c - 8.1} 19.1 C${c - 8.1} 11.7 ${c - 5.1} 6 ${c} 6 Z"
              fill="${color}" stroke="#fff" stroke-width="2.3"/>
        <path d="M${c - 5.4} 16.9 C${c - 5.4} 13.2 ${c - 3.2} 10.7 ${c} 10.7 C${c + 3.2} 10.7 ${c + 5.4} 13.2 ${c + 5.4} 16.9
                 L${c + 5.4} 19.4 L${c - 5.4} 19.4 Z" fill="#e8fdf1" opacity=".9"/>
        <rect x="${c - 6.2}" y="24.2" width="12.4" height="3.2" rx="1.6" fill="#0b3d3a" opacity=".55"/>
      </g>
    </svg>`.trim();
  return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg);
}

export function carIcon(headingDeg: number, color = '#16a34a') {
  return {
    url: carIconUrl(headingDeg, color),
    scaledSize: new google.maps.Size(CAR_SIZE, CAR_SIZE),
    anchor: new google.maps.Point(CAR_SIZE / 2, CAR_SIZE / 2),
  };
}

// Great-circle initial bearing, in degrees (0 = north), for when the
// device's own compass heading (coords.heading) is null/unreliable —
// common while driving with the screen off or on cheaper phones.
export function bearingBetween(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const y = Math.sin(toRad(lng2 - lng1)) * Math.cos(toRad(lat2));
  const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
    Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(toRad(lng2 - lng1));
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

// Glides a marker from its current position to (lat,lng) over `ms`
// instead of snapping — the marker itself stores its animation timer
// on `marker.__moveRaf` so a fresh call cancels any tween in progress.
export function animateMarkerTo(marker: google.maps.Marker, lat: number, lng: number, ms = 2800) {
  const from = marker.getPosition();
  const fromLat = from ? from.lat() : lat;
  const fromLng = from ? from.lng() : lng;
  if ((marker as any).__moveRaf) cancelAnimationFrame((marker as any).__moveRaf);

  const start = performance.now();
  function step(now: number) {
    const t = Math.min(1, (now - start) / ms);
    const eased = 1 - Math.pow(1 - t, 2); // ease-out
    marker.setPosition({ lat: fromLat + (lat - fromLat) * eased, lng: fromLng + (lng - fromLng) * eased });
    if (t < 1) (marker as any).__moveRaf = requestAnimationFrame(step);
  }
  (marker as any).__moveRaf = requestAnimationFrame(step);
}
