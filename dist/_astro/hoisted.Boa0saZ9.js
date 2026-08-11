import"./hoisted.VIaS4Poc.js";const l=document.querySelectorAll(".orders-filter"),i=document.getElementById("orders-empty");function o(t){const r=document.querySelectorAll(".order-row");let s=0;r.forEach(e=>{const a=t==="all"||e.dataset.status===t;e.style.display=a?"":"none",a&&s++}),i.classList.toggle("is-visible",s===0)}l.forEach(t=>{t.addEventListener("click",()=>{l.forEach(r=>{r.classList.remove("is-active"),r.setAttribute("aria-pressed","false")}),t.classList.add("is-active"),t.setAttribute("aria-pressed","true"),o(t.dataset.filter??"all")})});function d(t){try{if(!t)return"—";const r=new Date(t);if(isNaN(r.getTime()))return"—";const e=new Date().getTime()-r.getTime();return e<6e4?"الآن":e<36e5?`منذ ${Math.floor(e/6e4)} دقيقة`:e<864e5?`منذ ${Math.floor(e/36e5)} ساعة`:r.toLocaleDateString("ar-EG",{day:"numeric",month:"long"})}catch{return"—"}}function u(){try{const t=JSON.parse(localStorage.getItem("wslha_user")||"{}");return t.phone?"wslha_orders_"+t.phone:"wslha_orders"}catch{return"wslha_orders"}}function p(){try{const t=JSON.parse(localStorage.getItem(u())||"[]"),r=document.getElementById("orders-list");if(!t.length){o("all");return}i.classList.remove("is-visible");const s={active:{label:"قيد التوصيل",cls:"order-row__status--active"},delivered:{label:"تم التسليم",cls:"order-row__status--delivered"},cancelled:{label:"ملغي",cls:"order-row__status--cancelled"}};t.forEach(e=>{const a=s[e.status]||s.active,n=e.status==="active"?`<a href="/track?q=${e.id}" class="order-row__track">تتبع ←</a>`:"",c=document.createElement("article");c.className="order-row order-row--new",c.dataset.status=e.status,c.innerHTML=`
          <div class="order-row__icon" aria-hidden="true">${e.icon}</div>
          <div>
            <p class="order-row__id">${e.id}</p>
            <p class="order-row__meta">${e.type} · ${e.route}</p>
            <p class="order-row__date">${d(e.createdAt)}</p>
          </div>
          <div class="order-row__side">
            <span class="order-row__price">${e.price}</span>
            <span class="order-row__status ${a.cls}">${a.label}</span>
            ${n}
          </div>`,r.prepend(c)}),o("all")}catch{}}p();
