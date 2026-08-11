import{c as l,e as o}from"./marketplaceApi.CHYm1uEh.js";import"./hoisted.VIaS4Poc.js";let r=[],a="";function m(e){return Number(e||0).toLocaleString("ar-EG")+" ج.م"}function n(){const e=document.getElementById("mkt-search").value.trim().toLowerCase();let i=r;a&&(i=i.filter(t=>t.category===a)),e&&(i=i.filter(t=>t.title.toLowerCase().includes(e)||(t.description||"").toLowerCase().includes(e))),document.getElementById("mkt-count").textContent=String(i.length);const s=document.getElementById("mkt-grid");if(!i.length){s.innerHTML='<div class="no-results"><div class="no-results__icon">🔍</div><p>لا توجد إعلانات مطابقة</p></div>';return}s.innerHTML=i.map(t=>`
      <a class="item-card" href="/marketplace/item?id=${t.id}">
        <div class="item-card__cover">
          ${t.images?.[0]?`<img src="${t.images[0]}" loading="lazy" alt="">`:"📦"}
          ${t.seller_type==="merchant"?'<span class="item-card__merchant">🏪 تاجر</span>':""}
          <span class="item-card__badge">${t.condition==="new"?"جديد":t.condition==="like_new"?"كالجديد":"مستعمل"}</span>
        </div>
        <div class="item-card__body">
          <div class="item-card__title">${t.title}</div>
          <div class="item-card__meta">📍 ${t.city||t.area||"دمياط الجديدة"}</div>
          <div class="item-card__price">${m(t.price)}</div>
        </div>
      </a>`).join("")}function v(){const e=document.getElementById("mkt-grid");e.innerHTML=Array.from({length:8}).map(()=>`
      <div class="skeleton-card" aria-hidden="true">
        <div class="skeleton-card__cover"></div>
        <div class="skeleton-card__line"></div>
        <div class="skeleton-card__line skeleton-card__line--short"></div>
      </div>`).join("")}async function d(){v();try{r=await o(),n()}catch{const e=document.getElementById("mkt-grid");e.innerHTML='<div class="no-results"><div class="no-results__icon">⚠️</div><p>تعذّر تحميل الإعلانات — تحقق من اتصالك بالإنترنت</p><button class="no-results__retry" id="mkt-retry">إعادة المحاولة</button></div>',document.getElementById("mkt-retry")?.addEventListener("click",d)}}document.getElementById("mkt-search").addEventListener("input",n);const c=document.getElementById("mkt-cats");c.innerHTML='<button class="cat-chip is-active" data-cat="">🗂️ الكل</button>'+l.map(e=>`<button class="cat-chip" data-cat="${e.id}">${e.emoji} ${e.label}</button>`).join("");c.querySelectorAll(".cat-chip").forEach(e=>{e.addEventListener("click",()=>{a=e.dataset.cat||"",c.querySelectorAll(".cat-chip").forEach(i=>i.classList.remove("is-active")),e.classList.add("is-active"),n()})});d();
