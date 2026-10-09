-- =====================================================================
--  وصّلها — Security #125: bucket خاص لمستندات الهوية (future uploads)
--
--  bucket "documents" كان public=true ومشترك بين: مستندات هوية حساسة
--  (رقم قومي/رخصة/فيش جنائية) + صورة السائق الشخصية + صور المركبة/
--  اللوحة. أي حد بالـ anon key يقدر يفتح/يحمّل أي ملف فيه مباشرة لو
--  عرف الـ path (والمسار نفسه predictable: driver-apps/<phone>/<نوع>-
--  <timestamp>.<ext>).
--
--  النطاق هنا (بقرار واعي): bucket خاص جديد "driver-docs" للمستندات
--  الرسمية الحساسة بس (رقم قومي/رخصة/تسجيل مركبة/تأمين/فحص/فيش جنائية،
--  وكل مستندات التاجر). صورة السائق الشخصية (driver_photo_url) وصور
--  المركبة/اللوحة فضلوا على bucket "documents" العام القديم عمدًا —
--  دول بيتعرضوا فعليًا للعميل في شاشة تتبّع الرحلة (get_approved_driver_badge)
--  فمحتاجين يفضلوا قابلين للعرض المباشر من غير تعقيد signed URL لكل
--  عميل بيشوف صورة سائقه.
--
--  ده بيأمّن الرفعات الجديدة بس — المستندات القديمة المرفوعة فعليًا
--  تحت bucket "documents" العام تفضل زي ما هي (نقلها محتاج هجرة ملفات
--  فعلية، مش مجرد SQL، وده قرار منفصل لو اتقرر لاحقًا).
--
--  القراءة: مفيش أي policy لـ anon/authenticated على bucket ده خالص —
--  المراجعة من لوحة الأدمن بتعدي عن طريق signed URL يتولّد سيرفر-سايد
--  (src/pages/api/admin/sign-document.ts) باستخدام service role key،
--  بعد التحقق من كلمة مرور الأدمن عن طريق admin_verify_password.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into storage.buckets (id, name, public) values ('driver-docs', 'driver-docs', false)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'anon upload driver-docs'
  ) then
    create policy "anon upload driver-docs" on storage.objects
    for insert to anon, authenticated
    with check (bucket_id = 'driver-docs');
  end if;
end $$;

-- دالة عامة للتحقق من كلمة مرور الأدمن — نفس المنطق المكرر في كل دالة
-- admin_* تقريبًا، لكن هنا كدالة مستقلة لاستخدامها من الـ API route
-- (مش RPC بيغيّر بيانات، بس بيتحقق ويرجّع true/false).
create or replace function public.admin_verify_password(p_admin_phone text, p_admin_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  return v_admin.password is not null and v_admin.password = extensions.crypt(p_admin_password, v_admin.password);
end;
$$;
grant execute on function public.admin_verify_password(text, text) to anon, authenticated;
