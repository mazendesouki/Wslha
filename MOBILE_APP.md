# 📱 وصّلها — تطبيق الجوال (Capacitor)

الموقع متغلّف بـ **Capacitor** عشان يتنشر كتطبيق أصلي على **Google Play** و **App Store**،
وفي نفس الوقت يفضل شغّال كـ PWA على الويب من نفس الكود.

- **App ID:** `co.wslha.app`
- **App Name:** وصّلها
- **Web build dir:** `dist/` (يتولّد من `npm run build`)

---

## ⚙️ المتطلبات (مرة واحدة على جهازك)

### أندرويد
- [Android Studio](https://developer.android.com/studio) (يثبّت Android SDK + Gradle)
- JDK 17

### iOS (ماك فقط)
- Xcode من App Store
- CocoaPods: `sudo gem install cocoapods`

> ملاحظة: مينفعش تبني تطبيق iOS غير على جهاز ماك.

---

## 🚀 الأوامر السريعة

```bash
npm install            # تثبيت الحزم بعد أي clone جديد

# يبني الموقع + ينسخه للمشاريع الأصلية + يفتح الاستوديو
npm run app:android    # يفتح Android Studio
npm run app:ios        # يفتح Xcode (ماك)

# أو يدويًا:
npm run app:sync       # astro build + npx cap sync
```

**قاعدة مهمة:** أي تعديل في الموقع لازم بعده `npm run app:sync` عشان يتنقل للتطبيق.

---

## 📦 بناء ملف النشر

### Android (APK للتجربة / AAB للنشر على Play)
1. `npm run app:android`
2. في Android Studio: **Build → Generate Signed Bundle / APK**
3. اختَر **Android App Bundle (.aab)** للنشر على Google Play، أو **APK** للتجربة المباشرة.
4. اعمل/استورد مفتاح التوقيع (Keystore) — احتفظ بيه في مكان آمن، هتحتاجه لكل تحديث.

### iOS
1. `npm run app:ios`
2. في Xcode: اختَر فريق التطوير (Signing & Capabilities)
3. **Product → Archive** ثم ارفع عبر **Distribute App** إلى App Store Connect.

---

## 🔔 الإشعارات (Push)

التطبيق جاهز لاستقبال الإشعارات:
- **محلية (Local):** شغّالة فورًا — تنبيهات الطلبات والحالة.
- **Web Push (متصفح):** شغّالة فعليًا عبر `supabase/functions/send-push` (VAPID).
- **Native Push (FCM/APNs):** الكود جاهز — `src/components/layout.astro` بيسجّل
  الجهاز ويحفظ التوكن في جدول `device_tokens` (شغّل `db/security-04-device-tokens.sql`
  مرة واحدة) — لكن الإرسال الفعلي محتاج إعداد **Firebase Cloud Messaging**:
  1. أنشئ مشروع على [Firebase Console](https://console.firebase.google.com).
  2. نزّل `google-services.json` وحطه في `android/app/`.
  3. لـ iOS: نزّل `GoogleService-Info.plist` وحطه في مشروع Xcode + فعّل Push على Apple Developer.
  4. لسه محتاج توسيع `send-push` (أو دالة جديدة) عشان تبعت عبر FCM Admin SDK
     لأصحاب توكنات `device_tokens` — مش موجود حاليًا، الجدول بس اللي جاهز.

> الجسر البرمجي موجود في `src/components/layout.astro` ويتفعّل تلقائيًا داخل التطبيق فقط.

---

## 🎨 الأيقونات والـ Splash

تتولّد من سكربت واحد (بدون أدوات خارجية):

```bash
npm run icons     # يولّد أيقونات الويب + ملفات المصدر في assets/
npm run assets    # يوزّعها على كل أحجام أندرويد و iOS
```

المصدر: دبوس موقع أبيض على خلفية زرقاء البراند (`#3B6EF8`).

---

## 🗂️ بنية الملفات

```
capacitor.config.json   إعداد Capacitor (id, splash, push, status bar)
assets/                 مصادر الأيقونة/الـ splash (1024 + 2732)
scripts/gen-icons.mjs   مولّد الأيقونات بـ Node خالص
android/                مشروع أندرويد (افتحه في Android Studio)
ios/                    مشروع iOS (افتحه في Xcode على ماك)
dist/                   ناتج بناء الموقع — هو اللي بيتغلّف
```

---

## ✅ الجاهزية للنشر على المتاجر

الأيقونات والـ Splash والبناء نفسه جاهزين. الباقي محتاج حسابات حقيقية
مقدرش أعملها بدالك — دي قائمة يدوية:

- [ ] حساب [Google Play Console](https://play.google.com/console) (رسوم تسجيل لمرة واحدة).
- [ ] حساب [Apple Developer Program](https://developer.apple.com/programs/) (اشتراك سنوي، محتاج ماك للنشر).
- [ ] مشروع Firebase + `google-services.json` / `GoogleService-Info.plist` (قسم الإشعارات فوق).
- [ ] Keystore موقّع لأندرويد (يتولّد أول مرة من Android Studio) — احتفظ بيه بمكان آمن.
- [ ] صور شاشة (screenshots) للمتجرين — مقاسات Google Play وApp Store مختلفة.
- [ ] نص وصف التطبيق + كلمات مفتاحية بالعربي (وبالإنجليزي لو هتستهدف غير مصر).
- [ ] رابط سياسة الخصوصية — `privacy.astro` موجود بالفعل، تقدر تنشره وتستخدم رابطه.
- [ ] تصنيف عمري ومحتوى (Content rating) — يتم تعبيته داخل كل لوحة تحكم.

بمجرد توفر الحسابات، الخطوات في قسم "بناء ملف النشر" فوق هي المطلوبة فعليًا للرفع.

---

## 🔗 ربط البيانات الحية

التطبيق بيحمّل ملفات الموقع المبنية محليًا (أسرع + يفتح offline)،
والطلبات/المواقع الحية بتيجي مباشرة من **Supabase** عبر الإنترنت —
الـ Service Worker مظبوط إنه **ميخزّنش** بيانات Supabase أبدًا عشان تفضل لحظية.

---

## 🔔 إشعارات فورية حقيقية (FCM) لتطبيقات Flutter

هذا القسم عن `flutter_app/` (تطبيقات العميل/السائق/التاجر المنفصلة) —
مختلف عن تطبيق Capacitor فوق. الكود بالكامل جاهز
(`flutter_app/lib/core/push.dart`, `supabase/functions/send-push`,
`db/security-18-order-notify-merchant.sql`) وبيشتغل تلقائيًا بمجرد
توفير 3 حاجات محتاجة حساب Google/Firebase حقيقي — مش حاجة أقدر أعملها
بدالك:

1. **افتح مشروع Firebase الموجود بالفعل** (`wslha-941c8` — نفس المشروع
   المستخدم لتطبيق Capacitor) على https://console.firebase.google.com.
2. **أضف تطبيق أندرويد** لكل باكدج بتستخدمه (Project Settings → Add app):
   - `co.wslha.wslha_app.merchant` (الأهم — التاجر)
   - `co.wslha.wslha_app.driver` (السائق)
   - `co.wslha.wslha_app` (العميل)
   نزّل ملف `google-services.json` الناتج (بيغطي كل الباكدجات المسجّلة
   في نفس المشروع بملف واحد) وحطّه في `flutter_app/android/app/google-services.json`.
3. **ولّد مفتاح حساب خدمة**: Project Settings → Service accounts →
   Generate new private key → نزّل ملف الـ JSON.
4. **ضيفه كـ Secret في Supabase**: Edge Functions → `send-push` →
   Secrets → أضف `FCM_SERVICE_ACCOUNT_JSON` وحط فيه محتوى الملف كامل
   (الـ JSON زي ما هو، سطر واحد).
5. **شغّل** `db/security-18-order-notify-merchant.sql` مرة واحدة في
   SQL Editor (بيربط: طلب جديد → استدعاء send-push برقم صاحب المتجر).
6. **push** أي تعديل على `flutter_app/` (أو شغّل الـ workflow يدويًا من
   تبويب Actions) — الـ CI هيبني الـ APKs بدعم FCM، ثبّتهم تاني.

بمجرد كده: أي طلب جديد بيوصل فورًا كإشعار حقيقي (حتى والتطبيق مقفول)
لموبايل التاجر، ونفس الآلية جاهزة تتوسّع للسائق والعميل لاحقًا بنفس
الكود (send-push بترسل لأي رقم مسجّل توكن في `device_tokens`).
