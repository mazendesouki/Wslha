import{f as o,u as c}from"./marketplaceApi.BAgn7257.js";import"./hoisted.VIaS4Poc.js";let i=null;try{i=JSON.parse(localStorage.getItem("wslha_user")||"null")}catch{}(!i||!i.phone)&&(window.location.href="/login?next=/marketplace/mine");function m(t){return String(t??"").replace(/[&<>"']/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[e])}function u(t){return Number(t||0).toLocaleString("ar-EG")+" ج.م"}const v={active:"منشور",sold:"تم البيع",removed:"محذوف",under_review:"قيد المراجعة"};let a=[];function l(){const t=document.getElementById("mine-content");if(!a.length){t.innerHTML=`<div class="mine-empty"><div class="mine-empty__icon">📦</div><p>لسه معملتش أي إعلان</p>
        <p><a href="/marketplace/post" style="color:var(--color-primary);font-weight:700">أضف أول إعلان لك ←</a></p></div>`;return}t.innerHTML=`<div class="mine-list">${a.map(e=>`
      <div class="mine-item" data-id="${e.id}">
        <div class="mine-item__cover">${e.images?.[0]?`<img src="${e.images[0]}" alt="">`:"📦"}</div>
        <div class="mine-item__body">
          <div class="mine-item__title">${m(e.title)}</div>
          <div class="mine-item__meta">👁️ ${e.views||0} مشاهدة</div>
          <div class="mine-item__price">${u(e.price)}</div>
          <span class="mine-item__status st-${e.status}">${v[e.status]||e.status}</span>
        </div>
        <div class="mine-item__actions">
          <button class="btn-mark-sold" data-id="${e.id}" ${e.status!=="active"?"disabled":""}>✅ تم البيع</button>
          <button class="btn-remove danger" data-id="${e.id}" ${e.status==="removed"?"disabled":""}>🗑️ حذف</button>
        </div>
      </div>`).join("")}</div>`,t.querySelectorAll(".btn-mark-sold").forEach(e=>{e.addEventListener("click",()=>d(e.dataset.id,"sold",e))}),t.querySelectorAll(".btn-remove").forEach(e=>{e.addEventListener("click",()=>{confirm("متأكد إنك عايز تحذف الإعلان ده؟")&&d(e.dataset.id,"removed",e)})})}async function d(t,e,s){if(s.disabled=!0,await c(i.phone,t,e)){const n=a.find(r=>r.id===t);n&&(n.status=e),l()}else s.disabled=!1,alert("تعذّر تحديث الإعلان — حاول مرة أخرى")}(async()=>(a=await o(i.phone),l()))();
