/* ==========================================================================
   PIKI POS LANDING PAGE - DYNAMIC INTERACTION ENGINE
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
    // ----------------------------------------------------------------------
    // 0. Light / Dark theme toggle
    // ----------------------------------------------------------------------
    const themeToggle = document.getElementById('themeToggle');
    let savedTheme = null;
    try {
        savedTheme = localStorage.getItem('piki-theme');
    } catch (_) {
        // localStorage unavailable (e.g. sandboxed iframe)
    }

    function applyTheme(theme) {
        if (theme === 'light') {
            document.body.classList.add('light-mode');
        } else {
            document.body.classList.remove('light-mode');
        }
        updateThemeIcon(theme);
    }

    function updateThemeIcon(theme) {
        if (!themeToggle) return;
        const icon = themeToggle.querySelector('i');
        if (theme === 'light') {
            icon.className = 'fa-solid fa-moon';
        } else {
            icon.className = 'fa-solid fa-sun';
        }
    }

    if (savedTheme) {
        applyTheme(savedTheme);
    } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        applyTheme('light');
    }

    if (themeToggle) {
        themeToggle.addEventListener('click', () => {
            const isLight = document.body.classList.contains('light-mode');
            const newTheme = isLight ? 'dark' : 'light';
            applyTheme(newTheme);
            localStorage.setItem('piki-theme', newTheme);
        });
    }

    // ----------------------------------------------------------------------
    // 0b. Shared scroll reveal observer (used by static and dynamic content)
    // ----------------------------------------------------------------------
    const observedElements = new WeakSet();
    let revealObserver = null;

    function observeReveals(container) {
        const targets = (container || document).querySelectorAll('.reveal, .reveal-left, .reveal-right, .reveal-scale');
        if (!revealObserver) {
            // Fallback: immediately show elements on browsers without IntersectionObserver
            targets.forEach((el) => el.classList.add('active'));
            return;
        }
        targets.forEach((el) => {
            if (!observedElements.has(el)) {
                revealObserver.observe(el);
                observedElements.add(el);
            }
        });
    }

    if ('IntersectionObserver' in window) {
        revealObserver = new IntersectionObserver((entries, observer) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('active');
                    observer.unobserve(entry.target);
                }
            });
        }, {
            root: null,
            rootMargin: '0px 0px -60px 0px',
            threshold: 0.1
        });
    }

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
    }, { passive: true });

    // ----------------------------------------------------------------------
    // 1b. Sticky mobile CTA bar: show after hero, hide near contact/footer
    // ----------------------------------------------------------------------
    const stickyCtaBar = document.getElementById('stickyCtaBar');
    const contactSection = document.getElementById('contact');

    if (stickyCtaBar) {
        const updateStickyCta = () => {
            const pastHero = window.scrollY > 600;
            let nearContact = false;
            if (contactSection) {
                const rect = contactSection.getBoundingClientRect();
                // Hide once the contact section's top reaches the upper half of viewport
                nearContact = rect.top < window.innerHeight * 0.6;
            }
            if (pastHero && !nearContact) {
                stickyCtaBar.classList.add('visible');
                stickyCtaBar.setAttribute('aria-hidden', 'false');
            } else {
                stickyCtaBar.classList.remove('visible');
                stickyCtaBar.setAttribute('aria-hidden', 'true');
            }
        };
        window.addEventListener('scroll', updateStickyCta, { passive: true });
        updateStickyCta();
    }

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
    // 2b. Download section OS detection and fallback
    // ----------------------------------------------------------------------
    const downloadCards = document.querySelectorAll('.download-card');
    const userAgent = navigator.userAgent.toLowerCase();
    const isWindows = userAgent.includes('windows');
    const isAndroid = userAgent.includes('android');

    downloadCards.forEach((card) => {
        const os = card.getAttribute('data-os');
        const link = card.querySelector('.download-link');
        const meta = card.querySelector('.download-meta');

        // Highlight the card that matches the visitor's OS
        if ((os === 'windows' && isWindows) || (os === 'android' && isAndroid)) {
            card.classList.add('recommended');
        }

        // Warn if the file has not been uploaded yet
        if (link) {
            link.addEventListener('click', () => {
                const href = link.getAttribute('href') || '';
                if (href.includes('/downloads/') || href.startsWith('downloads/')) {
                    // In a static file context the download may 404.
                    // Let the browser handle it; log for debugging.
                    console.debug('Download requested:', href);
                }
            });
        }
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

    function animateValue(element, start, end, duration = 500) {
        if (!element) return;
        const startTime = performance.now();
        function step(currentTime) {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);
            const easeProgress = 1 - Math.pow(1 - progress, 3); // easeOutCubic
            const current = start + (end - start) * easeProgress;
            element.textContent = formatCurrency(current);
            if (progress < 1) {
                requestAnimationFrame(step);
            }
        }
        requestAnimationFrame(step);
    }

    let previousMonthly = 0;
    let previousYearly = 0;

    function parseKesValue(text) {
        return Number(String(text).replace(/[^0-9.-]/g, '')) || 0;
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

        animateValue(monthlySavingsVal, previousMonthly, monthlyProtectedSales, 500);
        animateValue(yearlySavingsVal, previousYearly, yearlyProtectedSales, 600);

        previousMonthly = monthlyProtectedSales;
        previousYearly = yearlyProtectedSales;
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
        agent: 'Piki AI assistant',
        stock_list: 'Stock list',
        transfers: 'Transfers',
        branches: 'Branches',
        audit_logs: 'Audit logs',
        proactive_piki: 'Proactive Piki',
        excel_import: 'Excel imports',
        etims: 'KRA eTIMS',
        mpesa: 'M-Pesa integration',
        public_catalog: 'Public catalog',
        customer_accounts: 'Customer accounts'
    };

    const sellingModeLabels = {
        products: 'Products',
        services: 'Services',
        combo: 'Products + services'
    };

    function moneyFromMinor(amountMinor, currency) {
        const amount = Number(amountMinor || 0) / 100;
        const isZeroDecimal = ['KES', 'UGX', 'TZS', 'NGN'].includes(String(currency || '').toUpperCase());
        return new Intl.NumberFormat('en', {
            style: 'currency',
            currency: currency || 'KES',
            minimumFractionDigits: isZeroDecimal ? 0 : 2,
            maximumFractionDigits: isZeroDecimal ? 0 : 2
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

    function renderMarkets(markets, selectedMarket) {
        if (!pricingMarket || !Array.isArray(markets) || markets.length === 0) {
            return;
        }
        pricingMarket.innerHTML = markets.map((market) => {
            const code = market.countryCode || 'GLOBAL';
            const label = market.label || code;
            const provider = market.providerLabel ? ` - ${market.providerLabel}` : '';
            return `<option value="${escapeHtml(code)}">${escapeHtml(label + provider)}</option>`;
        }).join('');
        const preferred = selectedMarket?.countryCode || markets[0].countryCode || 'KE';
        const matching = markets.find((m) => (m.countryCode || 'GLOBAL') === preferred);
        pricingMarket.value = matching
            ? (matching.countryCode || 'GLOBAL')
            : (markets[0].countryCode || 'KE');
        pricingMarket.disabled = false;
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
            const staggerClass = index < 6 ? `stagger-${index + 1}` : '';
            return `
                <article class="pricing-card glass-card reveal ${staggerClass} ${isPopular ? 'pricing-card-popular' : ''}">
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

        observeReveals(pricingPlans);
    }

    async function detectVisitorCountry() {
        try {
            const response = await fetch('/api/geo/country');
            const body = await response.json().catch(() => ({}));
            const code = String(body.countryCode || '').trim().toUpperCase();
            if (/^[A-Z]{2}$/.test(code)) return code;
        } catch (_) {
            // Best-effort detection; fall back to Kenya pricing.
        }
        return 'KE';
    }

    async function loadPricingPlans(countryCode) {
        if (!pricingPlans) return;
        const resolvedCountry = countryCode || (await detectVisitorCountry());
        if (pricingSourceText) {
            pricingSourceText.textContent = 'Loading live plans...';
        }
        try {
            const response = await fetch(`/api/subscription/plans?countryCode=${encodeURIComponent(resolvedCountry)}`);
            const body = await response.json().catch(() => ({}));
            if (!response.ok || body.ok !== true) {
                throw new Error(body.error || 'Could not load pricing plans.');
            }
            renderMarkets(body.markets || [], body.selectedMarket);
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

    // Observe static reveal elements now that the observer is ready
    observeReveals(document);
});

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

// --------------------------------------------------------------------------
// 4. Testimonials Slider carousel
// --------------------------------------------------------------------------
let currentSlideIndex = 0;
const slides = document.querySelectorAll('.testimonial-slide');

function showSlide(index) {
    if (!slides.length) return;
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
// 6. Contact Lead Capture Form Submission Handler
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
    } catch (error) {
        if (errorMsg) {
            errorMsg.textContent = error.message;
            errorMsg.classList.remove('hidden');
        }
    } finally {
        submitButton.disabled = false;
        submitButton.innerHTML = originalButtonHtml;
    }
}
