# Deployment Guide — وصّلها

## Prerequisites
- Firebase account with a project
- Supabase project set up
- Node.js 18+ and npm installed
- Firebase CLI: `npm install -g firebase-tools`

---

## 1. Firebase Deployment

### Step 1: Authenticate with Firebase
```bash
firebase login
```

### Step 2: Update .firebaserc
Replace `wslha-production` with your actual Firebase project ID:
```bash
firebase projects:list  # Find your project ID
# Then edit .firebaserc
```

### Step 3: Deploy
```bash
npm run build
firebase deploy
```

**Output:** Your site will be live at `https://<project-id>.web.app`

---

## 2. Supabase Setup

### Step 1: Create Database Tables
1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Go to **SQL Editor**
4. Copy the entire contents of `supabase-schema.sql`
5. Paste into the SQL editor and run

**Tables created:**
- `driver_applications` — Driver application submissions
- `merchant_applications` — Merchant application submissions

### Step 2: Create Storage Bucket
1. Go to **Storage** in Supabase dashboard
2. Click **New bucket**
3. Name it: `documents`
4. Set to **Public**
5. Click **Create bucket**

### Step 3: Set Storage Policies
Run this SQL in **SQL Editor**:
```sql
INSERT INTO storage.policies (bucket_id, name, definition)
SELECT 'documents', 'Allow authenticated uploads',
  '{"bucket_id":"documents","definition":{"role":"authenticated"},"action":"INSERT"}'
WHERE NOT EXISTS (SELECT 1 FROM storage.policies WHERE bucket_id = 'documents');
```

---

## 3. Environment Variables

Ensure `.env` contains (or create if missing):
```env
PUBLIC_SB_URL=https://<your-project>.supabase.co
PUBLIC_SB_KEY=<your-public-anon-key>
```

Find these in Supabase → **Project Settings** → **API**

---

## 4. Test the Full Flow

### Test Driver Application:
1. Go to `/driver`
2. Log in with a test phone number
3. Fill all fields and upload documents
4. Verify submission succeeds
5. Check Supabase: `driver_applications` table should have new row

### Test Merchant Application:
1. Go to `/merchant-apply`
2. Log in with different phone number
3. Fill all fields and upload documents
4. Verify submission succeeds
5. Check Supabase: `merchant_applications` table should have new row

### Test Admin Dashboard:
1. Go to `/admin-login`
2. Log in with admin phone (must have `role: 'admin'` in accounts table)
3. Navigate to **Drivers** tab
4. You should see pending applications with document previews
5. Test approve/reject workflow

---

## 5. Post-Deployment Checklist

- [ ] Firebase site loads without errors
- [ ] All pages render correctly
- [ ] Driver application form works end-to-end
- [ ] Merchant application form works end-to-end
- [ ] Documents upload to Supabase Storage
- [ ] Admin can view and approve applications
- [ ] Role-based navigation works (driver/merchant buttons hide correctly)
- [ ] Profile page loads user data
- [ ] Orders and rides pages function
- [ ] Mobile menu works on small screens

---

## 6. Troubleshooting

### Build fails
```bash
npm run build  # Check error details
npm install   # Reinstall dependencies
```

### Firebase deploy fails
- Ensure `.firebaserc` has correct project ID
- Run `firebase init hosting` to reconfigure
- Check Firebase project has billing enabled

### Supabase database issues
- Verify tables created: Go to **Table Editor** in dashboard
- Check RLS policies if uploads fail: Storage → documents → Policies
- Test API key permissions in **Project Settings** → **API**

### Application uploads not working
- Ensure `PUBLIC_SB_URL` and `PUBLIC_SB_KEY` are set
- Verify `documents` bucket exists and is public
- Check browser console for network errors

---

## Current Stack

| Component | Technology |
|-----------|-----------|
| Frontend | Astro 4 + TypeScript |
| UI Framework | Preact 3 |
| Hosting | Firebase Hosting |
| Database | Supabase (PostgreSQL) |
| Storage | Supabase Storage |
| Mobile | Capacitor (iOS/Android wrapper) |

---

## Contact & Support

For production issues:
- Check Supabase dashboard for database errors
- Check Firebase dashboard for hosting errors
- Review browser console for client-side errors
- Check git log for recent changes: `git log --oneline -10`
