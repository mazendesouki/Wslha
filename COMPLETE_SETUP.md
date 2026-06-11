# Complete Deployment Checklist — وصّلها

> **All code is ready.** Follow these steps to deploy the application.

---

## ✅ PHASE 1: Firebase Setup (Local Machine)

### Step 1.1: Update `.firebaserc`
1. Open `.firebaserc` in the project root
2. Replace `wslha-production` with your actual Firebase project ID
   ```json
   {
     "projects": {
       "default": "your-firebase-project-id"
     }
   }
   ```
3. Get your project ID:
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project → Project Settings
   - Copy the "Project ID"

### Step 1.2: Create `.env` file
Create `.env` in project root with Supabase credentials:
```env
PUBLIC_SB_URL=https://your-project.supabase.co
PUBLIC_SB_KEY=your-public-anon-key
```

Get these from:
- Go to [Supabase Dashboard](https://supabase.com/dashboard)
- Select your project → Settings → API
- Copy "Project URL" and "anon public" key

### Step 1.3: Deploy to Firebase
```bash
npm run build
firebase deploy
```

**Your site will be live at:** `https://your-firebase-project-id.web.app`

---

## ✅ PHASE 2: Supabase Database Setup (Web Dashboard)

### Step 2.1: Create Tables
1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Go to **SQL Editor** (left sidebar)
4. Click **New query**
5. Copy the entire contents of `supabase-schema.sql` from the project
6. Paste into the query editor
7. Click **Run**

**Tables created:**
- ✅ `messages` — Contact form submissions
- ✅ `driver_applications` — Driver applications with documents
- ✅ `merchant_applications` — Merchant applications with documents

### Step 2.2: Create Storage Bucket
1. Go to **Storage** (left sidebar)
2. Click **New bucket**
3. Name: `documents`
4. Check **Public bucket**
5. Click **Create bucket**

### Step 2.3: Set Storage Policies
1. In **SQL Editor**, create new query
2. Paste this SQL:
```sql
INSERT INTO storage.policies (bucket_id, name, definition)
SELECT 'documents', 'Allow authenticated uploads',
  '{"bucket_id":"documents","definition":{"role":"authenticated"},"action":"INSERT"}'
WHERE NOT EXISTS (SELECT 1 FROM storage.policies WHERE bucket_id = 'documents');
```
3. Click **Run**

### Step 2.4: Create Admin Account
1. Go to **Table Editor**
2. Find the `accounts` table
3. Add a new row with:
   - `phone`: Your admin phone (e.g., `201001234567`)
   - `password`: A secure password
   - `role`: `admin`
   - `name`: Your name
   - `status`: `active`

---

## ✅ PHASE 3: Email Setup (EmailJS)

### Step 3.1: Create Email Address
Choose one option:

**Option A — Gmail (Quickest)**
1. Create a new Gmail: `info.wslha@gmail.com`
2. Enable "Less secure app access" or use an App Password

**Option B — Custom Domain (Professional)**
Use Zoho Mail, Google Workspace, or Namecheap

### Step 3.2: Set Up EmailJS
1. Go to [EmailJS](https://www.emailjs.com/)
2. Sign up for free
3. Go to **Email Services** → **Add Service**
4. Select **Gmail** (or SMTP for custom domain)
5. Connect your email account
6. Copy **Service ID** (e.g., `service_abc123`)

### Step 3.3: Create Email Templates

**Template 1 — Admin Notification**
1. Go to **Email Templates** → **Create Template**
2. **Template Name:** `Admin Notification`
3. **Subject:**
   ```
   رسالة جديدة من {{name}} — وصّلها
   ```
4. **Body:**
   ```
   رسالة جديدة من موقع وصّلها

   الاسم:    {{name}}
   الجوال:   {{phone}}
   البريد:   {{email}}
   الموضوع:  {{subject}}

   الرسالة:
   {{message}}

   ---
   تم الإرسال من موقع wslha.co
   ```
5. **To Email:** `info@wslha.co`
6. Save and copy **Template ID**

**Template 2 — Auto-Reply to User**
1. Create another template
2. **Template Name:** `User Auto-Reply`
3. **Subject:**
   ```
   تم استلام رسالتك — وصّلها
   ```
4. **Body:**
   ```
   مرحباً {{name}}،

   شكراً على تواصلك مع وصّلها!

   لقد استلمنا رسالتك بخصوص "{{subject}}" وسيتواصل معك فريقنا في أقرب وقت.

   ---
   فريق وصّلها
   info@wslha.co
   wslha.co
   ```
5. **To Email:** `{{to_email}}`
6. Save and copy **Template ID**

### Step 3.4: Get EmailJS Public Key
1. Go to **Account** → **General**
2. Copy **Public Key**

### Step 3.5: Update `.env` with EmailJS
Add to your `.env` file:
```env
PUBLIC_EMAILJS_SERVICE_ID=service_abc123
PUBLIC_EMAILJS_TEMPLATE_ID=template_notify123
PUBLIC_EMAILJS_REPLY_ID=template_reply123
PUBLIC_EMAILJS_PUBLIC_KEY=abcXYZ123
```

### Step 3.6: Rebuild and Deploy
```bash
npm run build
firebase deploy
```

---

## ✅ PHASE 4: Testing (Verify Everything Works)

### Test 1: Contact Form
1. Go to `https://your-site.web.app/contact`
2. Fill the form with real email
3. Submit
4. **Check:** `info@wslha.co` receives notification ✓
5. **Check:** Your email receives auto-reply ✓
6. **Check:** Supabase → `messages` table has the submission ✓
7. **Check:** Admin panel `/admin` shows the message ✓

### Test 2: Driver Application
1. Go to `/login` → Create account with phone
2. Go to `/driver`
3. Fill all 5 steps with test data
4. Upload documents
5. Submit
6. **Check:** Supabase → `driver_applications` has new row ✓
7. **Check:** `/admin` → **Drivers** tab shows pending application ✓
8. **Check:** Admin can view documents and approve/reject ✓

### Test 3: Merchant Application
1. Create new account with different phone
2. Go to `/merchant-apply`
3. Fill 4 steps with test data
4. Upload documents
5. Submit
6. **Check:** Supabase → `merchant_applications` has new row ✓
7. **Check:** `/admin` → **Merchants** tab shows pending application ✓

### Test 4: Admin Dashboard
1. Go to `/admin-login`
2. Log in with your admin phone + password (from Step 2.4)
3. **Check:** All sections load (Dashboard, Users, Drivers, Merchants, Orders, Rides, Stores, Messages, Finance, Settings) ✓
4. **Check:** Stats and KPIs display ✓
5. **Check:** Can view and approve pending applications ✓
6. **Check:** Can view messages and mark as read/replied ✓

### Test 5: Profile & Navigation
1. Log in as regular user at `/login`
2. Go to `/profile`
3. **Check:** Profile loads with correct data ✓
4. **Check:** Green "انضم كسائق" button appears ✓
5. **Check:** Amber "انضم كتاجر" button appears ✓
6. **Check:** Logout works correctly ✓
7. **Check:** Dropdown menu hides when not logged in ✓

### Test 6: Contact Info (Footer)
On any page, check footer "تواصل معنا" section shows:
- ✅ 📞 0020 1102 667324 (Phone)
- ✅ ✉️ info@wslha.co (Email)
- ✅ 💬 واتساب (WhatsApp)

---

## 📋 Final Deployment Checklist

- [ ] `.firebaserc` updated with Firebase project ID
- [ ] `.env` file created with Supabase credentials
- [ ] Firebase deployed and live at `.web.app` URL
- [ ] Supabase tables created (`messages`, `driver_applications`, `merchant_applications`)
- [ ] Storage bucket `documents` created
- [ ] Admin account created in `accounts` table
- [ ] EmailJS account set up
- [ ] 2 Email templates created (Admin notification + Auto-reply)
- [ ] `.env` updated with EmailJS credentials
- [ ] Email test successful (form → inbox → auto-reply)
- [ ] Driver application test successful
- [ ] Merchant application test successful
- [ ] Admin dashboard test successful
- [ ] Navigation and profile test successful
- [ ] Footer contact info displaying correctly
- [ ] All pages load without errors
- [ ] Mobile menu works on small screens

---

## 🚀 You're Done!

Your application is now fully deployed and operational:

- **Website:** https://your-firebase-project-id.web.app
- **Admin Panel:** /admin
- **Contact Form:** /contact (with working email)
- **Driver Applications:** /driver
- **Merchant Applications:** /merchant-apply
- **User Profiles:** /profile
- **Admin Messages:** /admin → Messages tab

---

## 📞 Support Resources

- **Firebase Issues:** https://console.firebase.google.com → Project → Logs
- **Supabase Issues:** https://supabase.com/dashboard → SQL Editor (check errors)
- **EmailJS Issues:** https://www.emailjs.com/ → Email Services (check logs)

---

## 🔐 Security Reminders

- ✅ `.env` is in `.gitignore` (never commit it)
- ✅ Supabase Storage is public for viewing, authenticated for uploads
- ✅ Admin login uses phone + password (no email/password)
- ✅ Row Level Security policies should be reviewed before production

For production deployments, consider:
1. Enabling RLS policies in Supabase
2. Setting up custom domain DNS
3. Configuring email whitelists
4. Setting up payment processing for orders
