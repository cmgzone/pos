# Production Admin Credentials Setup Guide

## 🔒 Changing Admin Login Credentials for Production

This guide explains how to change the default admin credentials before deploying to production.

---

## ⚠️ CRITICAL SECURITY WARNING

**NEVER use default credentials in production!**

Default credentials:
- ❌ `superadmin@velora.pos` / `superadmin123`
- ❌ Default JWT secrets
- ❌ Default license signing secrets

These **MUST** be changed before production deployment.

---

## Method 1: Environment Variables (Recommended)

### Step 1: Update Backend .env File

Edit your `backend/.env` file on your production server:

```bash
# Navigate to backend directory
cd backend

# Edit .env file (use nano, vim, or any editor)
nano .env
```

### Step 2: Set Production Credentials

```env
# Production Mode
NODE_ENV=production
PORT=3000

# Database Connection
NEON_DATABASE_URL=postgresql://USER:PASSWORD@YOUR-NEON-ENDPOINT/piki_pos?sslmode=require

# 🔒 CHANGE THESE FOR PRODUCTION 🔒
PLATFORM_ADMIN_EMAIL=admin@yourdomain.com
PLATFORM_ADMIN_PASSWORD=YourSecurePassword123!@#
PLATFORM_JWT_SECRET=your-long-random-jwt-secret-at-least-32-chars
LICENSE_SIGNING_SECRET=your-long-random-license-secret-at-least-32-chars

# CORS - Allow your admin panel domain
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com,https://app.yourdomain.com

# Required for M-Pesa callback and merchant credential security
MPESA_CALLBACK_SECRET=your-mpesa-callback-secret
PAYMENT_SECRETS_ENCRYPTION_KEY=your-random-32-byte-base64-key
```

### Step 3: Generate Strong Secrets

Use these commands to generate secure random secrets:

**On Linux/Mac:**
```bash
# Generate JWT Secret (64 characters)
openssl rand -base64 48

# Generate License Signing Secret (64 characters)
openssl rand -base64 48

# Generate M-Pesa Callback Secret (32 characters)
openssl rand -base64 24
```

**On Windows PowerShell:**
```powershell
# Generate JWT Secret
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object {[char]$_})

# Generate License Signing Secret
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object {[char]$_})

# Generate M-Pesa Callback Secret
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

**Online Generator:**
Visit: https://randomkeygen.com/ and use the "Fort Knox Passwords"

### Step 4: Restart Backend Server

After updating `.env`:

```bash
# Stop the current server (Ctrl+C or)
pm2 stop piki-backend

# Start with new environment
npm start

# Or with PM2
pm2 start npm --name "piki-backend" -- start
pm2 save
```

---

## Method 2: Docker Environment Variables

If deploying with Docker, pass environment variables:

### docker-compose.yml

```yaml
services:
  backend:
    image: piki-pos-backend
    environment:
      - NODE_ENV=production
      - PORT=3000
      - NEON_DATABASE_URL=${NEON_DATABASE_URL}
      - PLATFORM_ADMIN_EMAIL=${PLATFORM_ADMIN_EMAIL}
      - PLATFORM_ADMIN_PASSWORD=${PLATFORM_ADMIN_PASSWORD}
      - PLATFORM_JWT_SECRET=${PLATFORM_JWT_SECRET}
      - LICENSE_SIGNING_SECRET=${LICENSE_SIGNING_SECRET}
      - PLATFORM_ALLOWED_ORIGINS=${PLATFORM_ALLOWED_ORIGINS}
    ports:
      - "3000:3000"
