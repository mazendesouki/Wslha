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
- **Push (من سيرفر):** محتاجة إعداد **Firebase Cloud Messaging**:
  1. أنشئ مشروع على [Firebase Console](https://console.firebase.google.com).
  2. نزّل `google-services.json` وحطه في `android/app/`.
  3. لـ iOS: نزّل `GoogleService-Info.plist` وحطه في مشروع Xcode + فعّل Push على Apple Developer.

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

## 🔗 ربط البيانات الحية

التطبيق بيحمّل ملفات الموقع المبنية محليًا (أسرع + يفتح offline)،
والطلبات/المواقع الحية بتيجي مباشرة من **Supabase** عبر الإنترنت —
الـ Service Worker مظبوط إنه **ميخزّنش** بيانات Supabase أبدًا عشان تفضل لحظية.
