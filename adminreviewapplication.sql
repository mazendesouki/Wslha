-- =====================================================================
--  وصّلها — admin_review_application: اعتماد/رفض طلبات السائقين والتجار
--
--  دالة كانت مستخدمة في admin.astro (اعتماد/رفض) لكنها غير موجودة في
--  قاعدة البيانات أصلاً — عشان كده كل محاولة اعتماد كانت بترجع "فشل —
--  تحقق من كلمة مرور المشرف" (رسالة عامة لأي فشل، مش تشخيص حقيقي).
--
--  نفس نمط التحقق من كلمة مرور المشرف (bcrypt) زي grant_admin/
--  admin_delete_account. عند الاعتماد، بتحدّث حالة الطلب وكمان تفعّل
--  دور السائق/التاجر على الحساب نفسه (عشان لوحة السائق/التاجر تشتغل فورًا).
--
--  شغّله مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_review_application(
  p_admin_phone text, p_admin_password text,
  p_type text, p_phone text, p_status text, p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_local text;
  v_intl  text;
  v_rows  int;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_type not in ('driver', 'merchant') then
    raise exception 'invalid type: %', p_type;
  end if;

  v_local := case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2'||p_phone           else p_phone end;

  if p_type = 'driver' then
    update public.driver_applications
       set status = p_status, rejection_reason = p_reason, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'driver', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  else
    -- ملاحظة: merchant_applications مفيهوش عمود rejection_reason أصلاً (بخلاف driver_applications)
    update public.merchant_applications
       set status = p_status, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'merchant', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  end if;

  return v_rows > 0;
end;
$$;

grant execute on function public.admin_review_application(text, text, text, text, text, text) to anon, authenticated;
