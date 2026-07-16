-- =====================================================================
--  وصّلها — العدّاد المرن للمشاوير: حسب المسافة + نوع/موديل/سنة السيارة + الوجهة
--  (نسخة موسّعة: كتالوج أوسع للسيارات + تدرّج سنوي مستمر لكل سنة على حدة)
--
--  يحدّث حارس أجرة الرحلات (guard_ride_fare من الأمان #5) ليحسب نفس معادلة
--  الواجهة على الخادم (مصدر الحقيقة النهائي — العميل لا يُعطى الثقة بالسعر):
--
--    معدّل السيارة  = سعر_الموديل × 1.2 (معامل مدينة) × معامل_السنة
--    كم متدرّج      = أول 3كم×1.15 + من 3 إلى 10كم×1.0 + ما فوق 10كم×0.9
--    السعر الخام    = (25 + كم_متدرّج × معدّل_السيارة) × معامل_الوجهة + رسم_الوجهة
--    السعر النهائي  = أقرب مضاعف 5 لأعلى، بحد أدنى 35 ج.م
--
--  معامل السنة (تدرّج مستمر لكل سنة، لا فئات ثابتة):
--    معامل(سنة) = 1 + (سنة − 2021) × 0.035 ، محصور بين 0.80 و1.35
--    يعطي كل سنة صنع قيمة مختلفة فعليًا (مثال: 2024→1.105، 2025→1.14، 2026→1.175)
--
--  ⚠️ يجب أن تبقى الأسعار والمناطق هنا مطابقة لـ VEHICLE_MODELS/FARE_ZONES في
--  src/data/airports.ts — عدّل الاثنين معاً دائماً.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) أعمدة السيارة والوجهة على جدول الرحلات
alter table public.rides add column if not exists vehicle_model text;
alter table public.rides add column if not exists vehicle_year  int;

-- 2) جدول أسعار الموديلات (المصدر الموثوق على الخادم) — كتالوج موسّع 29 موديل
create table if not exists public.vehicle_rates (
  id          text primary key,
  name        text not null,
  category    text not null,
  rate_per_km numeric not null
);

insert into public.vehicle_rates (id, name, category, rate_per_km) values
  -- سيدان اقتصادي
  ('logan',          'رينو لوجان',            'sedan', 9),
  ('sunny',          'نيسان صني',             'sedan', 9),
  ('optra',          'شيفروليه أوبترا',        'sedan', 9),
  ('peugeot301',     'بيجو 301',              'sedan', 9.5),
  ('fiattipo',       'فيات تيبو',              'sedan', 9.5),
  -- سيدان متوسط/عائلي
  ('corolla',        'تويوتا كورولا',          'sedan', 10.5),
  ('elantra',        'هيونداي إلنترا',         'sedan', 10),
  ('cerato',         'كيا سيراتو',             'sedan', 10),
  ('mg5',            'إم جي 5',               'sedan', 10),
  ('octavia',        'سكودا أوكتافيا',         'sedan', 11),
  -- سيدان فاخر
  ('bmw3',           'بي إم دبليو الفئة 3',    'sedan', 19),
  ('mercc',          'مرسيدس الفئة C',         'sedan', 20),
  -- SUV مدمج/كروس أوفر
  ('mgzs',           'إم جي ZS',              'suv',   12),
  ('creta',          'هيونداي كريتا',          'suv',   12.5),
  ('tucson',         'هيونداي توسان',          'suv',   13),
  ('sportage',       'كيا سبورتاج',            'suv',   13),
  -- SUV متوسط/كبير
  ('xtrail',         'نيسان إكس تريل',         'suv',   13.5),
  ('tiggo8',         'شيري تيجو 8',            'suv',   14),
  ('compass',        'جيب كومباس',             'suv',   14.5),
  -- SUV فل سايز/فاخر
  ('landcruiser',    'تويوتا لاند كروزر',      'suv',   16),
  ('patrol',         'نيسان باترول',           'suv',   15.5),
  ('pajero',         'ميتسوبيشي باجيرو',        'suv',   15.5),
  ('grandcherokee',  'جيب جراند شيروكي',       'suv',   19),
  -- فان / ميكروباص
  ('xpander',        'ميتسوبيشي إكسباندر',      'van',   12.5),
  ('hiace',          'تويوتا هاي إيس',          'van',   13.5),
  ('h1',             'هيونداي H1',            'van',   14),
  ('carnival',       'كيا كارنيفال',           'van',   15),
  ('traveller',      'بيجو ترافيلر',           'van',   16),
  ('sprinter',       'مرسيدس سبرينتر',         'van',   16)
