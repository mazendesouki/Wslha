import"./Footer.astro_astro_type_script_index_0_lang.2478d8ea.js";const l=document.querySelectorAll(".orders-filter"),i=document.getElementById("orders-empty");function c(t){const s=document.querySelectorAll(".order-row");let r=0;s.forEach(e=>{const a=t==="all"||e.dataset.status===t;e.style.display=a?"":"none",a&&r++}),i.classList.toggle("is-visible",r===0)}l.forEach(t=>{t.addEventListener("click",()=>{l.forEach(s=>{s.classList.remove("is-active"),s.setAttribute("aria-pressed","false")}),t.classList.add("is-active"),t.setAttribute("aria-pressed","true"),c(t.dataset.filter??"all")})});function d(t){try{const s=new Date(t),e=new Date().getTime()-s.getTime();return e<6e4?"الآن":e<36e5?`منذ ${Math.floor(e/6e4)} دقيقة`:e<864e5?`منذ ${Math.floor(e/36e5)} ساعة`:s.toLocaleDateString("ar-EG",{day:"numeric",month:"long"})}catch{return"—"}}function u(){try{const t=JSON.parse(localStorage.getItem("wslha_user")||"{}");return t.phone?"wslha_orders_"+t.phone:"wslha_orders"}catch{return"wslha_orders"}}function p(){try{const t=JSON.parse(localStorage.getItem(u())||"[]"),s=document.getElementById("orders-list");if(!t.length){c("all");return}i.classList.remove("is-visible");const r={active:{label:"قيد التوصيل",cls:"order-row__status--active"},delivered:{label:"تم التسليم",cls:"order-row__status--delivered"},cancelled:{label:"ملغي",cls:"order-row__status--cancelled"}};t.forEach(e=>{const a=r[e.status]||r.active,n=e.status==="active"?`<a href="/track?q=${e.id}" class="order-row__track">تتبع ←</a>`:"",o=document.createElement("article");o.className="order-row order-row--new",o.dataset.status=e.status,o.innerHTML=`
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
          </div>`,s.prepend(o)}),c("all")}catch{}}p();
