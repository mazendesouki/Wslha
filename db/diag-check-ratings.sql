-- تشخيصي فقط (لا يغيّر أي بيانات) — يعرض آخر 10 تقييمات محفوظة في النظام،
-- وآخر رقم هاتف استُخدم كسائق في جدول الرحلات، عشان نقارن الصيغتين.

select id, driver_phone, customer_phone, rating, rated_by, service_type, created_at
from public.ratings
order by created_at desc
limit 10;

select id, driver_phone, status, created_at
from public.rides
where driver_phone is not null
order by created_at desc
limit 10;
