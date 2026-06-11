# Email Setup Guide — وصّلها

## How it works

Every contact form submission does **3 things**:
1. Saves the message to Supabase (`messages` table) — permanent record
2. Sends a notification email to `info@wslha.co` — admin sees new message
3. Sends an auto-reply to the user — if they provided their email

---

## Step 1: Create the email account

### Option A — Gmail (free, quick setup)
1. Go to https://accounts.google.com/signup
2. Create: `info.wslha@gmail.com` (or similar)
3. Use this as your receiving address

### Option B — Custom domain (professional, recommended)
Get `info@wslha.co` via one of:
- **Zoho Mail** — free for 1 user: https://www.zoho.com/mail/
- **Google Workspace** — $6/month: https://workspace.google.com/
- **Namecheap Private Email** — $1/month: https://www.namecheap.com/hosting/email/

---

## Step 2: Set up EmailJS (free — 200 emails/month)

### 2a. Create account
1. Go to https://www.emailjs.com/
2. Sign up for free
3. Go to **Email Services** → **Add New Service**
4. Choose **Gmail** (or your custom domain via SMTP)
5. Connect your email account
6. Copy the **Service ID** (e.g. `service_abc123`)

### 2b. Create Template 1 — Admin Notification
1. Go to **Email Templates** → **Create New Template**
2. Use this template:

**Subject:**
```
رسالة جديدة من {{name}} — وصّلها
```

**Body:**
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

3. Set **To Email** field to: `info@wslha.co`
4. Save and copy the **Template ID** (e.g. `template_notify123`)

### 2c. Create Template 2 — Auto-Reply to User
1. Create another template
2. Use this template:

**Subject:**
```
تم استلام رسالتك — وصّلها
```

**Body:**
```
مرحباً {{name}}،

شكراً على تواصلك مع وصّلها!

لقد استلمنا رسالتك بخصوص "{{subject}}" وسيتواصل معك فريقنا في أقرب وقت.

---
فريق وصّلها
info@wslha.co
wslha.co
```

3. Set **To Email** field to: `{{to_email}}`
4. Save and copy the **Template ID** (e.g. `template_reply123`)

### 2d. Get your Public Key
1. Go to **Account** → **General**
2. Copy your **Public Key** (e.g. `abcXYZ123`)

---

## Step 3: Add environment variables

Create a `.env` file in the project root (if it doesn't exist):

```env
# Supabase
PUBLIC_SB_URL=https://your-project.supabase.co
PUBLIC_SB_KEY=your-public-anon-key

# EmailJS
PUBLIC_EMAILJS_SERVICE_ID=service_abc123
PUBLIC_EMAILJS_TEMPLATE_ID=template_notify123
PUBLIC_EMAILJS_REPLY_ID=template_reply123
PUBLIC_EMAILJS_PUBLIC_KEY=abcXYZ123
```

> ⚠️ Never commit `.env` to git — it's already in `.gitignore`

---

## Step 4: Add Supabase `messages` table

Run this SQL in **Supabase → SQL Editor**:

```sql
CREATE TABLE IF NOT EXISTS messages (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL,
  email      TEXT,
  subject    TEXT NOT NULL,
  message    TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'unread',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

## Step 5: Set Firebase environment variables (for production)

In Firebase Hosting, env variables from `.env` don't work automatically.
You need to set them during build in your CI/CD pipeline, or use a workaround.

### Option A — Build locally then deploy
```bash
# Set env vars in your .env file, then:
npm run build
firebase deploy
```

### Option B — GitHub Actions secret (if using CI/CD)
Add all `PUBLIC_*` vars as GitHub Secrets, then inject during build:
```yaml
- name: Build
  env:
    PUBLIC_EMAILJS_PUBLIC_KEY: ${{ secrets.EMAILJS_PUBLIC_KEY }}
    # ... other vars
  run: npm run build
```

---

## Step 6: Test the form

1. Go to `/contact` on your deployed site
2. Fill the form with a real email
3. Submit
4. Check: `info@wslha.co` inbox — should receive notification
5. Check: your email — should receive auto-reply
6. Check: Supabase → Table Editor → `messages` — should see the row
7. Check: Admin Panel (`/admin`) → Messages section

---

## Monitoring messages

All messages are visible in the **Admin Panel** at `/admin`.
The admin can:
- View all messages (unread shown first)
- Mark as read / replied
- See full message details

---

## Free tier limits

| Service | Free Limit |
|---------|-----------|
| EmailJS | 200 emails/month |
| Supabase | 500MB storage, 2GB bandwidth |
| Firebase Hosting | 10GB/month bandwidth |

For higher volume, upgrade EmailJS to $15/month (1,000 emails).
