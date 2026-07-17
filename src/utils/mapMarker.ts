// ─────────────────────────────────────────────────────────────
// Lightweight top-down car marker for Google Maps: a small rotated
// SVG icon (cheap — no WebGL/3D layer) plus a position tween so the
// marker glides between GPS updates instead of jumping.
// The rides.astro page runs a `define:vars` inline script and can't
// import this module — it embeds the SAME logic inline. Keep both
// in sync if you change something here.
// ─────────────────────────────────────────────────────────────

export function carIconUrl(headingDeg: number, color = '#16a34a'): string {
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 30 30">
      <g transform="rotate(${headingDeg} 15 15)">
        <ellipse cx="15" cy="16" rx="5.5" ry="3" fill="rgba(0,0,0,.18)"/>
        <path d="M15 4 C18.5 4 20.5 8 20.5 13 L20.5 21 C20.5 23.5 18.5 25 15 25
                 C11.5 25 9.5 23.5 9.5 21 L9.5 13 C9.5 8 11.5 4 15 4 Z"
              fill="${color}" stroke="#fff" stroke-width="1.6"/>
        <path d="M11.3 11.5 C11.3 9 12.8 7.3 15 7.3 C17.2 7.3 18.7 9 18.7 11.5
                 L18.7 13.2 L11.3 13.2 Z" fill="#e8fdf1" opacity=".9"/>
        <rect x="10.8" y="16.5" width="8.4" height="2.2" rx="1.1" fill="#0b3d3a" opacity=".55"/>
      </g>
    </svg>`.trim();
  return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg);
}

export function carIcon(headingDeg: number, color = '#16a34a') {
  return {
    url: carIconUrl(headingDeg, color),
    scaledSize: new google.maps.Size(30, 30),
    anchor: new google.maps.Point(15, 15),
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
