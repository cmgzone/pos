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
    // 3. ROI Savings Calculator logic
    // ----------------------------------------------------------------------
    const salesSlider = document.getElementById('monthlySales');
    const cardShareSlider = document.getElementById('cardTxShare');
    const feeSlider = document.getElementById('competitorFee');

    const salesVal = document.getElementById('salesVal');
    const cardShareVal = document.getElementById('cardShareVal');
    const competitorFeeVal = document.getElementById('competitorFeeVal');

    const monthlySavingsVal = document.getElementById('monthlySavingsVal');
    const yearlySavingsVal = document.getElementById('yearlySavingsVal');

    function formatCurrency(amount) {
        return 'KES ' + Math.round(amount).toLocaleString();
    }

    function calculateSavings() {
        const sales = parseFloat(salesSlider.value);
        const cardShare = parseFloat(cardShareSlider.value) / 100;
        const competitorFee = parseFloat(feeSlider.value) / 100;

        // Digital payments are charged the competitor fee in standard POS systems
        const legacyDigitalFees = sales * cardShare * competitorFee;
        
        // Piki POS charges 0% transaction fees!
        // We'll simulate that we save exactly the full competitor transaction fee on digital channels
        const monthlySavings = legacyDigitalFees;
        const yearlySavings = monthlySavings * 12;

        // Update values in UI
        salesVal.textContent = formatCurrency(sales);
        cardShareVal.textContent = Math.round(cardShare * 100) + '%';
        competitorFeeVal.textContent = competitorFeeVal.textContent = (competitorFee * 100).toFixed(1) + '%';

        monthlySavingsVal.textContent = formatCurrency(monthlySavings);
        yearlySavingsVal.textContent = formatCurrency(yearlySavings);
    }

    if (salesSlider) {
        salesSlider.addEventListener('input', calculateSavings);
        cardShareSlider.addEventListener('input', calculateSavings);
        feeSlider.addEventListener('input', calculateSavings);
        calculateSavings(); // Initial execution
    }
});

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
    
    logSyncConsole('sqlite', `Added to local cart: ${name} (KES ${price})`);
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
    logSyncConsole('sqlite', `Removed from local cart: ${item.name}`);
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
        logSyncConsole('sqlite', 'Kopesha credit option chosen. Ready to log customer balance.');
    } else {
        kopeshaFields.classList.add('hidden');
        logSyncConsole('sqlite', `Payment selected: ${method.toUpperCase()}`);
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
    
    // Update local SQLite transaction rows count
    sqliteTransactionsCount++;
    document.getElementById('sqliteTxCount').textContent = `${sqliteTransactionsCount} Transactions`;
    logSyncConsole('sqlite', `COMPLETED checkout locally! Saved in SQLite with Transaction ID: ${txId}`);
    
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
        
        logSyncConsole('sqlite', `Registered customer balance: Debited KES ${totalVal} to ${customerName}`);
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
        
        logSyncConsole('sqlite', `Transaction ${txId} queued locally for sync. Waiting for internet connection...`);
    } else {
        receiptStatusText.className = 'receipt-status-badge online';
        receiptStatusText.textContent = 'CLOUD SYNCED TRANSACTION';
        
        // Sync instantly
        neonTransactionsCount++;
        document.getElementById('neonTxCount').textContent = `${neonTransactionsCount} Transactions`;
        logSyncConsole('neon', `Synced successfully! Committed Transaction ID: ${txId} to Neon Postgres Cloud.`);
    }
    
    // Display receipt
    receiptPreview.classList.remove('hidden');
    
    // Clear simulator cart
    simulatorCart = [];
    renderCart();
}

function triggerBackgroundSync() {
    if (offlineTxQueue.length === 0) {
        logSyncConsole('system', 'Database is currently fully synchronized.');
        return;
    }
    
    logSyncConsole('system', `Background worker found ${offlineTxQueue.length} pending transaction(s). Synergizing with Express Sync API...`);
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
            logSyncConsole('neon', `Sync complete! SQLite ID ${tx.id} committed to Neon Postgres Cloud (Cursor rev: ${neonTransactionsCount}).`);
        }
        
        if (neonCloudStatus) {
            neonCloudStatus.textContent = 'SYNCED';
            neonCloudStatus.className = 'badge';
        }
        logSyncConsole('success', 'SQLite and Neon databases are 100% in sync!');
        
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
function handleFormSubmit(event) {
    event.preventDefault();
    
    const form = document.getElementById('contactForm');
    const successMsg = document.getElementById('formSuccess');
    
    form.classList.add('hidden');
    successMsg.classList.remove('hidden');
    
    const name = document.getElementById('contactName').value;
    logSyncConsole('system', `New store demo requested by: ${name}. Welcome credentials generated.`);
}
