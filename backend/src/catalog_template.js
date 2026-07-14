function renderPublicCatalogPage(catalog) {
  const businessName = catalog.business.name || 'Catalog';
  const productCount = catalog.products.length;
  const branchName = catalog.business.selectedBranch?.name || 'Main store';
  const storeInitial = businessName.trim().charAt(0).toUpperCase() || 'P';
  const brand = catalog.business.brand || {};
  const primaryColor = normalizeStorefrontColor(brand.primaryColor, {
    fallback: '#000000',
    throwOnInvalid: false,
  });
  const logoUrl = safePublicImageUrl(brand.logoUrl);
  const coverUrl = safePublicImageUrl(brand.coverUrl);
  const tagline = normalizeOptionalText(brand.tagline) || 'Online catalog';
  const description =
    normalizeOptionalText(brand.description) ||
    'Shop products and services, choose variants, and send your order directly to the store.';
  const safeCatalogJson = JSON.stringify(catalog).replace(/</g, '\\u003c');
  const whatsappNumber = normalizePublicPhone(catalog.business.whatsappNumber || '');

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />
  <title>\${escapeHtml(businessName)} - Store</title>
  <meta name="description" content="\${escapeHtml(description)}" />
  <meta property="og:title" content="\${escapeHtml(businessName)}" />
  <meta property="og:description" content="\${escapeHtml(description)}" />
  \${coverUrl ? \`<meta property="og:image" content="\${escapeHtml(coverUrl)}" />\` : ''}
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #f7f9fa;
      --surface: #ffffff;
      --ink: #111827;
      --muted: #6b7280;
      --line: #e5e7eb;
      --primary: \${escapeHtml(primaryColor)};
      --success: #059669;
      --danger: #dc2626;
      --radius-sm: 8px;
      --radius-md: 12px;
      --radius-lg: 20px;
      --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
      --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
      --shadow-lg: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
      --shadow-floating: 0 24px 50px -12px rgba(0,0,0,0.25);
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      -webkit-font-smoothing: antialiased;
      padding-bottom: 80px;
    }
    
    /* Navbar */
    .navbar {
      position: sticky;
      top: 0;
      z-index: 40;
      background: rgba(255, 255, 255, 0.85);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--line);
      padding: 12px 0;
    }
    .wrap {
      width: min(1200px, 100% - 32px);
      margin: 0 auto;
    }
    .nav-inner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .brand-lockup {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: var(--ink);
      font-weight: 800;
      font-size: 20px;
      letter-spacing: -0.02em;
    }
    .logo-mark {
      width: 40px;
      height: 40px;
      border-radius: var(--radius-sm);
      overflow: hidden;
      background: var(--primary);
      color: #fff;
      display: grid;
      place-items: center;
      font-size: 18px;
    }
    .logo-mark img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .nav-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .cart-btn-top {
      background: var(--ink);
      color: #fff;
      border: none;
      padding: 10px 16px;
      border-radius: 999px;
      font-weight: 600;
      font-size: 14px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
      transition: opacity 0.2s;
    }
    .cart-btn-top:hover { opacity: 0.9; }
    .cart-badge {
      background: var(--primary);
      color: #fff;
      min-width: 20px;
      height: 20px;
      border-radius: 10px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
      font-weight: 800;
      padding: 0 6px;
    }

    /* Hero */
    .hero {
      position: relative;
      background: \${coverUrl ? \`url('\${escapeHtml(coverUrl)}')\` : 'linear-gradient(135deg, var(--ink), #374151)'};
      background-size: cover;
      background-position: center;
      min-height: 380px;
      display: flex;
      align-items: flex-end;
      padding: 60px 0 40px;
    }
    .hero::before {
      content: '';
      position: absolute;
      inset: 0;
      background: linear-gradient(to top, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.3) 50%, rgba(0,0,0,0.1) 100%);
    }
    .hero-content {
      position: relative;
      z-index: 10;
      color: #fff;
      max-width: 800px;
    }
    .hero-title {
      font-size: clamp(36px, 6vw, 64px);
      font-weight: 800;
      margin: 0 0 12px 0;
      line-height: 1.1;
      letter-spacing: -0.03em;
    }
    .hero-subtitle {
      font-size: clamp(16px, 2vw, 20px);
      color: rgba(255,255,255,0.85);
      margin: 0 0 24px 0;
      line-height: 1.5;
    }
    .search-bar {
      position: relative;
      max-width: 500px;
      margin-top: 24px;
    }
    .search-bar input {
      width: 100%;
      background: rgba(255,255,255,0.95);
      border: 2px solid transparent;
      padding: 16px 20px 16px 48px;
      border-radius: 999px;
      font-size: 16px;
      outline: none;
      box-shadow: var(--shadow-lg);
      transition: all 0.2s;
    }
    .search-bar input:focus {
      background: #fff;
      border-color: var(--primary);
    }
    .search-icon {
      position: absolute;
      left: 18px;
      top: 50%;
      transform: translateY(-50%);
      width: 20px;
      height: 20px;
      opacity: 0.5;
    }

    /* Categories */
    .categories-wrap {
      padding: 24px 0;
      background: var(--surface);
      border-bottom: 1px solid var(--line);
      position: sticky;
      top: 65px;
      z-index: 30;
      box-shadow: 0 4px 12px rgba(0,0,0,0.02);
    }
    .categories {
      display: flex;
      gap: 12px;
      overflow-x: auto;
      scrollbar-width: none;
      -webkit-overflow-scrolling: touch;
      padding-bottom: 4px;
    }
    .categories::-webkit-scrollbar { display: none; }
    .cat-btn {
      background: var(--bg);
      border: 1px solid var(--line);
      padding: 10px 20px;
      border-radius: 999px;
      font-size: 14px;
      font-weight: 600;
      color: var(--muted);
      cursor: pointer;
      white-space: nowrap;
      transition: all 0.2s;
    }
    .cat-btn.active {
      background: var(--ink);
      border-color: var(--ink);
      color: #fff;
    }
    .cat-btn:hover:not(.active) {
      background: #e5e7eb;
      color: var(--ink);
    }

    /* Product Grid */
    .catalog-section {
      padding: 48px 0;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 24px;
    }
    .card {
      background: var(--surface);
      border-radius: var(--radius-lg);
      overflow: hidden;
      box-shadow: var(--shadow-sm);
      border: 1px solid var(--line);
      display: flex;
      flex-direction: column;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      cursor: pointer;
      position: relative;
    }
    .card:hover {
      box-shadow: var(--shadow-lg);
      transform: translateY(-4px);
    }
    .card-img-wrap {
      aspect-ratio: 4/3;
      background: #f3f4f6;
      overflow: hidden;
      position: relative;
    }
    .card-img-wrap img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      transition: transform 0.5s ease;
    }
    .card:hover .card-img-wrap img {
      transform: scale(1.05);
    }
    .placeholder-icon {
      position: absolute;
      inset: 0;
      display: grid;
      place-items: center;
      color: #9ca3af;
      font-size: 40px;
    }
    .availability-badge {
      position: absolute;
      top: 12px;
      left: 12px;
      background: rgba(255,255,255,0.9);
      backdrop-filter: blur(4px);
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      color: var(--ink);
      box-shadow: var(--shadow-sm);
    }
    .availability-badge.unavailable {
      color: var(--danger);
      background: rgba(254, 226, 226, 0.9);
    }
    .card-body {
      padding: 20px;
      display: flex;
      flex-direction: column;
      flex: 1;
    }
    .card-brand {
      font-size: 12px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .card-title {
      font-size: 16px;
      font-weight: 700;
      color: var(--ink);
      margin: 0 0 8px 0;
      line-height: 1.3;
    }
    .card-variants {
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 16px;
    }
    .card-footer {
      margin-top: auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .card-price {
      font-size: 20px;
      font-weight: 800;
      color: var(--ink);
    }
    .add-btn {
      background: var(--ink);
      color: #fff;
      border: none;
      width: 36px;
      height: 36px;
      border-radius: 18px;
      display: grid;
      place-items: center;
      font-size: 20px;
      cursor: pointer;
      transition: background 0.2s, transform 0.2s;
    }
    .add-btn:hover {
      background: var(--primary);
      transform: scale(1.05);
    }
    .variant-select-wrapper {
      margin-top: 12px;
    }
    .variant-select-wrapper select {
      width: 100%;
      padding: 10px 12px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--line);
      font-family: inherit;
      font-size: 14px;
      background: #f9fafc;
    }

    /* Cart Drawer */
    .cart-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(17, 24, 39, 0.6);
      backdrop-filter: blur(4px);
      z-index: 100;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.3s ease;
    }
    .cart-backdrop.open {
      opacity: 1;
      pointer-events: auto;
    }
    .cart-drawer {
      position: fixed;
      top: 0;
      right: 0;
      bottom: 0;
      width: min(440px, 100vw);
      background: var(--surface);
      z-index: 101;
      transform: translateX(100%);
      transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1);
      display: flex;
      flex-direction: column;
      box-shadow: var(--shadow-floating);
    }
    .cart-drawer.open {
      transform: translateX(0);
    }
    .cart-header {
      padding: 24px;
      border-bottom: 1px solid var(--line);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .cart-header h2 {
      margin: 0;
      font-size: 24px;
      font-weight: 800;
      letter-spacing: -0.03em;
    }
    .close-btn {
      background: transparent;
      border: none;
      font-size: 28px;
      color: var(--muted);
      cursor: pointer;
      line-height: 1;
      padding: 4px;
    }
    .close-btn:hover { color: var(--ink); }
    
    .cart-body {
      flex: 1;
      overflow-y: auto;
      padding: 24px;
      display: flex;
      flex-direction: column;
      gap: 24px;
    }
    .cart-item {
      display: flex;
      gap: 16px;
      align-items: center;
    }
    .cart-item-img {
      width: 64px;
      height: 64px;
      border-radius: var(--radius-sm);
      background: #f3f4f6;
      object-fit: cover;
    }
    .cart-item-info {
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .cart-item-title {
      font-size: 14px;
      font-weight: 600;
      color: var(--ink);
    }
    .cart-item-price {
      font-size: 14px;
      color: var(--muted);
    }
    .cart-item-actions {
      display: flex;
      align-items: center;
      gap: 12px;
      background: var(--bg);
      border-radius: 999px;
      padding: 4px;
      border: 1px solid var(--line);
    }
    .qty-btn {
      width: 28px;
      height: 28px;
      border-radius: 14px;
      background: #fff;
      border: 1px solid var(--line);
      display: grid;
      place-items: center;
      cursor: pointer;
      font-size: 16px;
      font-weight: 600;
      color: var(--ink);
    }
    .qty-display {
      font-size: 14px;
      font-weight: 600;
      min-width: 20px;
      text-align: center;
    }
    .cart-empty-state {
      text-align: center;
      padding: 60px 20px;
      color: var(--muted);
    }
    .cart-empty-state svg {
      width: 64px;
      height: 64px;
      opacity: 0.2;
      margin-bottom: 16px;
    }

    /* Checkout Form */
    .checkout-form {
      display: flex;
      flex-direction: column;
      gap: 16px;
      background: var(--bg);
      padding: 20px;
      border-radius: var(--radius-md);
      border: 1px solid var(--line);
    }
    .form-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .form-group label {
      font-size: 13px;
      font-weight: 700;
      color: var(--ink);
    }
    .form-input {
      padding: 12px 16px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--line);
      font-family: inherit;
      font-size: 15px;
      transition: all 0.2s;
    }
    .form-input:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(0,0,0,0.05);
    }
    textarea.form-input {
      min-height: 80px;
      resize: vertical;
    }
    .radio-group {
      display: flex;
      gap: 12px;
    }
    .radio-label {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 12px;
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-weight: 600;
      font-size: 14px;
      background: #fff;
      transition: all 0.2s;
    }
    .radio-label:has(input:checked) {
      border-color: var(--ink);
      background: var(--ink);
      color: #fff;
    }
    .radio-label input {
      display: none;
    }

    .cart-footer {
      padding: 24px;
      border-top: 1px solid var(--line);
      background: var(--surface);
    }
    .cart-total-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
      font-size: 20px;
      font-weight: 800;
    }
    .checkout-btn {
      width: 100%;
      padding: 16px;
      background: var(--primary);
      color: #fff;
      border: none;
      border-radius: var(--radius-sm);
      font-size: 16px;
      font-weight: 800;
      cursor: pointer;
      transition: transform 0.2s, opacity 0.2s;
    }
    .checkout-btn:hover { opacity: 0.9; }
    .checkout-btn:active { transform: scale(0.98); }
    .checkout-btn:disabled {
      background: var(--muted);
      cursor: not-allowed;
      transform: none;
    }
    .whatsapp-btn {
      display: none;
      width: 100%;
      padding: 16px;
      background: #25D366;
      color: #fff;
      border: none;
      border-radius: var(--radius-sm);
      font-size: 16px;
      font-weight: 800;
      cursor: pointer;
      text-align: center;
      text-decoration: none;
      margin-top: 12px;
    }

    /* System Messages */
    .alert {
      padding: 16px;
      border-radius: var(--radius-sm);
      font-size: 14px;
      font-weight: 600;
      margin-bottom: 16px;
      display: none;
    }
    .alert-success { background: #d1fae5; color: #065f46; border: 1px solid #34d399; }
    .alert-error { background: #fee2e2; color: #991b1b; border: 1px solid #f87171; }

    /* Footer */
    .site-footer {
      border-top: 1px solid var(--line);
      padding: 40px 0;
      margin-top: 40px;
      background: #fff;
      text-align: center;
      color: var(--muted);
      font-size: 14px;
    }
    .footer-links {
      display: flex;
      justify-content: center;
      gap: 24px;
      margin-top: 16px;
    }
    .footer-links a {
      color: var(--muted);
      text-decoration: none;
      font-weight: 600;
    }
    .footer-links a:hover { color: var(--ink); }

    /* Mobile floating button */
    .mobile-cart-float {
      display: none;
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: var(--primary);
      color: white;
      border: none;
      border-radius: 999px;
      padding: 14px 24px;
      font-weight: 800;
      font-size: 15px;
      box-shadow: var(--shadow-floating);
      z-index: 30;
      cursor: pointer;
    }

    @media (max-width: 768px) {
      .hero { min-height: 320px; padding: 40px 0 30px; }
      .hero-title { font-size: 32px; }
      .grid { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 16px; }
      .card-body { padding: 12px; }
      .card-title { font-size: 14px; }
      .card-price { font-size: 16px; }
      .add-btn { width: 32px; height: 32px; font-size: 18px; }
      .navbar .cart-btn-top { display: none; }
      .mobile-cart-float { display: flex; align-items: center; gap: 8px; }
    }
  </style>
</head>
<body>

  <!-- Top Navigation -->
  <header class="navbar">
    <div class="wrap nav-inner">
      <a href="#" class="brand-lockup">
        <div class="logo-mark">
          \${logoUrl ? \`<img src="\${escapeHtml(logoUrl)}" alt="Logo" />\` : storeInitial}
        </div>
        <span>\${escapeHtml(businessName)}</span>
      </a>
      <div class="nav-actions">
        <button class="cart-btn-top" onclick="toggleCart()">
          <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
          </svg>
          Cart <span class="cart-badge" id="nav-cart-count">0</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Hero Banner -->
  <section class="hero">
    <div class="wrap hero-content">
      <h1 class="hero-title">\${escapeHtml(businessName)}</h1>
      <p class="hero-subtitle">\${escapeHtml(tagline)}</p>
      
      <div class="search-bar">
        <svg class="search-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
        </svg>
        <input type="text" id="search-input" placeholder="Search products..." onkeyup="handleSearch()" />
      </div>
    </div>
  </section>

  <!-- Categories Sticky Bar -->
  <div class="categories-wrap">
    <div class="wrap categories" id="category-pills">
      <button class="cat-btn active" onclick="setCategory('all', this)">All Items</button>
      <!-- Categories injected via JS -->
    </div>
  </div>

  <!-- Main Catalog Grid -->
  <main class="catalog-section wrap">
    <div id="empty-state" style="display: none; text-align: center; padding: 60px 0; color: var(--muted);">
      <svg width="64" height="64" fill="none" stroke="currentColor" viewBox="0 0 24 24" style="opacity:0.3; margin:0 auto 16px;">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"></path>
      </svg>
      <h3>No products found</h3>
      <p>Try adjusting your search or category filter.</p>
    </div>
    
    <div class="grid" id="product-grid">
      <!-- Products injected via JS -->
    </div>
  </main>

  <!-- Order Tracking -->
  <section class="wrap" style="margin-top: 48px; background: var(--surface); padding: 32px; border-radius: var(--radius-lg); border: 1px solid var(--line);">
    <h3 style="margin: 0 0 16px; font-size: 20px;">Track your order</h3>
    <form id="tracking-form" style="display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end;" onsubmit="trackOrder(event)">
      <div class="form-group" style="flex:1; min-width:200px">
        <label>Order Number</label>
        <input id="tracking-order-number" class="form-input" required placeholder="A1B2C3D4">
      </div>
      <div class="form-group" style="flex:1; min-width:200px">
        <label>Phone Number</label>
        <input id="tracking-phone" class="form-input" required placeholder="+254...">
      </div>
      <button type="submit" id="track-btn" class="cart-btn-top" style="height: 44px">Track Order</button>
    </form>
    <div id="tracking-result" class="alert" style="margin-top:16px"></div>
  </section>

  <!-- Footer -->
  <footer class="site-footer">
    <div class="wrap">
      <p>Powered by <strong>Piki POS</strong></p>
      <div class="footer-links">
        <a href="#">Terms of Service</a>
        <a href="#">Privacy Policy</a>
      </div>
    </div>
  </footer>

  <!-- Mobile Floating Cart -->
  <button class="mobile-cart-float" onclick="toggleCart()">
    <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
    </svg>
    View Cart (<span id="fab-cart-count">0</span>)
  </button>

  <!-- Slide-out Cart Drawer -->
  <div class="cart-backdrop" id="cart-backdrop" onclick="toggleCart()"></div>
  <aside class="cart-drawer" id="cart-drawer">
    <div class="cart-header">
      <h2>Your Cart</h2>
      <button class="close-btn" onclick="toggleCart()">&times;</button>
    </div>
    
    <div class="cart-body" id="cart-body">
      <!-- Cart items injected via JS -->
      <div class="cart-empty-state" id="cart-empty-state">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
        </svg>
        <p>Your cart is empty.<br>Browse the catalog to add items.</p>
      </div>
      
      <!-- Checkout Form (Hidden when empty) -->
      <div id="checkout-section" style="display: none;">
        <h3 style="margin: 0 0 16px; font-size: 16px;">Delivery Details</h3>
        
        <div id="alert-success" class="alert alert-success">Order placed successfully!</div>
        <div id="alert-error" class="alert alert-error">Something went wrong.</div>

        <form id="order-form" class="checkout-form" onsubmit="submitOrder(event)">
          <div class="form-group">
            <label>Name</label>
            <input type="text" id="customer-name" class="form-input" required placeholder="John Doe">
          </div>
          <div class="form-group">
            <label>Phone Number</label>
            <input type="tel" id="customer-phone" class="form-input" required placeholder="+254...">
          </div>
          
          <div class="radio-group">
            <label class="radio-label">
              <input type="radio" name="fulfillment" value="delivery" checked> Delivery
            </label>
            <label class="radio-label">
              <input type="radio" name="fulfillment" value="pickup"> Pickup
            </label>
          </div>

          <div class="form-group">
            <label>Address / Note</label>
            <textarea id="order-note" class="form-input" placeholder="Delivery instructions..."></textarea>
          </div>
        </form>
      </div>
    </div>
    
    <div class="cart-footer">
      <div class="cart-total-row">
        <span>Total</span>
        <span id="cart-total-display">$0.00</span>
      </div>
      <button class="checkout-btn" id="checkout-btn" onclick="document.getElementById('order-form').requestSubmit()" disabled>Place Order</button>
      <a href="#" class="whatsapp-btn" id="whatsapp-btn" target="_blank">Send via WhatsApp</a>
    </div>
  </aside>

  <!-- Application State & Logic -->
  <script id="catalog-data" type="application/json">\${safeCatalogJson}</script>
  <script>
    // System Init
    const catalog = JSON.parse(document.getElementById('catalog-data').textContent);
    const shopWhatsApp = '\${escapeHtml(whatsappNumber)}';
    
    // State
    const state = {
      cart: new Map(),
      activeCategory: 'all',
      searchQuery: '',
      isCartOpen: false
    };

    // DOM Elements
    const els = {
      grid: document.getElementById('product-grid'),
      empty: document.getElementById('empty-state'),
      catPills: document.getElementById('category-pills'),
      navCount: document.getElementById('nav-cart-count'),
      fabCount: document.getElementById('fab-cart-count'),
      cartDrawer: document.getElementById('cart-drawer'),
      cartBackdrop: document.getElementById('cart-backdrop'),
      cartBody: document.getElementById('cart-body'),
      cartEmpty: document.getElementById('cart-empty-state'),
      checkoutSec: document.getElementById('checkout-section'),
      cartTotal: document.getElementById('cart-total-display'),
      checkoutBtn: document.getElementById('checkout-btn'),
      whatsappBtn: document.getElementById('whatsapp-btn'),
      alertSuccess: document.getElementById('alert-success'),
      alertError: document.getElementById('alert-error'),
      searchInput: document.getElementById('search-input')
    };

    // Currency Formatter
    const currencyCode = catalog.currencyCode || catalog.currency || 'KES';
    const currencySymbol = String(catalog.currencySymbol || '').trim();
    const formatMoney = (amount) => {
      amount = Number(amount || 0);
      if (currencySymbol) {
        return currencySymbol + amount.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      }
      return new Intl.NumberFormat('en', { style: 'currency', currency: currencyCode }).format(amount);
    };

    // Helpers
    const safeHtml = (str) => String(str || '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m]);
    
    function init() {
      // Extract unique categories
      const cats = new Set();
      [...catalog.products, ...catalog.services].forEach(item => {
        if (item.category && item.category !== 'Services') cats.add(item.category);
      });
      
      // Render category pills
      const sortedCats = Array.from(cats).sort();
      sortedCats.forEach(c => {
        const btn = document.createElement('button');
        btn.className = 'cat-btn';
        btn.textContent = c;
        btn.onclick = () => setCategory(c, btn);
        els.catPills.appendChild(btn);
      });

      renderGrid();
      renderCart();
    }

    function handleSearch() {
      state.searchQuery = els.searchInput.value.toLowerCase().trim();
      renderGrid();
    }

    function setCategory(cat, btnElement) {
      state.activeCategory = cat;
      document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
      btnElement.classList.add('active');
      renderGrid();
    }

    function toggleCart() {
      state.isCartOpen = !state.isCartOpen;
      if (state.isCartOpen) {
        els.cartDrawer.classList.add('open');
        els.cartBackdrop.classList.add('open');
        document.body.style.overflow = 'hidden';
      } else {
        els.cartDrawer.classList.remove('open');
        els.cartBackdrop.classList.remove('open');
        document.body.style.overflow = '';
      }
    }

    function getItems() {
      return [...catalog.products, ...catalog.services].filter(item => {
        const matchCat = state.activeCategory === 'all' || item.category === state.activeCategory;
        const matchSearch = !state.searchQuery || item.name.toLowerCase().includes(state.searchQuery) || (item.brand || '').toLowerCase().includes(state.searchQuery);
        return matchCat && matchSearch;
      });
    }

    function renderGrid() {
      const items = getItems();
      els.grid.innerHTML = '';
      
      if (items.length === 0) {
        els.empty.style.display = 'block';
        return;
      }
      
      els.empty.style.display = 'none';
      
      items.forEach(item => {
        const isAvailable = item.availability === 'Available';
        const badge = isAvailable 
          ? '' 
          : '<div class="availability-badge unavailable">Unavailable</div>';
        
        const img = item.imageUrl 
          ? \`<img src="\${safeHtml(item.imageUrl)}" loading="lazy" alt="\${safeHtml(item.name)}">\`
          : \`<div class="placeholder-icon"><svg width="32" height="32" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg></div>\`;

        // Handle variants selector if needed
        let variantsHtml = '';
        let primaryPrice = item.price;
        
        if (item.hasVariants && item.variants.length > 0) {
          primaryPrice = item.variants[0].price;
          variantsHtml = \`
            <div class="variant-select-wrapper" onclick="event.stopPropagation()">
              <select id="var-\${item.id}" onchange="updatePrice('\${item.id}', this.options[this.selectedIndex].dataset.price)">
                \${item.variants.map((v, i) => \`<option value="\${v.id}" data-price="\${v.price}" \${i===0?'selected':''}>\${safeHtml(v.name)} - \${formatMoney(v.price)}</option>\`).join('')}
              </select>
            </div>
          \`;
        } else if (item.hasVariants) {
          variantsHtml = '<div class="card-variants">Multiple options available</div>';
        }

        const priceId = \`price-\${item.id}\`;

        const card = document.createElement('div');
        card.className = 'card';
        card.onclick = () => {
          // If variants exist, get the selected one
          let selectedVarId = null;
          if (item.hasVariants && item.variants.length > 0) {
            const sel = document.getElementById(\`var-\${item.id}\`);
            if (sel) selectedVarId = sel.value;
          }
          addToCart(item, selectedVarId);
        };

        card.innerHTML = \`
          <div class="card-img-wrap">
            \${badge}
            \${img}
          </div>
          <div class="card-body">
            \${item.brand && item.brand !== 'Service' ? \`<div class="card-brand">\${safeHtml(item.brand)}</div>\` : ''}
            <h3 class="card-title">\${safeHtml(item.name)}</h3>
            \${variantsHtml}
            <div class="card-footer">
              <div class="card-price" id="\${priceId}">\${formatMoney(primaryPrice)}</div>
              <button class="add-btn" onclick="event.stopPropagation(); this.parentElement.parentElement.parentElement.click()" aria-label="Add to cart">
                +
              </button>
            </div>
          </div>
        \`;
        els.grid.appendChild(card);
      });
    }

    // Global function to update price displayed on the card when variant changes
    window.updatePrice = (itemId, newPrice) => {
      const priceEl = document.getElementById(\`price-\${itemId}\`);
      if (priceEl) {
        priceEl.textContent = formatMoney(newPrice);
      }
    };

    function cartKey(item, variantId) {
      return item.id + ':' + (variantId || '');
    }

    function addToCart(item, variantId) {
      const key = cartKey(item, variantId);
      const existing = state.cart.get(key);
      
      let variant = null;
      if (variantId && item.variants) {
        variant = item.variants.find(v => v.id === variantId);
      }

      state.cart.set(key, {
        item,
        variant,
        qty: existing ? existing.qty + 1 : 1
      });

      // Reset states
      els.alertSuccess.style.display = 'none';
      els.alertError.style.display = 'none';
      els.whatsappBtn.style.display = 'none';
      els.checkoutBtn.style.display = 'block';

      renderCart();
      toggleCart(); // Open cart on add
    }

    function updateQty(key, delta) {
      const existing = state.cart.get(key);
      if (!existing) return;
      
      const newQty = existing.qty + delta;
      if (newQty <= 0) {
        state.cart.delete(key);
      } else {
        existing.qty = newQty;
      }
      renderCart();
    }

    function renderCart() {
      const items = Array.from(state.cart.values());
      const totalQty = items.reduce((sum, i) => sum + i.qty, 0);
      
      els.navCount.textContent = totalQty;
      els.fabCount.textContent = totalQty;

      if (items.length === 0) {
        els.cartEmpty.style.display = 'block';
        els.checkoutSec.style.display = 'none';
        els.checkoutBtn.disabled = true;
        // clear old item nodes
        document.querySelectorAll('.cart-item-row').forEach(n => n.remove());
        els.cartTotal.textContent = formatMoney(0);
        return;
      }

      els.cartEmpty.style.display = 'none';
      els.checkoutSec.style.display = 'block';
      els.checkoutBtn.disabled = false;

      // Render lines
      document.querySelectorAll('.cart-item-row').forEach(n => n.remove());
      
      let totalValue = 0;

      items.forEach(cartEntry => {
        const { item, variant, qty } = cartEntry;
        const key = cartKey(item, variant ? variant.id : null);
        const price = variant ? variant.price : item.price;
        const title = variant ? \`\${item.name} (\${variant.name})\` : item.name;
        totalValue += (price * qty);

        const imgHtml = item.imageUrl 
          ? \`<img src="\${safeHtml(item.imageUrl)}" class="cart-item-img">\`
          : \`<div class="cart-item-img" style="display:grid;place-items:center;color:#9ca3af"><svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16"></path></svg></div>\`;

        const row = document.createElement('div');
        row.className = 'cart-item cart-item-row';
        row.innerHTML = \`
          \${imgHtml}
          <div class="cart-item-info">
            <div class="cart-item-title">\${safeHtml(title)}</div>
            <div class="cart-item-price">\${formatMoney(price)}</div>
          </div>
          <div class="cart-item-actions">
            <button class="qty-btn" onclick="updateQty('\${key}', -1)">-</button>
            <span class="qty-display">\${qty}</span>
            <button class="qty-btn" onclick="updateQty('\${key}', 1)">+</button>
          </div>
        \`;
        els.cartBody.insertBefore(row, els.checkoutSec);
      });

      els.cartTotal.textContent = formatMoney(totalValue);
    }

    async function submitOrder(e) {
      e.preventDefault();
      
      const items = Array.from(state.cart.values());
      if (items.length === 0) return;

      const name = document.getElementById('customer-name').value;
      const phone = document.getElementById('customer-phone').value;
      const method = document.querySelector('input[name="fulfillment"]:checked').value;
      const note = document.getElementById('order-note').value;

      els.checkoutBtn.disabled = true;
      els.checkoutBtn.textContent = 'Processing...';
      els.alertError.style.display = 'none';

      try {
        const payload = {
          businessId: catalog.business.id,
          branchId: catalog.business.selectedBranch ? catalog.business.selectedBranch.id : null,
          customerName: name,
          phone,
          fulfillmentMethod: method,
          deliveryAddress: note,
          note: note,
          lines: items.map(entry => ({
            productId: entry.item.type === 'product' ? entry.item.id : null,
            variantId: entry.variant ? entry.variant.id : null,
            serviceId: entry.item.type === 'service' ? entry.item.serviceId : null,
            quantity: entry.qty
          }))
        };

        const res = await fetch('/api/public/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        const data = await res.json();
        
        if (!res.ok) {
          throw new Error(data.message || 'Failed to submit order');
        }

        // Success
        state.cart.clear();
        renderCart();
        
        els.alertSuccess.textContent = 'Order placed successfully! Reference: ' + data.order.order_number;
        els.alertSuccess.style.display = 'block';
        els.checkoutBtn.style.display = 'none';

        // Show WhatsApp button if configured
        if (shopWhatsApp) {
          const waUrl = new URL('https://wa.me/' + shopWhatsApp.replace(/\\D/g, ''));
          waUrl.searchParams.set('text', \`Hi, I just placed an order (\${data.order.order_number}) on your catalog. Please confirm.\`);
          els.whatsappBtn.href = waUrl.toString();
          els.whatsappBtn.style.display = 'block';
        }

      } catch (err) {
        els.alertError.textContent = err.message;
        els.alertError.style.display = 'block';
        els.checkoutBtn.disabled = false;
        els.checkoutBtn.textContent = 'Place Order';
      }
    }

    async function trackOrder(e) {
      e.preventDefault();
      const btn = document.getElementById('track-btn');
      const resDiv = document.getElementById('tracking-result');
      btn.textContent = 'Tracking...';
      btn.disabled = true;
      try {
        const no = document.getElementById('tracking-order-number').value.trim();
        const ph = document.getElementById('tracking-phone').value.trim();
        const res = await fetch(\`/api/public/orders/\${encodeURIComponent(no)}/track?phone=\${encodeURIComponent(ph)}\`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Not found');
        resDiv.className = 'alert alert-success';
        resDiv.innerHTML = \`Order status: <strong>\${safeHtml(data.order.status)}</strong><br>Last updated: \${new Date(data.order.updated_at).toLocaleString()}\`;
        resDiv.style.display = 'block';
      } catch (err) {
        resDiv.className = 'alert alert-error';
        resDiv.textContent = err.message;
        resDiv.style.display = 'block';
      } finally {
        btn.textContent = 'Track Order';
        btn.disabled = false;
      }
    }

    // Start
    init();
  </script>
</body>
</html>\`;
}

module.exports = { renderPublicCatalogPage };
