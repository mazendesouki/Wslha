# خطة الانتقال إلى Supabase Auth (هاتف + SMS OTP)

> الهدف: استبدال نظام الدخول المخصّص (`localStorage` + مفتاح `anon` للجميع)
> بمصادقة Supabase حقيقية، حتى تصبح كل الجداول قابلة للحماية بـ RLS لكل
> مستخدم — وتُغلق نهائياً ثغرات ترقية الصلاحيات والحذف/التعديل غير المصرّح.

طريقة المصادقة المختارة: **هاتف + SMS OTP حقيقي** (مزوّد مدفوع).

---

## المرحلة 0 — إعداد مزوّد SMS (مطلوب منك، مرة واحدة)

لا يعمل أي شيء قبل هذه الخطوة. في لوحة Supabase:

1. **Authentication → Providers → Phone**: فعّل "Phone".
2. اختر مزوّد SMS وأدخل بياناته:
   - **Twilio**: Account SID + Auth Token + Messaging Service SID (أو رقم مُرسِل).
   - أو **Vonage / MessageBird / Textlocal**.
   - أنشئ حساباً لدى المزوّد، فعّل المراسلة الدولية لمصر (+20)، وانسخ المفاتيح.
3. **Authentication → Providers → Phone → SMS OTP**: اضبط مدة الصلاحية (مثلاً 60 ثانية) وطول الرمز (6).
4. (موصى به) فعّل **SMS rate-limit** في Authentication → Rate Limits لمنع استنزاف رصيد SMS.
5. جرّب: من المرحلة 2 سنرسل OTP فعلياً للتأكد من وصول الرسائل.

> التكلفة: كل رسالة SMS لها سعر لدى المزوّد. فعّل حدّ معدّل صارم.

---

## المرحلة 1 — الأساس (آمن، إضافي، لا يكسر شيئاً)

- إضافة عمود ربط `auth_user_id uuid` إلى جدول `accounts` (nullable).
- إبقاء النظام القديم يعمل بالتوازي حتى اكتمال التحويل.
- تجهيز عميل Supabase مشترك بإدارة جلسة (`persistSession: true`).

## المرحلة 2 — تسجيل الدخول/التسجيل عبر Auth

- `supabase.auth.signInWithOtp({ phone })` لإرسال الرمز.
- `supabase.auth.verifyOtp({ phone, token, type: 'sms' })` للتحقق.
- عند أول دخول ناجح: إنشاء/ربط صف `accounts` بـ `auth.uid()` (عبر trigger
  `on auth.users` أو RPC ربط).
- إعادة كتابة: `login.astro`, `register.astro`, `driver.astro`,
  `merchant-apply.astro`, `admin-login.astro` لتستخدم الجلسة.
- لا يوجد كلمات مرور تُهاجَر — الدخول كله عبر OTP.

## المرحلة 3 — استبدال كل طلبات `anon` بجلسة المستخدم

- استبدال كل `fetch(SB_URL + '/rest/v1/...', { headers: SB_H })` بعميل
  Supabase المصادَق (`supabase.from(...)`)، فترسل المتصفح توكن المستخدم.
- المواضع: accounts, rides, orders, wallets, wallet_transactions,
  driver_applications, merchant_applications, stores, products,
  menu_sections, ratings, driver_locations, messages, app_settings, otps.

## المرحلة 4 — تفعيل RLS لكل جدول بسياسات حسب الدور

نموذج السياسات (مبدئي):

| الجدول | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| accounts | صاحب الصف أو admin | تسجيل ذاتي | صاحب الصف (عدا role/status) أو admin | admin فقط |
| wallets | صاحب الصف أو admin | — (RPC) | — (RPC) | admin |
| wallet_transactions | صاحب الصف أو admin | عبر RPC/الخادم | — | admin |
| rides | الراكب أو السائق المعيَّن أو admin | الراكب | الطرفان حسب الحقول | admin |
| orders | العميل أو السائق أو التاجر أو admin | العميل | حسب الدور | admin |
| driver_applications | صاحبها أو admin | صاحبها (status=pending) | admin فقط للاعتماد | admin |
| stores/products/menu_sections | الجميع قراءة | التاجر المالك أو admin | المالك أو admin | المالك أو admin |
| messages | المرسِل أو admin | الجميع | admin | admin |
| app_settings | الجميع قراءة | admin | admin | admin |

- دور admin يُحدَّد بـ claim مخصّص في الـ JWT (app_metadata.role='admin')
  أو بجدول `admins` يُفحص داخل سياسات RLS عبر دالة `is_admin()`.

## المرحلة 5 — الإزالة والتحقق النهائي

- حذف نظام `wslha_user` / `wslha_admin` القديم وكل مساراته.
- حذف `verify_otp` / جدول `otps` المخصّص (استبدلهما Auth).
- اختبار اختراق: محاولة PATCH مباشر لترقية الدور → يجب أن تُرفض بـ RLS.

---

## ملاحظات تنفيذية

- يجب أن تُختبر كل مرحلة على بيئة حيّة قبل الانتقال للتالية (مستخدمون حقيقيون).
- الترتيب إلزامي: لا تُفعّل RLS (المرحلة 4) قبل اكتمال المرحلة 3، وإلا تعطّل
  كل ما زال يستخدم مفتاح `anon`.
- النشر يتم منك (E:\Wslha) — البيئة هنا لا تستطيع الدفع (403).
