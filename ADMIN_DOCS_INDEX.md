# Admin Panel Documentation Index

## 📚 Complete Documentation Suite

All documentation has been deployed to GitHub: https://github.com/cmgzone/pos.git

---

## 🎯 Quick Start

**Need to change admin password?** → Read `QUICK_ADMIN_CHANGE.md`

**Admin panel not working?** → Read `ADMIN_PANEL_FIXED.md`

**Deploying to production?** → Read `PRODUCTION_ADMIN_SETUP.md`

---

## 📖 Documentation Files

### 1. **QUICK_ADMIN_CHANGE.md** ⚡
**Quick reference card for changing admin credentials**
- Fast 5-step process
- Password generation commands
- Security checklist
- Emergency access

**When to use:** Need to quickly change admin password for production

---

### 2. **PRODUCTION_ADMIN_SETUP.md** 📋
**Comprehensive production deployment guide**
- Environment variable configuration
- Multiple deployment methods (Docker, Cloud, etc.)
- Security best practices
- Password requirements
- Troubleshooting guide
- Full deployment checklist

**When to use:** Preparing for production deployment or need detailed security guidance

---

### 3. **ADMIN_PANEL_FIXED.md** 🔧
**Troubleshooting guide for admin panel login issues**
- JSON parsing error resolution
- Server setup and configuration
- Architecture overview
- Common issues and solutions
- Access verification steps

**When to use:** Admin panel login is not working or showing errors

---

### 4. **DEPLOYMENT_SUMMARY.md** 📊
**Deployment status and commit history**
- Recent deployments
- Files added/changed
- Commit messages
- Current status

**When to use:** Track what has been deployed to GitHub

---

## 🚀 Common Tasks

### Change Admin Password for Production

1. **Quick method:** Follow `QUICK_ADMIN_CHANGE.md`
2. **Detailed method:** Read `PRODUCTION_ADMIN_SETUP.md` → "Method 1: Environment Variables"

### Fix Admin Panel Login Error

1. Read `ADMIN_PANEL_FIXED.md`
2. Check both backend and admin panel are running
3. Verify backend on port 3000, admin panel on port 4000

### Deploy to Production

1. Read `PRODUCTION_ADMIN_SETUP.md` completely
2. Complete the deployment checklist
3. Verify all security settings
4. Test login with new credentials

---

## 🔐 Default Credentials (Development Only)

**⚠️ NEVER USE IN PRODUCTION!**

- **Email:** `superadmin@velora.pos`
- **Password:** `superadmin123`
- **Admin Panel URL:** http://localhost:4000

**Before production:** Follow `QUICK_ADMIN_CHANGE.md` or `PRODUCTION_ADMIN_SETUP.md`

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────┐
│  Browser                                │
│  http://localhost:4000 (dev)            │
│  https://admin.yourdomain.com (prod)    │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Admin Panel (Vite + React)             │
│  Port: 4000 (dev)                       │
│  - Login UI                             │
│  - Dashboard                            │
│  - Proxies /api → backend               │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Backend Server (Express + Node.js)     │
│  Port: 3000                             │
│  - /api/platform/login endpoint         │
│  - JWT authentication                   │
│  - Admin credentials from .env          │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Neon PostgreSQL Database               │
│  - Business data                        │
│  - Subscriptions                        │
│  - Users                                │
└─────────────────────────────────────────┘
```

---

## 🔧 Configuration Files

### Backend Configuration
**File:** `backend/.env`
```env
NODE_ENV=production
PORT=3000
NEON_DATABASE_URL=postgresql://...
PLATFORM_ADMIN_EMAIL=admin@yourdomain.com
PLATFORM_ADMIN_PASSWORD=YourSecurePassword
PLATFORM_JWT_SECRET=your-jwt-secret
LICENSE_SIGNING_SECRET=your-license-secret
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com
```

### Admin Panel Configuration
**File:** `admin-web/vite.config.js`
```javascript
export default defineConfig({
  plugins: [react()],
  server: {
    port: 4000,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
    },
  },
})
```

---

## 🆘 Troubleshooting

### Issue: Can't login to admin panel
→ Read `ADMIN_PANEL_FIXED.md`

### Issue: Need to change password
→ Read `QUICK_ADMIN_CHANGE.md`

### Issue: Preparing for production
→ Read `PRODUCTION_ADMIN_SETUP.md`

### Issue: CORS errors
→ Check `PLATFORM_ALLOWED_ORIGINS` in `backend/.env`

### Issue: Lost admin password
→ Edit `backend/.env` → Update `PLATFORM_ADMIN_PASSWORD` → Restart backend

---

## 📝 Security Checklist

Before production deployment:

- [ ] Changed `PLATFORM_ADMIN_EMAIL` from default
- [ ] Changed `PLATFORM_ADMIN_PASSWORD` to strong password (12+ chars)
- [ ] Generated new `PLATFORM_JWT_SECRET` (64+ chars)
- [ ] Generated new `LICENSE_SIGNING_SECRET` (64+ chars)
- [ ] Set `NODE_ENV=production`
- [ ] Configured `PLATFORM_ALLOWED_ORIGINS`
- [ ] Enabled HTTPS
- [ ] `.env` file not in Git
- [ ] Tested new credentials work
- [ ] Verified old credentials don't work

---

## 🔗 Quick Links

- **GitHub Repository:** https://github.com/cmgzone/pos.git
- **Development Admin Panel:** http://localhost:4000
- **Backend API:** http://localhost:3000

---

## 📞 Support

For additional help:
1. Check the specific documentation file for your issue
2. Review troubleshooting sections
3. Check backend logs: `backend/backend-server.log`
4. Check error logs: `backend/backend-server.err.log`

---

**Last Updated:** June 10, 2026  
**Documentation Version:** 1.0  
**All docs deployed to GitHub** ✅