```

### .env.production

Create a separate file for production secrets:

```env
NEON_DATABASE_URL=postgresql://...
PLATFORM_ADMIN_EMAIL=admin@yourdomain.com
PLATFORM_ADMIN_PASSWORD=YourSecurePassword123!
PLATFORM_JWT_SECRET=your-jwt-secret-here
LICENSE_SIGNING_SECRET=your-license-secret-here
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com
```

Deploy with:
```bash
docker-compose --env-file .env.production up -d
```

---

## Method 3: Cloud Platform Environment Variables

### For Coolify / Vercel / Netlify / Railway

Set environment variables in your hosting platform's dashboard:

1. **Navigate to your project settings**
2. **Find "Environment Variables" section**
3. **Add these variables:**

| Variable Name | Example Value | Description |
|--------------|---------------|-------------|
| `NODE_ENV` | `production` | Environment mode |
| `PLATFORM_ADMIN_EMAIL` | `admin@yourdomain.com` | Your admin email |
| `PLATFORM_ADMIN_PASSWORD` | `SecurePass123!` | Strong password |
| `PLATFORM_JWT_SECRET` | `long-random-string-here` | JWT signing key |
| `LICENSE_SIGNING_SECRET` | `another-random-string` | License signing key |
| `PLATFORM_ALLOWED_ORIGINS` | `https://admin.yourdomain.com` | Allowed domains |
| `NEON_DATABASE_URL` | `postgresql://...` | Database URL |

4. **Save and redeploy**

---

## Verification Steps

### 1. Check Environment Variables

Test if your backend loaded the new credentials:

```bash
# Test login with OLD credentials (should fail)
curl -X POST http://localhost:3000/api/platform/login \
  -H "Content-Type: application/json" \
  -d '{"email":"superadmin@velora.pos","password":"superadmin123"}'

# Expected: {"error":"Invalid admin credentials"}
```

```bash
# Test login with NEW credentials (should work)
curl -X POST http://localhost:3000/api/platform/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@yourdomain.com","password":"YourSecurePassword123!"}'

# Expected: {"ok":true,"token":"eyJ..."}
```

### 2. Check Production Mode

Verify the backend is running in production mode:

```bash
curl http://localhost:3000/api/health
```

Look for:
```json
{
  "status": "healthy",
  "environment": "production",
  ...
}
```

### 3. Verify CORS

The backend should reject requests from unauthorized origins in production:

```bash
# Test from unauthorized origin (should be blocked)
curl -X POST http://localhost:3000/api/platform/login \
  -H "Origin: http://unauthorized-domain.com" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@yourdomain.com","password":"YourSecurePassword123!"}'

# Expected: CORS error or 403 Forbidden
```

---

## Security Best Practices

### ✅ DO:
- Use strong passwords (min 12 characters, mixed case, numbers, symbols)
- Use randomly generated secrets (at least 32 characters)
- Store secrets in environment variables, never in code
- Use different credentials for each environment (dev/staging/prod)
- Rotate credentials regularly (every 90 days)
- Use HTTPS in production
- Enable CORS only for your domains
- Store `.env` files securely (encrypted backups)

### ❌ DON'T:
- Commit `.env` files to Git
- Share production credentials via email/chat
- Use the same password across multiple services
- Use dictionary words or predictable patterns
- Leave default credentials active
- Expose environment variables in client-side code

---

## Password Requirements