on conflict (id) do update set
  name = excluded.name, category = excluded.category, rate_per_km = excluded.rate_per_km;

-- الموديلات القديمة المُستبدلة (إن وُجدت من نسخة سابقة) تبقى في الجدول لعدم كسر
-- رحلات سابقة مرتبطة بها — لا داعي لحذفها.

-- 3) جدول مناطق الوجهة (رسوم/معامل إضافي حسب بُعد أو طبيعة الوجهة)
create table if not exists public.fare_zones (
  id        text primary key,
  label     text not null,
  factor    numeric not null default 1,
  surcharge numeric not null default 0,
  keywords  text[] not null default '{}'
);

insert into public.fare_zones (id, label, factor, surcharge, keywords) values
  ('rasbar',     'رأس البر (مصيف)',          1.15, 10, array['رأس البر', 'راس البر']),
  ('remote',     'أطراف المحافظة',            1.10, 15, array['فارسكور', 'الزرقا', 'كفر البطيخ', 'الروضة', 'كفر سعد', 'ميت أبو غالب', 'عزبة البرج', 'الرحامنة', 'السرو']),
  ('industrial', 'المنطقة الصناعية والميناء', 1.05, 10, array['الصناعية', 'ميناء', 'الميناء', 'شطا'])
on conflict (id) do update set
  label = excluded.label, factor = excluded.factor, surcharge = excluded.surcharge, keywords = excluded.keywords;

-- القراءة فقط للجميع؛ التعديل عبر لوحة Supabase أو دوال المشرف فقط
grant select on public.vehicle_rates, public.fare_zones to anon, authenticated;
revoke insert, update, delete on public.vehicle_rates, public.fare_zones from anon, authenticated;

-- 4) تحديث حارس الأجرة — العدّاد المرن الكامل (تدرّج سنوي مستمر)
create or replace function public.guard_ride_fare()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rate     numeric;
  v_mult     numeric;
  v_effrate  numeric;
  v_km       numeric;
  v_tiered   numeric;
  v_zone     record;
  v_raw      numeric;
begin
  if new.ride_type is null or new.ride_type = 'local' then
    select rate_per_km into v_rate from public.vehicle_rates where id = new.vehicle_model;
    if v_rate is null then
      v_rate := 10; -- موديل غير معروف → سعر السيدان القياسي
    end if;

    -- معامل السنة: تدرّج مستمر لكل سنة (يطابق yearMultiplier في airports.ts)
    v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));
    v_effrate := v_rate * 1.2 * v_mult;

    v_km := coalesce(new.distance_km, 0);
    v_tiered := least(v_km, 3) * 1.15
              + least(greatest(v_km - 3, 0), 7) * 1.0
              + greatest(v_km - 10, 0) * 0.9;

    select * into v_zone from public.fare_zones z
     where new.to_area is not null and exists (
       select 1 from unnest(z.keywords) k where new.to_area ilike '%' || k || '%'
     )
     limit 1;

    v_raw := (25 + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0);
    new.fare := ceil(greatest(v_raw, 35) / 5) * 5;
  end if;
  -- ride_type='airport': تسعير مركّب (موديل + سنة + شنط + مرافقين + انتظار)
  -- يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;

drop trigger if exists trg_guard_ride_fare on public.rides;
create trigger trg_guard_ride_fare
  before insert on public.rides
  for each row execute function public.guard_ride_fare();
