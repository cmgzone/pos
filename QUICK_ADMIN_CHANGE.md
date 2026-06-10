# Quick Reference: Change Admin Credentials

## 🚀 Fast Track - Production Admin Setup

### Step 1: Edit Backend .env File
```bash
cd backend
nano .env  # or use any text editor
```

### Step 2: Update These Lines
```env
# Change these from defaults:
NODE_ENV=production
PLATFORM_ADMIN_EMAIL=admin@yourdomain.com
PLATFORM_ADMIN_PASSWORD=YourSecurePassword123!
PLATFORM_JWT_SECRET=generate-64-char-random-string-here
LICENSE_SIGNING_SECRET=generate-64-char-random-string-here
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com
```

### Step 3: Generate Random Secrets
**Windows PowerShell:**
```powershell
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object {[char]$_})
```

**Linux/Mac:**
```bash
openssl rand -base64 48
```

### Step 4: Restart Backend
```bash
npm start
# or with PM2
pm2 restart piki-backend
```

### Step 5: Test New Login
Visit: `https://admin.yourdomain.com`

**Login with:**
- Email: Your new `PLATFORM_ADMIN_EMAIL`
- Password: Your new `PLATFORM_ADMIN_PASSWORD`

---

## ⚠️ Critical Security Checklist

- [ ] Changed email from `superadmin@velora.pos`
- [ ] Changed password from `superadmin123`
- [ ] Generated new JWT secret (64+ chars)
- [ ] Generated new license secret (64+ chars)
- [ ] Set `NODE_ENV=production`
- [ ] Added your domain to `PLATFORM_ALLOWED_ORIGINS`
- [ ] Tested old credentials DON'T work
- [ ] Tested new credentials DO work
- [ ] `.env` file NOT in Git

---

## 📋 Password Requirements
- **Minimum 12 characters**
- Mixed case (Aa)
- Numbers (123)
- Special chars (!@#$)

**Good Example:** `Tr0pic@lW1nd#2026`

---

## 🆘 Lost Password?
1. SSH to server
2. Edit `backend/.env`
3. Change `PLATFORM_ADMIN_PASSWORD`
4. Restart: `pm2 restart piki-backend`

---

For detailed instructions, see: **PRODUCTION_ADMIN_SETUP.md**
