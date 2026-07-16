# محرك التوزيع — Dispatch Engine

سيرفر Node.js صغير مستقل، بيشتغل جنب Supabase مش بديل عنه. مسؤوليته
الوحيدة: لما تتجهز رحلة أو طلب توصيل جديد، يدوّر على أقرب سائق متصل
ومتاح ويعرضه عليه لوحده (بإشعار مستهدف)، وله 30 ثانية يرد. لو رفض أو
معملش حاجة، يتحول تلقائياً لأقرب سائق تاني، وهكذا.

لو السيرفر ده مش شغال (أو معدّاش على كل السائقين القريبين)، شاشة
السائق فيها نظام بثّ احتياطي قديم بيشتغل تلقائياً بعد مهلة — التطبيق
مايتوقفش لو السيرفر ده وقع.

## التشغيل محلياً

```bash
cd server
npm install
cp .env.example .env   # املأ القيم
npm start
```

## المتغيرات المطلوبة

| المتغير | منين تجيبه |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard → Project Settings → API → `service_role` (سري جداً — متحطهوش في الفرونت إند أبداً) |
| `PUSH_TRIGGER_SECRET` | نفس القيمة اللي مضبوطة كـ secret على edge function اسمها `send-push` |

## النشر على Render (مجاني)

1. اعمل حساب على [render.com](https://render.com) واربطه بحساب GitHub بتاعك.
2. **New → Web Service** → اختار الريبو `mazendesouki/wslha`.
3. **Root Directory**: `server`
4. **Build Command**: `npm install`
5. **Start Command**: `npm start`
6. **Instance Type**: Free
7. ضيف الـ Environment Variables اللي في `.env.example` أعلاه (بالقيم الحقيقية).
8. Deploy.

### مهم — منع السيرفر من "النوم"

الخطة المجانية في Render بتوقف أي خدمة بعد 15 دقيقة من غير طلبات HTTP،
وده هيقطع اتصال الـ Realtime بتاع محرك التوزيع. عشان تمنع ده:

- اعمل حساب مجاني على [cron-job.org](https://cron-job.org) (أو أي خدمة مشابهة).
- اضبط مهمة تعمل GET على `https://<اسم-الخدمة>.onrender.com/health` كل 10 دقايق.

ده هيخلي السيرفر صاحي طول الوقت.

## SQL مطلوب قبل التشغيل

شغّل `dispatch-engine-schema.sql` (المرفق في المشروع) في Supabase SQL
Editor قبل ما تشغّل السيرفر ده — بيضيف جدول `dispatch_offers` والدوال
اللي شاشة السائق بتستخدمها عشان تستقبل العروض المستهدفة.