### Minimum Requirements:
- **Length:** 12+ characters
- **Uppercase:** At least 1
- **Lowercase:** At least 1
- **Numbers:** At least 1
- **Special chars:** At least 1 (!@#$%^&*)

### Good Password Examples:
- `Tr0pic@lW1nd#2026`
- `N@irobi$Sunshine99`
- `Piki!Pos#Secure2026`

### Bad Password Examples:
- ❌ `password123`
- ❌ `admin2026`
- ❌ `superadmin123` (default)

---

## Admin Panel Configuration

### Update Admin Panel Environment

If your admin panel needs to know the backend URL, configure it:

**admin-web/.env.production**
```env
VITE_API_URL=https://api.yourdomain.com
```

**admin-web/vite.config.js** (for production build)
```javascript
export default defineConfig({
  plugins: [react()],
  define: {
    'import.meta.env.VITE_API_URL': JSON.stringify(
      process.env.VITE_API_URL || 'https://api.yourdomain.com'
    )
  }
})
```

Then in your Login component, use:
```javascript
const API_URL = import.meta.env.VITE_API_URL || '';

const res = await fetch(`${API_URL}/api/platform/login`, {
  method: 'POST',
  // ...
});
```

---

## Troubleshooting

### Issue: "Invalid admin credentials" with correct password

**Solution:** Check if the backend loaded the new environment variables:

```bash
# Check backend logs
tail -f backend/backend-server.log

# Restart backend to reload .env
pm2 restart piki-backend
```

### Issue: CORS errors in production

**Solution:** Verify `PLATFORM_ALLOWED_ORIGINS` includes your admin panel domain:

```env
# Must include the EXACT origin (no trailing slash)
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com
```

### Issue: Backend won't start in production mode

**Solution:** Production mode requires all security variables to be set. Check logs:

```bash
# Backend will exit with error if required vars are missing
cat backend/backend-server.err.log
```

Required in production:
- Non-default `PLATFORM_ADMIN_PASSWORD`
- Non-default `PLATFORM_JWT_SECRET`
- Non-default `LICENSE_SIGNING_SECRET`
- Non-default `PLATFORM_ADMIN_EMAIL`
- At least one `PLATFORM_ALLOWED_ORIGINS`

---

## Deployment Checklist

Before deploying to production:

- [ ] Changed `PLATFORM_ADMIN_EMAIL` from default
- [ ] Changed `PLATFORM_ADMIN_PASSWORD` to strong password
- [ ] Generated new `PLATFORM_JWT_SECRET` (32+ chars)
- [ ] Generated new `LICENSE_SIGNING_SECRET` (32+ chars)
- [ ] Set `NODE_ENV=production`
- [ ] Configured `PLATFORM_ALLOWED_ORIGINS` with your domain
- [ ] Verified database connection string
- [ ] Tested login with new credentials
- [ ] Verified old credentials no longer work
- [ ] Enabled HTTPS
- [ ] Secured `.env` file (not in Git, encrypted backup)
- [ ] Documented credentials in password manager

---

## Emergency Access

### Lost Admin Password?

If you lose your admin password, you'll need to update it directly in the environment:

1. **SSH into your production server**
2. **Edit the .env file:**
   ```bash
   cd /path/to/backend
   nano .env
   ```
3. **Update `PLATFORM_ADMIN_PASSWORD`**
4. **Restart backend:**
   ```bash
   pm2 restart piki-backend
   ```

**Note:** There's no password reset UI. The admin credential is configured via environment variables only.

---

## Multiple Admin Users

Currently, the platform supports **one superadmin account** configured via environment variables.

### For Multiple Administrators:

**Option 1:** Share the superadmin credentials securely (use a password manager like 1Password or LastPass)

**Option 2:** Create business-level admin users (these are stored in the database and can be managed through the Flutter app's Settings > Team Access)

**Option 3:** Implement additional superadmin accounts (requires code changes to store admins in database instead of env vars)

---

## Quick Reference

### Production .env Template

```env
# Environment
NODE_ENV=production
PORT=3000

# Database
NEON_DATABASE_URL=postgresql://USER:PASSWORD@HOST/DATABASE?sslmode=require

# Admin Credentials (CHANGE THESE!)
PLATFORM_ADMIN_EMAIL=admin@yourdomain.com
PLATFORM_ADMIN_PASSWORD=YourSecurePassword123!
PLATFORM_JWT_SECRET=your-64-char-random-jwt-secret-here
LICENSE_SIGNING_SECRET=your-64-char-random-license-secret-here

# CORS
PLATFORM_ALLOWED_ORIGINS=https://admin.yourdomain.com,https://app.yourdomain.com

# Required when M-Pesa is enabled
MPESA_CALLBACK_SECRET=your-32-char-callback-secret
PAYMENT_SECRETS_ENCRYPTION_KEY=your-random-32-byte-base64-key
SERPAPI_API_KEY=your-serpapi-key-if-needed
```

### Login After Update

**URL:** https://admin.yourdomain.com

**Email:** The one you set in `PLATFORM_ADMIN_EMAIL`  
**Password:** The one you set in `PLATFORM_ADMIN_PASSWORD`

---

**Security Note:** Treat production credentials like cash. Never share them publicly, commit them to Git, or send them via insecure channels.
