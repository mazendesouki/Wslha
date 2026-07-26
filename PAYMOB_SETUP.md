# 💳 وصّلها — إعداد بوابة الدفع (Paymob)

الدفع الإلكتروني للمحفظة بيشتغل عبر **Paymob** (فيزا/ماستركارد، فودافون كاش، فوري)
من خلال دالتين على Supabase Edge Functions:

- `supabase/functions/paymob-create-intention` — بتفتح عملية دفع جديدة.
- `supabase/functions/paymob-webhook` — بتستقبل تأكيد الدفع من Paymob وتشحن المحفظة.

مفيش أي مفتاح سري في كود العميل (المتصفح/التطبيق) — كل المفاتيح أسرار على السيرفر فقط.

---

## 1) مفاتيح Paymob المطلوبة

من [لوحة تحكم Paymob](https://accept.paymob.com) → **Developers → API Keys**:

| المتغيّر | من فين | ملاحظة |
|---|---|---|
| `PAYMOB_SECRET_KEY` | Secret Key | يُستخدم في نداء Intention API من السيرفر فقط |
| `PAYMOB_PUBLIC_KEY` | Public Key | يُضاف في رابط صفحة الدفع (آمن أنه يظهر للعميل) |
| `PAYMOB_HMAC_SECRET` | HMAC Secret | للتحقق من صحة كل Webhook قادم من Paymob |

من **Developers → Payment Integrations** (اعمل تكامل واحد على الأقل، وممكن أكتر من نوع):

| المتغيّر | التكامل |
|---|---|
| `PAYMOB_INTEGRATION_ID_CARD` | بطاقة فيزا/ماستركارد |
| `PAYMOB_INTEGRATION_ID_WALLET` | محفظة موبايل (فودافون كاش) |
| `PAYMOB_INTEGRATION_ID_FAWRY` | فوري (كاش) |

> مش لازم تضيف الثلاثة — أي واحد أو أكتر موجود، صفحة الدفع الموحّدة من Paymob
> هتعرض للعميل خيارات الدفع المتاحة بناءً على اللي مضبوط بس.

---

## 2) ضبط الأسرار على Supabase

```bash
supabase secrets set \
  PAYMOB_SECRET_KEY=xxxxx \
  PAYMOB_PUBLIC_KEY=xxxxx \
  PAYMOB_HMAC_SECRET=xxxxx \
  PAYMOB_INTEGRATION_ID_CARD=12345 \
  PAYMOB_INTEGRATION_ID_WALLET=12346 \
  PAYMOB_INTEGRATION_ID_FAWRY=12347

supabase functions deploy paymob-create-intention --no-verify-jwt
supabase functions deploy paymob-webhook --no-verify-jwt
```

---

## 3) ربط الـ Webhook في لوحة Paymob

في **Developers → Payment Integrations** (لكل تكامل) أو **Webhooks** (حسب نسخة اللوحة)،
اضبط رابط **Transaction Processed Callback** على:

```
https://<project-ref>.supabase.co/functions/v1/paymob-webhook
```

---

## 4) الاختبار

Paymob بيوفّر بيئة **Test/Sandbox** ببطاقات وهمية جاهزة لتجربة الدفع كامل من غير فلوس حقيقية —
استخدمها الأول قبل أي مفاتيح حقيقية (Live Keys).

خطوات التجربة:
1. من صفحة المحفظة `wallet.astro` → إيداع → **ادفع الآن أونلاين**.
2. تأكد إن صف جديد اتسجّل في `wallet_requests` بحالة `pending`.
3. أكمل الدفع التجريبي في صفحة Paymob.
4. تأكد إن `wallet_requests.status` بقى `done` وإن `wallets.balance` زاد بنفس القيمة.
5. جرّب إرسال Webhook مزوّر (بدون HMAC صحيح) بـ `curl` وتأكد إنه بيترفض بـ 403.

> **ملاحظة:** ترتيب الحقول المستخدم في حساب الـ HMAC داخل `paymob-webhook/index.ts`
> مبني على توثيق Paymob الرسمي — لازم يتأكد منه على بيانات حقيقية من الـ Sandbox
> قبل التفعيل الفعلي، لأن Paymob غيّرت شكل الـ payload أكتر من مرة بين نسخ الـ API.
