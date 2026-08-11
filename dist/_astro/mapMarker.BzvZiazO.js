function m(t,o="#16a34a"){const a=`
    <svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44">
      <g transform="rotate(${t} 22 22)">
        <ellipse cx="22" cy="${23.5}" rx="8.1" ry="4.4" fill="rgba(0,0,0,.18)"/>
        <path d="M22 6 C${27.1} 6 ${30.1} 11.7 ${30.1} 19.1 L${30.1} 30.8
                 C${30.1} 34.5 ${27.1} 36.7 22 36.7 C${16.9} 36.7 ${13.9} 34.5 ${13.9} 30.8
                 L${13.9} 19.1 C${13.9} 11.7 ${16.9} 6 22 6 Z"
              fill="${o}" stroke="#fff" stroke-width="2.3"/>
        <path d="M${16.6} 16.9 C${16.6} 13.2 ${18.8} 10.7 22 10.7 C${25.2} 10.7 ${27.4} 13.2 ${27.4} 16.9
                 L${27.4} 19.4 L${16.6} 19.4 Z" fill="#e8fdf1" opacity=".9"/>
        <rect x="${15.8}" y="24.2" width="12.4" height="3.2" rx="1.6" fill="#0b3d3a" opacity=".55"/>
      </g>
    </svg>`.trim();return"data:image/svg+xml;charset=UTF-8,"+encodeURIComponent(a)}function g(t,o="#16a34a"){return{url:m(t,o),scaledSize:new google.maps.Size(44,44),anchor:new google.maps.Point(44/2,44/2)}}function _(t,o,n,a){const c=i=>i*Math.PI/180,e=Math.sin(c(a-o))*Math.cos(c(n)),s=Math.cos(c(t))*Math.sin(c(n))-Math.sin(c(t))*Math.cos(c(n))*Math.cos(c(a-o));return(Math.atan2(e,s)*180/Math.PI+360)%360}function C(t,o,n,a=2800){const c=t.getPosition(),e=c?c.lat():o,s=c?c.lng():n;t.__moveRaf&&cancelAnimationFrame(t.__moveRaf);const i=performance.now();function $(h){const r=Math.min(1,(h-i)/a),f=1-Math.pow(1-r,2);t.setPosition({lat:e+(o-e)*f,lng:s+(n-s)*f}),r<1&&(t.__moveRaf=requestAnimationFrame($))}t.__moveRaf=requestAnimationFrame($)}export{C as a,_ as b,g as c};
