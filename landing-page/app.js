/* ==========================================================================
   PIKI POS LANDING PAGE - DYNAMIC INTERACTION ENGINE
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
    // ----------------------------------------------------------------------
    // 1. Header scroll interaction
    // ----------------------------------------------------------------------
    const header = document.getElementById('header');
    
    window.addEventListener('scroll', () => {
        if (window.scrollY > 50) {
            header.classList.add('scrolled');
        } else {
            header.classList.remove('scrolled');
        }
    });

    // ----------------------------------------------------------------------
    // 2. Mobile navigation toggle
    // ----------------------------------------------------------------------
    const menuToggle = document.getElementById('menuToggle');
    const navMenu = document.getElementById('navMenu');

    menuToggle.addEventListener('click', () => {
        navMenu.classList.toggle('active');
        const icon = menuToggle.querySelector('i');
        if (navMenu.classList.contains('active')) {
            icon.className = 'fa-solid fa-xmark';
        } else {
            icon.className = 'fa-solid fa-bars';
        }
    });

    // Close menu when clicking navigation links on mobile
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            navMenu.classList.remove('active');
            menuToggle.querySelector('i').className = 'fa-solid fa-bars';
        });
    });

    // ----------------------------------------------------------------------
    // 3. Business impact calculator logic
    // ----------------------------------------------------------------------
    const salesSlider = document.getElementById('monthlySales');
    const interruptionShareSlider = document.getElementById('interruptionShare');
    const offlineCaptureRateSlider = document.getElementById('offlineCaptureRate');

    const salesVal = document.getElementById('salesVal');
    const interruptionShareVal = document.getElementById('interruptionShareVal');
    const offlineCaptureRateVal = document.getElementById('offlineCaptureRateVal');

    const monthlySavingsVal = document.getElementById('monthlySavingsVal');
    const yearlySavingsVal = document.getElementById('yearlySavingsVal');

    function formatCurrency(amount) {
        return 'KES ' + Math.round(amount).toLocaleString();
    }

    function calculateSavings() {
        const sales = parseFloat(salesSlider.value);
        const interruptedSalesShare = parseFloat(interruptionShareSlider.value) / 100;
        const offlineCaptureRate = parseFloat(offlineCaptureRateSlider.value) / 100;

        const monthlyProtectedSales = sales * interruptedSalesShare * offlineCaptureRate;
        const yearlyProtectedSales = monthlyProtectedSales * 12;

        salesVal.textContent = formatCurrency(sales);
        interruptionShareVal.textContent = Math.round(interruptedSalesShare * 100) + '%';
        offlineCaptureRateVal.textContent = Math.round(offlineCaptureRate * 100) + '%';

        monthlySavingsVal.textContent = formatCurrency(monthlyProtectedSales);
        yearlySavingsVal.textContent = formatCurrency(yearlyProtectedSales);
    }

    if (salesSlider) {
        salesSlider.addEventListener('input', calculateSavings);
        interruptionShareSlider.addEventListener('input', calculateSavings);
        offlineCaptureRateSlider.addEventListener('input', calculateSavings);
        calculateSavings();
    }

    // ----------------------------------------------------------------------
    // 4. Dynamic pricing catalog from subscription plans
    // ----------------------------------------------------------------------
    const pricingPlans = document.getElementById('pricingPlans');
    const pricingMarket = document.getElementById('pricingMarket');
    const pricingSourceText = document.getElementById('pricingSourceText');

    const featureLabels = {
        pos: 'POS checkout',
        products: 'Products',
        categories: 'Categories',
        purchases: 'Purchases',
        sales: 'Sales history',
        dashboard: 'Dashboard',
        kopesha: 'Kopesha credit',
        profit_loss: 'Profit & Loss',
        reports: 'Reports',
        settings: 'Settings',
        shifts: 'Shifts',
        services: 'Services',
        agent: 'Piki AI',
        stock_list: 'Stock list',
        transfers: 'Transfers',
        branches: 'Branches',
        audit_logs: 'Audit logs',
        proactive_piki: 'Proactive Piki'
    };

    const sellingModeLabels = {
        products: 'Products',
        services: 'Services',
        combo: 'Products + services'
    };

    function moneyFromMinor(amountMinor, currency) {
        const amount = Number(amountMinor || 0) / 100;
        const hasDecimals = !['KES', 'UGX', 'TZS', 'NGN'].includes(String(currency || '').toUpperCase());
        return new Intl.NumberFormat('en', {
            style: 'currency',
            currency: currency || 'KES',
            minimumFractionDigits: hasDecimals ? 2 : 0,
            maximumFractionDigits: hasDecimals ? 2 : 0
        }).format(amount);
    }

    function planPriceText(plan) {
        const price = plan.price;
        if (!price) {
            return {
                amount: 'Custom',
                suffix: 'price not published'
            };
        }
        if (Number(price.amountMinor || 0) === 0) {
            return {
                amount: 'Free',
                suffix: price.billingPeriod || 'monthly'
            };
        }
        return {
            amount: moneyFromMinor(price.amountMinor, price.currency),
            suffix: price.billingPeriod || 'monthly'
        };
    }

    function compactLimit(value, label) {
        const number = Number(value || 0);
        if (number >= 999999) return `Unlimited ${label}`;
        return `${number} ${label}`;
    }

    function renderMarkets(markets, selectedCountryCode) {
        if (!pricingMarket || !Array.isArray(markets) || markets.length === 0) {
            return;
        }
        pricingMarket.innerHTML = markets.map((market) => {
            const code = market.countryCode || 'GLOBAL';
            const label = market.label || code;
            const provider = market.providerLabel ? ` - ${market.providerLabel}` : '';
            return `<option value="${escapeHtml(code)}">${escapeHtml(label + provider)}</option>`;
        }).join('');
        pricingMarket.value = selectedCountryCode || markets[0].countryCode || 'KE';
    }

    function renderPricingPlans(plans, meta) {
        if (!pricingPlans) return;
        if (!Array.isArray(plans) || plans.length === 0) {
            pricingPlans.innerHTML = `
                <article class="pricing-empty glass-card">
                    <i class="fa-solid fa-circle-info"></i>
                    <h3>No public plans yet</h3>
                    <p>Activate at least one plan and one market to publish pricing here.</p>
                </article>
            `;
            return;
        }

        pricingPlans.innerHTML = plans.map((plan, index) => {
            const price = planPriceText(plan);
            const features = (plan.features || []).slice(0, 6);
            const sellingModes = (plan.availableSellingModes || plan.sellingModes || [])
                .map((mode) => sellingModeLabels[mode] || mode)
                .slice(0, 3);
            const isPopular = index === Math.min(2, plans.length - 1) && plan.code !== 'trial';
            const cta = plan.price ? 'Request This Plan' : 'Discuss Pricing';
            return `
                <article class="pricing-card glass-card ${isPopular ? 'pricing-card-popular' : ''}">
                    ${isPopular ? '<span class="pricing-popular-badge">Best fit</span>' : ''}
                    <div class="pricing-card-header">
                        <span class="pricing-plan-code">${escapeHtml(plan.code || 'plan')}</span>
                        <h3>${escapeHtml(plan.name || 'Plan')}</h3>
                        <p>${escapeHtml(plan.description || 'Piki POS subscription plan')}</p>
                    </div>
                    <div class="pricing-price-row">
                        <span class="pricing-price">${escapeHtml(price.amount)}</span>
                        <span class="pricing-period">${escapeHtml(price.suffix)}</span>
                    </div>
                    <div class="pricing-limits">
                        <span><i class="fa-solid fa-store"></i>${escapeHtml(compactLimit(plan.maxBranches, 'branch'))}</span>
                        <span><i class="fa-solid fa-users"></i>${escapeHtml(compactLimit(plan.maxEmployees, 'users'))}</span>
                        <span><i class="fa-solid fa-wand-magic-sparkles"></i>${escapeHtml(compactLimit(plan.maxAiAgents, 'AI seat'))}</span>
                    </div>
                    ${sellingModes.length ? `<div class="pricing-modes">${sellingModes.map((mode) => `<span>${escapeHtml(mode)}</span>`).join('')}</div>` : ''}
                    <ul class="pricing-feature-list">
                        ${features.map((feature) => `<li><i class="fa-solid fa-check"></i>${escapeHtml(featureLabels[feature] || feature)}</li>`).join('')}
                    </ul>
                    <a class="btn btn-primary btn-block pricing-plan-cta" href="#contact" data-plan="${escapeHtml(plan.name || '')}">${cta}</a>
                </article>
            `;
        }).join('');

        if (pricingSourceText) {
            const market = meta?.selectedMarket?.label || meta?.countryCode || 'selected market';
            const provider = meta?.selectedMarket?.providerLabel || meta?.provider || 'payment gateway';
            pricingSourceText.textContent = `Showing current ${market} pricing via ${provider}`;
        }

        document.querySelectorAll('.pricing-plan-cta').forEach((button) => {
            button.addEventListener('click', () => {
                const messageInput = document.getElementById('contactMessage');
                const planName = button.getAttribute('data-plan');
                if (messageInput && planName) {
                    messageInput.value = `I want setup help for the ${planName} plan.`;
                }
            });
        });
    }

    async function loadPricingPlans(countryCode = 'KE') {
        if (!pricingPlans) return;
        if (pricingSourceText) {
            pricingSourceText.textContent = 'Loading live plans...';
        }
        try {
            const response = await fetch(`/api/subscription/plans?countryCode=${encodeURIComponent(countryCode)}`);
            const body = await response.json().catch(() => ({}));
            if (!response.ok || body.ok !== true) {
                throw new Error(body.error || 'Could not load pricing plans.');
            }
            renderMarkets(body.markets || [], body.countryCode);
            renderPricingPlans(body.plans || [], body);
        } catch (error) {
            if (pricingSourceText) {
                pricingSourceText.textContent = 'Could not load live pricing';
            }
            pricingPlans.innerHTML = `
                <article class="pricing-empty glass-card">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    <h3>Pricing is temporarily unavailable</h3>
                    <p>${escapeHtml(error.message || 'Please request setup help and the team will share the latest plan options.')}</p>
                    <a class="btn btn-primary btn-sm" href="#contact">Request Pricing</a>
                </article>
            `;
        }
    }

    if (pricingMarket) {
        pricingMarket.addEventListener('change', () => {
            loadPricingPlans(pricingMarket.value || 'KE');
        });
    }

    loadPricingPlans();
});

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

// --------------------------------------------------------------------------
// 4. Testimonials Slider carousel
// --------------------------------------------------------------------------
let currentSlideIndex = 0;
const slides = document.querySelectorAll('.testimonial-slide');

function showSlide(index) {
    slides.forEach(slide => slide.classList.remove('active'));
    
    if (index >= slides.length) {
        currentSlideIndex = 0;
    } else if (index < 0) {
        currentSlideIndex = slides.length - 1;
    } else {
        currentSlideIndex = index;
    }
    
    slides[currentSlideIndex].classList.add('active');
}

function nextSlide() {
    showSlide(currentSlideIndex + 1);
}

function prevSlide() {
    showSlide(currentSlideIndex - 1);
}

// Auto slider rotation
let autoSlideInterval = setInterval(nextSlide, 8000);

const prevBtn = document.querySelector('.btn-prev');
const nextBtn = document.querySelector('.btn-next');
if (prevBtn && nextBtn) {
    prevBtn.addEventListener('click', () => {
        clearInterval(autoSlideInterval);
        autoSlideInterval = setInterval(nextSlide, 8000);
    });
    nextBtn.addEventListener('click', () => {
        clearInterval(autoSlideInterval);
        autoSlideInterval = setInterval(nextSlide, 8000);
    });
}

// --------------------------------------------------------------------------
// 5. FAQ Accordion panel expansion
// --------------------------------------------------------------------------
function toggleFaq(element) {
    const faqItem = element.parentElement;
    const answer = faqItem.querySelector('.faq-answer');
    const isActive = faqItem.classList.contains('active');

    // Close all other open items
    const allItems = document.querySelectorAll('.faq-item');
    allItems.forEach(item => {
        item.classList.remove('active');
        item.querySelector('.faq-answer').style.maxHeight = null;
    });

    if (!isActive) {
        faqItem.classList.add('active');
        answer.style.maxHeight = answer.scrollHeight + "px";
    }
}

// --------------------------------------------------------------------------
// 6. Interactive POS Simulator Engine
// --------------------------------------------------------------------------
let simulatorCart = [];
let currentPaymentMethod = 'cash';
let offlineTxQueue = [];
let sqliteTransactionsCount = 0;
let neonTransactionsCount = 0;

// Update network indicators and listeners
const networkToggle = document.getElementById('networkToggle');
const terminalNetworkBadge = document.getElementById('terminalNetworkBadge');
const heroSyncStatus = document.getElementById('heroSyncStatus');
const neonCloudStatus = document.getElementById('neonCloudStatus');
const consoleLogs = document.getElementById('consoleLogs');

if (networkToggle) {
    networkToggle.addEventListener('change', (e) => {
        const isOnline = e.target.checked;
        
        if (isOnline) {
            terminalNetworkBadge.textContent = 'ONLINE';
            terminalNetworkBadge.className = 'connection-badge online';
            heroSyncStatus.textContent = 'Connected';
            heroSyncStatus.className = 'status-indicator online';
            heroSyncStatus.innerHTML = '<span class="pulse-ring"></span><i class="fa-solid fa-circle"></i> Connected';
            
            logSyncConsole('system', 'Network Connection RESTORED.');
            triggerBackgroundSync();
        } else {
            terminalNetworkBadge.textContent = 'OFFLINE';
            terminalNetworkBadge.className = 'connection-badge offline';
            heroSyncStatus.textContent = 'Offline Mode';
            heroSyncStatus.className = 'status-indicator offline';
            heroSyncStatus.innerHTML = '<i class="fa-solid fa-plane-arrival"></i> Offline Mode';
            
            logSyncConsole('system', 'Network Connection LOST. Running in local-first offline fallback mode.');
        }
    });
}

function logSyncConsole(type, message) {
    if (!consoleLogs) return;
    const timestamp = new Date().toLocaleTimeString();
    const logLine = document.createElement('div');
    logLine.className = `log-line ${type}`;
    logLine.textContent = `[${timestamp}] [${type.toUpperCase()}] ${message}`;
    consoleLogs.appendChild(logLine);
    consoleLogs.scrollTop = consoleLogs.scrollHeight;
}

function addToCart(name, price, icon) {
    const existingItem = simulatorCart.find(item => item.name === name);
    if (existingItem) {
        existingItem.qty += 1;
    } else {
        simulatorCart.push({ name, price, qty: 1, icon });
    }
    
    logSyncConsole('local', `Added to cart on this device: ${name} (KES ${price})`);
    renderCart();
}

function renderCart() {
    const container = document.getElementById('cartContainer');
    const subtotalText = document.getElementById('cartSubtotal');
    const totalText = document.getElementById('cartTotal');
    
    if (!container) return;
    
    if (simulatorCart.length === 0) {
        container.innerHTML = `
            <div class="empty-cart-message">
                <i class="fa-solid fa-cart-shopping"></i>
                <p>Cart is empty. Click items to add.</p>
            </div>
        `;
        subtotalText.textContent = 'KES 0';
        totalText.textContent = 'KES 0';
        return;
    }
    
    container.innerHTML = '';
    let total = 0;
    
    simulatorCart.forEach((item, index) => {
        const itemTotal = item.price * item.qty;
        total += itemTotal;
        
        const row = document.createElement('div');
        row.className = 'cart-item-row';
        row.innerHTML = `
            <div class="c-item-details">
                <span class="c-item-name">${item.name}</span>
                <span class="c-item-qty">Qty: ${item.qty} &times; KES ${item.price}</span>
            </div>
            <div class="c-item-price-remove">
                <span class="c-item-price">KES ${itemTotal}</span>
                <button class="c-item-remove" onclick="removeFromCart(${index})">
                    <i class="fa-solid fa-trash-can"></i>
                </button>
            </div>
        `;
        container.appendChild(row);
    });
    
    subtotalText.textContent = 'KES ' + total.toLocaleString();
    totalText.textContent = 'KES ' + total.toLocaleString();
}

function removeFromCart(index) {
    const item = simulatorCart[index];
    logSyncConsole('local', `Removed from cart on this device: ${item.name}`);
    simulatorCart.splice(index, 1);
    renderCart();
}

function selectPaymentMethod(method) {
    currentPaymentMethod = method;
    
    // Toggle active state visual
    const buttons = document.querySelectorAll('.pay-method-btn');
    buttons.forEach(btn => btn.classList.remove('active'));
    
    const activeBtn = document.querySelector(`.pay-method-btn[data-type="${method}"]`);
    if (activeBtn) activeBtn.classList.add('active');
    
    // Toggle credit fields for Kopesha
    const kopeshaFields = document.getElementById('kopeshaFields');
    if (method === 'kopesha') {
        kopeshaFields.classList.remove('hidden');
        logSyncConsole('local', 'Kopesha credit option chosen. Ready to record customer balance.');
    } else {
        kopeshaFields.classList.add('hidden');
        logSyncConsole('local', `Payment selected: ${method.toUpperCase()}`);
    }
}

function processCheckout() {
    if (simulatorCart.length === 0) {
        logSyncConsole('error', 'Checkout failed. Cart is empty!');
        alert('Please add items to your cart first.');
        return;
    }
    
    const isOnline = networkToggle ? networkToggle.checked : true;
    let totalVal = 0;
    simulatorCart.forEach(item => totalVal += (item.price * item.qty));
    
    const receiptPreview = document.getElementById('receiptPreview');
    const rNum = document.getElementById('rNum');
    const rDate = document.getElementById('rDate');
    const rItems = document.getElementById('receiptItems');
    const receiptTotalVal = document.getElementById('receiptTotalVal');
    const receiptPaymentType = document.getElementById('receiptPaymentType');
    const receiptKopeshaDetail = document.getElementById('receiptKopeshaDetail');
    const receiptStatusText = document.getElementById('receiptStatusText');
    
    const txId = 'TX-' + Math.floor(100000 + Math.random() * 900000);
    const dateStr = new Date().toISOString().replace('T', ' ').substring(0, 16);
    
    // Update local transaction count
    sqliteTransactionsCount++;
    document.getElementById('sqliteTxCount').textContent = `${sqliteTransactionsCount} Transactions`;
    logSyncConsole('local', `Checkout completed on this device. Transaction ID: ${txId}`);
    
    // Setup simulated receipt details
    rNum.textContent = txId;
    rDate.textContent = dateStr;
    rItems.innerHTML = '';
    
    simulatorCart.forEach(item => {
        const itemRow = document.createElement('div');
        itemRow.className = 'r-item-row';
        itemRow.innerHTML = `
            <span>${item.qty}x ${item.name}</span>
            <span>KES ${(item.price * item.qty).toLocaleString()}</span>
        `;
        rItems.appendChild(itemRow);
    });
    
    receiptTotalVal.textContent = 'KES ' + totalVal.toLocaleString();
    receiptPaymentType.textContent = 'Payment Method: ' + currentPaymentMethod.toUpperCase();
    
    if (currentPaymentMethod === 'kopesha') {
        const custSelect = document.getElementById('customerSelect');
        const dueDateInput = document.getElementById('creditDueDate');
        const customerName = custSelect.options[custSelect.selectedIndex].text.split(' (')[0];
        
        receiptKopeshaDetail.classList.remove('hidden');
        receiptKopeshaDetail.innerHTML = `Customer: ${customerName}<br>Due Date: ${dueDateInput.value}`;
        
        logSyncConsole('local', `Recorded customer balance: Debited KES ${totalVal} to ${customerName}`);
    } else {
        receiptKopeshaDetail.classList.add('hidden');
    }
    
    // Queue offline or process cloud sync
    if (!isOnline) {
        offlineTxQueue.push({
            id: txId,
            items: [...simulatorCart],
            payment: currentPaymentMethod,
            total: totalVal,
            timestamp: dateStr
        });
        
        receiptStatusText.className = 'receipt-status-badge offline';
        receiptStatusText.textContent = 'OFFLINE TRANSACTION RECORDED';
        
        if (neonCloudStatus) {
            neonCloudStatus.textContent = 'PENDING SYNC';
            neonCloudStatus.className = 'badge badge-pending';
        }
        
        logSyncConsole('local', `Transaction ${txId} queued for sync. Waiting for internet connection...`);
    } else {
        receiptStatusText.className = 'receipt-status-badge online';
        receiptStatusText.textContent = 'CLOUD SYNCED TRANSACTION';
        
        // Simulate a successful sync for the browser demo.
        neonTransactionsCount++;
        document.getElementById('neonTxCount').textContent = `${neonTransactionsCount} Transactions`;
        logSyncConsole('cloud', `Synced successfully. Transaction ID: ${txId} is backed up.`);
    }
    
    // Display receipt
    receiptPreview.classList.remove('hidden');
    
    // Clear simulator cart
    simulatorCart = [];
    renderCart();
}

function triggerBackgroundSync() {
    if (offlineTxQueue.length === 0) {
        logSyncConsole('system', 'Records are currently fully synchronized.');
        return;
    }
    
    logSyncConsole('system', `Found ${offlineTxQueue.length} pending transaction(s). Sending queued changes to cloud sync...`);
    if (neonCloudStatus) {
        neonCloudStatus.textContent = 'SYNCING...';
        neonCloudStatus.className = 'badge badge-pending';
    }
    
    // Simulate API network latency
    setTimeout(() => {
        while(offlineTxQueue.length > 0) {
            const tx = offlineTxQueue.shift();
            neonTransactionsCount++;
            document.getElementById('neonTxCount').textContent = `${neonTransactionsCount} Transactions`;
            logSyncConsole('cloud', `Sync complete. Transaction ${tx.id} is now backed up (sync ${neonTransactionsCount}).`);
        }
        
        if (neonCloudStatus) {
            neonCloudStatus.textContent = 'SYNCED';
            neonCloudStatus.className = 'badge';
        }
        logSyncConsole('success', 'Device and cloud demo records are now in sync.');
        
        // Update current receipt status badge to online synced if it is visible
        const receiptStatusText = document.getElementById('receiptStatusText');
        if (receiptStatusText) {
            receiptStatusText.className = 'receipt-status-badge online';
            receiptStatusText.textContent = 'CLOUD SYNCED TRANSACTION';
        }
    }, 2000);
}

// --------------------------------------------------------------------------
// 7. Contact Lead Capture Form Submission Handler
// --------------------------------------------------------------------------
async function handleFormSubmit(event) {
    event.preventDefault();
    
    const form = document.getElementById('contactForm');
    const successMsg = document.getElementById('formSuccess');
    const errorMsg = document.getElementById('formError');
    const submitButton = form.querySelector('button[type="submit"]');
    const originalButtonHtml = submitButton.innerHTML;
    const name = document.getElementById('contactName').value.trim();
    const email = document.getElementById('contactEmail').value.trim();
    const storeType = document.getElementById('storeType').value;
    const message = document.getElementById('contactMessage').value.trim();
    
    if (errorMsg) {
        errorMsg.classList.add('hidden');
        errorMsg.textContent = '';
    }
    submitButton.disabled = true;
    submitButton.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Sending...';

    try {
        const response = await fetch('/api/public/demo-requests', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                fullName: name,
                email,
                storeType,
                message
            })
        });
        const body = await response.json().catch(() => ({}));

        if (!response.ok || body.ok === false) {
            throw new Error(body.error || 'Could not send your request. Please try again.');
        }

        form.classList.add('hidden');
        successMsg.classList.remove('hidden');
        logSyncConsole('system', `New store demo requested by: ${name}. Request ${body.data?.id || 'created'} saved.`);
    } catch (error) {
        if (errorMsg) {
            errorMsg.textContent = error.message;
            errorMsg.classList.remove('hidden');
        }
        logSyncConsole('error', `Demo request failed: ${error.message}`);
    } finally {
        submitButton.disabled = false;
        submitButton.innerHTML = originalButtonHtml;
    }
}
