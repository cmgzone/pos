(() => {
  const byId = (id) => document.getElementById(id);
  const escapeHtml = (value) => String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');

  window.addEventListener('DOMContentLoaded', () => {
    window.lucide?.createIcons();
    byId('year').textContent = new Date().getFullYear();

    const menuButton = byId('menuButton');
    const siteNav = byId('siteNav');
    menuButton?.addEventListener('click', () => {
      const isOpen = siteNav.classList.toggle('is-open');
      menuButton.setAttribute('aria-expanded', String(isOpen));
      menuButton.setAttribute('aria-label', isOpen ? 'Close navigation' : 'Open navigation');
      menuButton.innerHTML = `<i data-lucide="${isOpen ? 'x' : 'menu'}"></i>`;
      window.lucide?.createIcons({ nodes: [menuButton] });
    });
    siteNav?.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => {
      siteNav.classList.remove('is-open');
      menuButton?.setAttribute('aria-expanded', 'false');
    }));

    const revealObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      });
    }, { threshold: 0.14 });
    document.querySelectorAll('[data-reveal]').forEach((element) => revealObserver.observe(element));

    document.querySelectorAll('.faq-item button').forEach((button) => {
      button.addEventListener('click', () => {
        const item = button.closest('.faq-item');
        const willOpen = !item.classList.contains('is-open');
        document.querySelectorAll('.faq-item').forEach((other) => {
          other.classList.remove('is-open');
          other.querySelector('button').setAttribute('aria-expanded', 'false');
        });
        item.classList.toggle('is-open', willOpen);
        button.setAttribute('aria-expanded', String(willOpen));
      });
    });

    setupContactForm();
    setupPlanCtas(document);
    loadReleases();
    loadPricingPlans();
    setupHeroFlow();
  });

  function setupContactForm() {
    const form = byId('contactForm');
    const message = byId('formMessage');
    if (!form || !message) return;
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const submit = form.querySelector('button[type="submit"]');
      const original = submit.innerHTML;
      message.textContent = '';
      message.classList.remove('is-error');
      submit.disabled = true;
      submit.innerHTML = 'Sending request...';
      try {
        const response = await fetch('/api/public/demo-requests', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            fullName: byId('contactName').value.trim(),
            email: byId('contactEmail').value.trim(),
            storeType: byId('storeType').value,
            message: byId('contactMessage').value.trim(),
          }),
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok || body.ok === false) throw new Error(body.error || 'Your request could not be sent. Please try again.');
        form.reset();
        message.textContent = 'Thanks. The Piki team will be in touch shortly.';
      } catch (error) {
        message.textContent = error.message || 'Your request could not be sent. Please try again.';
        message.classList.add('is-error');
      } finally {
        submit.disabled = false;
        submit.innerHTML = original;
        window.lucide?.createIcons({ nodes: [submit] });
      }
    });
  }

  function setupPlanCtas(root) {
    root.querySelectorAll('.plan-cta[data-plan]').forEach((cta) => {
      cta.addEventListener('click', () => {
        const message = byId('contactMessage');
        if (message) message.value = `I would like setup help with the ${cta.dataset.plan} plan.`;
      });
    });
  }

  async function loadReleases() {
    const setReleaseUnavailable = (platform, message = 'Not available yet') => {
      const link = document.querySelector(`[data-release="${platform}"]`);
      const meta = document.querySelector(`[data-release-meta="${platform}"]`);
      if (link) {
        link.removeAttribute('href');
        link.removeAttribute('download');
        link.classList.add('is-disabled');
        link.setAttribute('aria-disabled', 'true');
        link.setAttribute('tabindex', '-1');
        link.innerHTML = `Release not available <i data-lucide="circle-alert"></i>`;
        window.lucide?.createIcons({ nodes: [link] });
      }
      if (meta) meta.textContent = message;
    };

    const setReleaseAvailable = (platform, release) => {
      const link = document.querySelector(`[data-release="${platform}"]`);
      const meta = document.querySelector(`[data-release-meta="${platform}"]`);
      if (!link || !release.url) return setReleaseUnavailable(platform);
      link.href = release.url;
      link.setAttribute('download', '');
      link.classList.remove('is-disabled');
      link.removeAttribute('aria-disabled');
      link.removeAttribute('tabindex');
      link.innerHTML = `${link.dataset.readyLabel} <i data-lucide="download"></i>`;
      window.lucide?.createIcons({ nodes: [link] });
      if (meta) {
        meta.textContent = release.version
          ? `Version ${String(release.version).replace(/^v/i, '')}`
          : 'Ready to download';
      }
    };

    try {
      const response = await fetch('/api/app/version', { headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error('Release service unavailable');
      const body = await response.json();
      const data = body?.data || body;
      const releases = {
        windows: { url: data.windowsUrl, version: data.windowsVersion },
        android: { url: data.androidUrl || data.apkUrl, version: data.androidVersion || data.latestVersion },
      };
      Object.entries(releases).forEach(([platform, release]) => setReleaseAvailable(platform, release));
    } catch (_) {
      setReleaseUnavailable('windows', 'Check back for the next Windows release.');
      setReleaseUnavailable('android', 'Check back for the next Android release.');
    }
  }

  function priceFromMinor(price) {
    const amount = Number(price?.amountMinor || 0) / 100;
    if (!amount) return 'Free';
    return new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency: price.currency || 'KES',
      maximumFractionDigits: 0,
    }).format(amount);
  }

  async function loadPricingPlans(countryCode = 'KE') {
    const plansRoot = byId('pricingPlans');
    const marketSelect = byId('pricingMarket');
    const source = byId('pricingSource');
    if (!plansRoot || !marketSelect || !source) return;
    try {
      const response = await fetch(`/api/subscription/plans?countryCode=${encodeURIComponent(countryCode)}`);
      const body = await response.json().catch(() => ({}));
      if (!response.ok || body.ok !== true || !Array.isArray(body.plans) || !body.plans.length) throw new Error('No active plans');
      const markets = Array.isArray(body.markets) ? body.markets : [];
      marketSelect.innerHTML = markets.map((market) => `<option value="${escapeHtml(market.countryCode || 'KE')}">${escapeHtml(market.label || market.countryCode || 'Kenya')}</option>`).join('') || '<option value="KE">Kenya</option>';
      marketSelect.value = body.selectedMarket?.countryCode || countryCode;
      marketSelect.disabled = false;
      marketSelect.onchange = () => loadPricingPlans(marketSelect.value);
      plansRoot.innerHTML = body.plans.slice(0, 3).map((plan, index) => {
        const features = (plan.features || []).slice(0, 4);
        const price = plan.price ? priceFromMinor(plan.price) : 'Talk to us';
        const planName = plan.name || 'this plan';
        return `<article class="plan-card ${index === 1 ? 'plan-card-featured' : ''}">
          <p class="plan-code">${escapeHtml(plan.code || 'Piki plan')}</p>
          <h3>${escapeHtml(plan.name || 'Piki POS')}</h3>
          <p class="plan-price">${escapeHtml(price)}</p>
          ${features.length ? `<ul class="plan-features">${features.map((feature) => `<li>${escapeHtml(feature.replace(/_/g, ' '))}</li>`).join('')}</ul>` : `<p class="plan-description">${escapeHtml(plan.description || 'Built around your business.')}</p>`}
          <a class="plan-cta" href="#contact" data-plan="${escapeHtml(planName)}">Plan with Piki <i data-lucide="arrow-down-right"></i></a>
        </article>`;
      }).join('');
      window.lucide?.createIcons({ nodes: [plansRoot] });
      setupPlanCtas(plansRoot);
      source.textContent = `Showing current pricing for ${body.selectedMarket?.label || countryCode}.`;
    } catch (_) {
      source.textContent = 'Pricing updates are available from the Piki team.';
    }
  }

  function setupHeroFlow() {
    const flow = byId('heroFlow');
    const replay = byId('flowReplay');
    if (!flow || !replay) return;
    const stages = [
      { key: 'scan', number: '01', title: 'Open the counter', detail: 'Keep the next sale and every essential tool within reach.' },
      { key: 'review', number: '02', title: 'Read the day', detail: 'See sales, activity, and the next thing that needs attention.' },
      { key: 'complete', number: '03', title: 'Move between modules', detail: 'Stock, customers, payments, and selling remain connected.' },
    ];
    const number = byId('flowStepNumber');
    const title = byId('flowStepTitle');
    const detail = byId('flowStepDetail');
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let current = 0;
    let timer;
    const renderStage = () => {
      const stage = stages[current];
      flow.dataset.stage = stage.key;
      number.textContent = stage.number;
      title.textContent = stage.title;
      detail.textContent = stage.detail;
    };
    const advance = () => {
      current = (current + 1) % stages.length;
      renderStage();
    };
    const stop = () => window.clearInterval(timer);
    const play = () => {
      stop();
      if (!reducedMotion) timer = window.setInterval(advance, 3600);
    };
    replay.addEventListener('click', () => {
      current = 0;
      renderStage();
      play();
    });
    flow.addEventListener('pointerenter', stop);
    flow.addEventListener('pointerleave', play);
    renderStage();
    play();
  }
})();
