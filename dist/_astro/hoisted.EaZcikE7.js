import"./hoisted.DdLzwlQF.js";const l=document.querySelectorAll(".orders-filter"),i=document.getElementById("orders-empty");function d(t){const r=document.querySelectorAll(".order-row");let a=0;r.forEach(s=>{const e=t==="all"||s.dataset.status===t;s.style.display=e?"":"none",e&&a++}),i.classList.toggle("is-visible",a===0)}l.forEach(t=>{t.addEventListener("click",()=>{l.forEach(r=>{r.classList.remove("is-active"),r.setAttribute("aria-pressed","false")}),t.classList.add("is-active"),t.setAttribute("aria-pressed","true"),d(t.dataset.filter??"all")})});function u(t){try{const r=new Date(t),s=new Date().getTime()-r.getTime();return s<6e4?"الآن":s<36e5?`منذ ${Math.floor(s/6e4)} دقيقة`:s<864e5?`منذ ${Math.floor(s/36e5)} ساعة`:r.toLocaleDateString("ar-EG",{day:"numeric",month:"long"})}catch{return"—"}}function m(){try{const t=JSON.parse(localStorage.getItem("wslha_orders")||"[]");if(!t.length)return;const r=document.getElementById("orders-list"),a=document.createElement("p");a.className="orders-section-label",a.textContent="▸ طلباتي الأخيرة",r.insertAdjacentElement("beforebegin",a);const s={active:{label:"قيد التوصيل",cls:"order-row__status--active"},delivered:{label:"تم التسليم",cls:"order-row__status--delivered"},cancelled:{label:"ملغي",cls:"order-row__status--cancelled"}};t.forEach(e=>{const o=s[e.status]||s.active,n=e.status==="active"?`<a href="/track?q=${e.id}" class="order-row__track">تتبع ←</a>`:"",c=document.createElement("article");c.className="order-row order-row--new",c.dataset.status=e.status,c.innerHTML=`
          <div class="order-row__icon" aria-hidden="true">${e.icon}</div>
          <div>
            <p class="order-row__id">${e.id}</p>
            <p class="order-row__meta">${e.type} · ${e.route}</p>
            <p class="order-row__date">${u(e.createdAt)}</p>
          </div>
          <div class="order-row__side">
            <span class="order-row__price">${e.price}</span>
            <span class="order-row__status ${o.cls}">${o.label}</span>
            ${n}
          </div>`,r.prepend(c)})}catch{}}m();
