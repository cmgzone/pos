const crypto = require('crypto');

const STOREFRONT_THEME_PRESETS = Object.freeze({
  studio: Object.freeze({
    label: 'Studio',
    description: 'A polished dark storefront with generous product imagery.',
    design: Object.freeze({
      backgroundColor: '#100f0d',
      textColor: '#f5f3ef',
      mutedColor: '#9a958c',
      surfaceColor: '#181614',
      surfaceElevatedColor: '#211f1c',
      borderColor: '#34312c',
      accentColor: '#f0ead6',
      fontFamily: 'modern',
      heroStyle: 'cover',
      cardStyle: 'bordered',
      imageRatio: 'portrait',
      density: 'comfortable',
      cornerStyle: 'rounded',
    }),
  }),
  minimal: Object.freeze({
    label: 'Minimal',
    description: 'A bright, clean layout that keeps attention on the catalogue.',
    design: Object.freeze({
      backgroundColor: '#f8fafc',
      textColor: '#111827',
      mutedColor: '#64748b',
      surfaceColor: '#ffffff',
      surfaceElevatedColor: '#f1f5f9',
      borderColor: '#e2e8f0',
      accentColor: '#111827',
      fontFamily: 'inter',
      heroStyle: 'minimal',
      cardStyle: 'minimal',
      imageRatio: 'square',
      density: 'comfortable',
      cornerStyle: 'soft',
    }),
  }),
  warm: Object.freeze({
    label: 'Warm',
    description: 'Friendly earth tones for restaurants, makers, and local shops.',
    design: Object.freeze({
      backgroundColor: '#fff8ef',
      textColor: '#3d2417',
      mutedColor: '#8a6250',
      surfaceColor: '#fffdf9',
      surfaceElevatedColor: '#f8ead9',
      borderColor: '#ead4bd',
      accentColor: '#c65d36',
      fontFamily: 'serif',
      heroStyle: 'cover',
      cardStyle: 'elevated',
      imageRatio: 'landscape',
      density: 'comfortable',
      cornerStyle: 'rounded',
    }),
  }),
  fresh: Object.freeze({
    label: 'Fresh',
    description: 'An energetic, modern theme for services and growing brands.',
    design: Object.freeze({
      backgroundColor: '#f0fdfa',
      textColor: '#12332f',
      mutedColor: '#527a75',
      surfaceColor: '#ffffff',
      surfaceElevatedColor: '#dff7f1',
      borderColor: '#b8e5dc',
      accentColor: '#0f9f8e',
      fontFamily: 'rounded',
      heroStyle: 'split',
      cardStyle: 'elevated',
      imageRatio: 'square',
      density: 'comfortable',
      cornerStyle: 'pill',
    }),
  }),
  portfolio: Object.freeze({
    label: 'Portfolio',
    description: 'An editorial presentation for creative studios, collections, and visual work.',
    design: Object.freeze({
      backgroundColor: '#e9e5dc',
      textColor: '#10201d',
      mutedColor: '#59665f',
      surfaceColor: '#f7f3eb',
      surfaceElevatedColor: '#d8d3c8',
      borderColor: '#c9c3b7',
      accentColor: '#c45a00',
      fontFamily: 'merriweather',
      heroStyle: 'split',
      cardStyle: 'minimal',
      imageRatio: 'landscape',
      density: 'comfortable',
      cornerStyle: 'sharp',
    }),
  }),
  bold: Object.freeze({
    label: 'Bold',
    description: 'High contrast presentation for promotions and statement brands.',
    design: Object.freeze({
      backgroundColor: '#170815',
      textColor: '#fff3fb',
      mutedColor: '#c8a8bd',
      surfaceColor: '#241020',
      surfaceElevatedColor: '#35172f',
      borderColor: '#5a2b4e',
      accentColor: '#ff4aa2',
      fontFamily: 'modern',
      heroStyle: 'split',
      cardStyle: 'elevated',
      imageRatio: 'portrait',
      density: 'compact',
      cornerStyle: 'soft',
    }),
  }),
});

const THEME_ENUMS = Object.freeze({
  fontFamily: new Set(['inter', 'modern', 'serif', 'rounded', 'system', 'poppins', 'playfair', 'montserrat', 'nunito', 'oswald', 'merriweather']),
  headingFontFamily: new Set(['inter', 'modern', 'serif', 'rounded', 'system', 'poppins', 'playfair', 'montserrat', 'nunito', 'oswald', 'merriweather']),
  bodyFontFamily: new Set(['inter', 'modern', 'serif', 'rounded', 'system', 'poppins', 'playfair', 'montserrat', 'nunito', 'oswald', 'merriweather']),
  heroStyle: new Set(['cover', 'split', 'minimal']),
  cardStyle: new Set(['bordered', 'elevated', 'minimal']),
  imageRatio: new Set(['square', 'portrait', 'landscape']),
  density: new Set(['comfortable', 'compact']),
  cornerStyle: new Set(['sharp', 'soft', 'rounded', 'pill']),
  headingScale: new Set(['compact', 'balanced', 'display']),
  contentWidth: new Set(['compact', 'standard', 'wide', 'full']),
  sectionSpacing: new Set(['tight', 'standard', 'airy']),
  buttonStyle: new Set(['solid', 'outline', 'soft']),
  navigationStyle: new Set(['minimal', 'centered', 'expanded']),
  iconStyle: new Set(['plain', 'boxed', 'circle']),
  motionStyle: new Set(['none', 'subtle', 'expressive']),
  catalogLayout: new Set(['topbar', 'sidebar']),
});

const STOREFRONT_SECTION_TYPES = new Set([
  'announcement',
  'hero',
  'categoryShowcase',
  'featuredProducts',
  'promoBanner',
  'benefits',
  'story',
  'richText',
  'faq',
  'gallery',
  'video',
  'catalog',
  'contact',
]);
const STOREFRONT_SECTION_STYLES = new Set([
  'default',
  'surface',
  'accent',
  'contrast',
]);
const STOREFRONT_SECTION_ACTIONS = new Set([
  'none',
  'catalog',
  'whatsapp',
  'trackOrder',
]);
const STOREFRONT_SECTION_ALIGNMENTS = new Set(['left', 'center', 'right']);
const STOREFRONT_SECTION_WIDTHS = new Set(['narrow', 'contained', 'wide', 'full']);
const STOREFRONT_SECTION_SPACING = new Set(['none', 'compact', 'comfortable', 'spacious']);
const STOREFRONT_IMAGE_POSITIONS = new Set(['left', 'right', 'top', 'background']);
const STOREFRONT_PRODUCT_SOURCES = new Set(['featured', 'all', 'category']);
const STOREFRONT_BENEFIT_ICONS = new Set([
  'sparkles',
  'shield',
  'truck',
  'clock',
  'heart',
  'message',
  'star',
]);

const CHECKOUT_PAYMENT_METHODS = new Set(['manual', 'mpesa']);
const CHECKOUT_FULFILLMENT_METHODS = new Set(['pickup', 'delivery']);
const STOREFRONT_TYPES = new Set(['retail', 'services', 'restaurant']);

async function ensureStorefrontThemeSchema(target) {
  await run(target, `
    CREATE TABLE IF NOT EXISTS storefront_themes (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      storefront_type text NOT NULL DEFAULT 'retail',
      name text NOT NULL,
      preset text NOT NULL DEFAULT 'studio',
      design_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      checkout_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      source text NOT NULL DEFAULT 'manual',
      is_published boolean NOT NULL DEFAULT false,
      created_by text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      published_at timestamptz
    )
  `);
  await run(target, `
    CREATE INDEX IF NOT EXISTS idx_storefront_themes_business_scope
      ON storefront_themes (business_id, branch_id, storefront_type, updated_at DESC)
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_themes_one_published
      ON storefront_themes (business_id, branch_id, storefront_type)
      WHERE is_published = true
  `);
}

function storefrontThemePresets() {
  return Object.entries(STOREFRONT_THEME_PRESETS).map(([id, value]) => ({
    id,
    label: value.label,
    description: value.description,
    design: { ...value.design },
  }));
}

function defaultStorefrontTheme({
  storefrontType = 'retail',
  brandColor = null,
  branchId = 'main_branch',
} = {}) {
  const cleanType = normalizeStorefrontType(storefrontType);
  const typePreset = cleanType === 'restaurant' ? 'warm' : cleanType === 'services' ? 'fresh' : 'studio';
  const base = presetStorefrontTheme(typePreset, { storefrontType: cleanType, brandColor });
  return {
    id: null,
    branchId: normalizeBranchId(branchId),
    storefrontType: cleanType,
    name: 'Piki default',
    preset: typePreset,
    design: base.design,
    sections: defaultStorefrontSections({ storefrontType: cleanType }),
    checkout: normalizeStorefrontCheckout({}, {}),
    source: 'system',
    isPublished: true,
    createdBy: null,
    createdAt: null,
    updatedAt: null,
    publishedAt: null,
  };
}

function presetStorefrontTheme(preset, { storefrontType = 'retail', brandColor = null } = {}) {
  const cleanPreset = normalizePreset(preset);
  const cleanType = normalizeStorefrontType(storefrontType);
  const presetValue = STOREFRONT_THEME_PRESETS[cleanPreset];
  const design = { ...presetValue.design };
  const cleanBrandColor = normalizeColor(brandColor, null);
  if (cleanBrandColor) design.accentColor = cleanBrandColor;

  if (cleanPreset === 'studio' && !cleanBrandColor) {
    if (cleanType === 'services') {
      Object.assign(design, {
        backgroundColor: '#091820',
        textColor: '#e9f7f5',
        mutedColor: '#91adaa',
        surfaceColor: '#0e252d',
        surfaceElevatedColor: '#13313a',
        borderColor: '#29434a',
        accentColor: '#bcebe4',
      });
    } else if (cleanType === 'restaurant') {
      Object.assign(design, {
        backgroundColor: '#1b0d09',
        textColor: '#fff4e8',
        mutedColor: '#c6a99a',
        surfaceColor: '#27130d',
        surfaceElevatedColor: '#351a11',
        borderColor: '#583126',
        accentColor: '#f2c185',
      });
    }
  }
  return { preset: cleanPreset, design };
}

function normalizeStorefrontThemeInput(input = {}, options = {}) {
  const raw = objectValue(input);
  const existing = options.existing || null;
  const storefrontType = normalizeStorefrontType(
    raw.storefrontType ?? raw.storefront_type ?? existing?.storefrontType ?? options.storefrontType,
  );
  const branchId = normalizeBranchId(
    raw.branchId ?? raw.branch_id ?? existing?.branchId ?? options.branchId,
  );
  const preset = normalizePreset(raw.preset ?? existing?.preset);
  const presetValue = presetStorefrontTheme(preset, {
    storefrontType,
    brandColor: options.brandColor,
  });
  const designFallback = existing?.design || presetValue.design;
  const sectionsFallback =
    existing?.sections || defaultStorefrontSections({ storefrontType });
  const checkoutFallback = existing?.checkout || normalizeStorefrontCheckout({}, {});
  const name = limitText(raw.name ?? existing?.name ?? STOREFRONT_THEME_PRESETS[preset].label, 80);
  if (!name) throw createError(400, 'Theme name is required.');

  return {
    branchId,
    storefrontType,
    name,
    preset,
    design: normalizeStorefrontThemeDesign(
      raw.design ?? raw.design_json ?? raw,
      designFallback,
    ),
    sections: normalizeStorefrontThemeSections(
      raw.sections ?? raw.design?.sections ?? raw.design_json?.sections,
      sectionsFallback,
      { storefrontType },
    ),
    checkout: normalizeStorefrontCheckout(
      raw.checkout ?? raw.checkout_json ?? {},
      checkoutFallback,
    ),
    source: normalizeThemeSource(raw.source ?? existing?.source),
  };
}

function normalizeStorefrontThemeDesign(input = {}, fallback = {}) {
  const raw = objectValue(input);
  const base = objectValue(fallback);
  const color = (key, aliases = []) => {
    const value = firstDefined(raw, [key, ...aliases]);
    return normalizeColor(value, normalizeColor(base[key], '#111827'));
  };
  const enumValue = (key, aliases = []) => {
    const value = normalizeText(firstDefined(raw, [key, ...aliases]))?.toLowerCase();
    if (value && THEME_ENUMS[key].has(value)) return value;
    const fallbackValue = normalizeText(firstDefined(base, [key, ...aliases]))?.toLowerCase();
    return THEME_ENUMS[key].has(fallbackValue) ? fallbackValue : [...THEME_ENUMS[key]][0];
  };

  return {
    backgroundColor: color('backgroundColor', ['background_color', 'background']),
    textColor: color('textColor', ['text_color', 'foregroundColor', 'foreground_color']),
    mutedColor: color('mutedColor', ['muted_color']),
    surfaceColor: color('surfaceColor', ['surface_color']),
    surfaceElevatedColor: color('surfaceElevatedColor', ['surface_elevated_color']),
    borderColor: color('borderColor', ['border_color']),
    accentColor: color('accentColor', ['accent_color', 'primaryColor', 'primary_color']),
    fontFamily: enumValue('fontFamily', ['font_family', 'font']),
    headingFontFamily: enumValue('headingFontFamily', ['heading_font_family', 'displayFont', 'fontFamily', 'font_family', 'font']),
    bodyFontFamily: enumValue('bodyFontFamily', ['body_font_family', 'fontFamily', 'font_family', 'font']),
    heroStyle: enumValue('heroStyle', ['hero_style']),
    cardStyle: enumValue('cardStyle', ['card_style']),
    imageRatio: enumValue('imageRatio', ['image_ratio']),
    density: enumValue('density'),
    cornerStyle: enumValue('cornerStyle', ['corner_style', 'corners']),
    headingScale: enumValue('headingScale', ['heading_scale']),
    contentWidth: enumValue('contentWidth', ['content_width']),
    sectionSpacing: enumValue('sectionSpacing', ['section_spacing']),
    buttonStyle: enumValue('buttonStyle', ['button_style']),
    navigationStyle: enumValue('navigationStyle', ['navigation_style', 'navStyle']),
    iconStyle: enumValue('iconStyle', ['icon_style']),
    motionStyle: enumValue('motionStyle', ['motion_style', 'motion']),
    catalogLayout: enumValue('catalogLayout', [
      'catalog_layout',
      'categoryLayout',
      'category_layout',
      'catalogNavigation',
    ]),
    productColumns: clampInteger(raw.productColumns ?? raw.product_columns ?? base.productColumns, 2, 5, 4),
  };
}

function defaultStorefrontSections({ storefrontType = 'retail' } = {}) {
  const cleanType = normalizeStorefrontType(storefrontType);
  return normalizeStorefrontThemeSections(
    defaultStorefrontSectionBlueprints(cleanType),
    [],
    { storefrontType: cleanType },
  );
}

function defaultStorefrontSectionBlueprints(storefrontType) {
  const isServices = storefrontType === 'services';
  const isRestaurant = storefrontType === 'restaurant';
  const noun = isServices ? 'services' : isRestaurant ? 'menu' : 'collection';
  return [
    {
      id: 'welcome',
      type: 'announcement',
      style: 'accent',
      text: isServices
        ? 'Book online in a few simple steps.'
        : isRestaurant
          ? 'Order ahead for pickup or delivery.'
          : 'Shop online for pickup or delivery.',
    },
    {
      id: 'hero',
      type: 'hero',
      style: 'default',
      eyebrow: isServices ? 'Appointments made simple' : isRestaurant ? 'Fresh today' : 'Welcome',
      title: isServices
        ? 'Make time for what matters'
        : isRestaurant
          ? 'Made fresh. Ready when you are.'
          : 'Find something worth bringing home',
      body: isServices
        ? 'Explore available services and request the time that works for you.'
        : `Explore our ${noun}, choose what you love, and order in minutes.`,
      buttonLabel: isServices ? 'Browse services' : isRestaurant ? 'View menu' : 'Shop now',
      buttonAction: 'catalog',
      secondaryButtonLabel: '',
      secondaryButtonAction: 'none',
      alignment: 'left',
      showImage: true,
    },
    {
      id: 'discover',
      type: 'categoryShowcase',
      style: 'surface',
      eyebrow: 'Discover',
      title: isServices ? 'Find the right service' : isRestaurant ? 'Choose your favourites' : 'Shop by category',
      body: `Explore the ${noun} in the way that suits you.`,
    },
    {
      id: 'featured',
      type: 'featuredProducts',
      style: 'default',
      eyebrow: 'Popular now',
      title: isServices ? 'Recommended services' : isRestaurant ? 'Customer favourites' : 'Featured picks',
      body: 'A quick look at what customers choose most.',
      source: 'featured',
      category: '',
      limit: 4,
    },
    {
      id: 'catalog',
      type: 'catalog',
      style: 'default',
      eyebrow: isServices ? 'All services' : isRestaurant ? 'Full menu' : 'The store',
      title: isServices ? 'Choose a service' : isRestaurant ? 'Order from the menu' : 'Browse the store',
      body: '',
    },
    {
      id: 'support',
      type: 'contact',
      style: 'surface',
      eyebrow: 'Need help?',
      title: 'Talk to the team',
      body: 'Ask a question before placing your order and we will help you choose.',
      buttonLabel: 'Chat on WhatsApp',
      buttonAction: 'whatsapp',
      alignment: 'center',
    },
  ];
}

function normalizeStorefrontThemeSections(input, fallback = [], options = {}) {
  const storefrontType = normalizeStorefrontType(options.storefrontType);
  const requireCatalog = options.requireCatalog !== false;
  const maxSections = clampInteger(options.maxSections, 1, 24, 12);
  const requested = Array.isArray(input) ? input : [];
  const fallbackSections = Array.isArray(fallback) ? fallback : [];
  const candidates = requested.length
    ? requested
    : fallbackSections.length
      ? fallbackSections
      : defaultStorefrontSectionBlueprints(storefrontType);
  const normalized = [];
  const ids = new Set();
  let hasCatalog = false;

  for (const [index, candidateValue] of candidates.slice(0, maxSections).entries()) {
    const candidate = objectValue(candidateValue);
    const type = normalizeStorefrontSectionType(candidate.type);
    if (!STOREFRONT_SECTION_TYPES.has(type)) continue;
    if (type === 'catalog' && hasCatalog) continue;
    const fallbackSection = objectValue(
      fallbackSections.find((section) => section?.id === candidate.id) ||
        fallbackSections.find(
          (section) => normalizeStorefrontSectionType(section?.type) === type,
        ) ||
        defaultStorefrontSectionBlueprints(storefrontType).find(
          (section) => section.type === type,
        ),
    );
    const section = normalizeStorefrontSection(candidate, fallbackSection, {
      index,
      type,
    });
    let id = section.id;
    while (ids.has(id)) id = `${section.id}-${ids.size + 1}`;
    section.id = id;
    ids.add(id);
    normalized.push(section);
    if (type === 'catalog') hasCatalog = true;
  }

  if (requireCatalog && !hasCatalog) {
    const catalogFallback = defaultStorefrontSectionBlueprints(storefrontType).find(
      (section) => section.type === 'catalog',
    );
    normalized.push(
      normalizeStorefrontSection(catalogFallback, catalogFallback, {
        index: normalized.length,
        type: 'catalog',
      }),
    );
  }
  return normalized;
}

function normalizeStorefrontSection(raw, fallback, { index, type }) {
  const text = (key, maxLength, defaultValue = '') =>
    limitText(raw[key] ?? fallback[key] ?? defaultValue, maxLength) || '';
  const enumValue = (key, values, defaultValue) => {
    const value = normalizeText(raw[key] ?? fallback[key]);
    const match = [...values].find(
      (candidate) => normalizeEnumToken(candidate) === normalizeEnumToken(value),
    );
    return match || defaultValue;
  };
  const common = {
    id: normalizeSectionId(raw.id, `${type}-${index + 1}`),
    type,
    enabled: raw.enabled !== false,
    style: enumValue('style', STOREFRONT_SECTION_STYLES, 'default'),
    width: enumValue('width', STOREFRONT_SECTION_WIDTHS, 'contained'),
    spacing: enumValue('spacing', STOREFRONT_SECTION_SPACING, 'comfortable'),
    columns: clampInteger(raw.columns ?? fallback.columns, 1, 4, 3),
    imagePosition: enumValue(
      'imagePosition',
      STOREFRONT_IMAGE_POSITIONS,
      'right',
    ),
    icon: limitText(raw.icon ?? fallback.icon, 40) || '',
  };
  const heading = () => ({
    eyebrow: text('eyebrow', 50),
    title: text('title', 100),
    body: text('body', 360),
  });
  const action = (prefix = '') => {
    const labelKey = prefix ? `${prefix}ButtonLabel` : 'buttonLabel';
    const key = prefix ? `${prefix}ButtonAction` : 'buttonAction';
    return {
      [labelKey]: text(labelKey, 40),
      [key]: enumValue(key, STOREFRONT_SECTION_ACTIONS, 'none'),
    };
  };

  switch (type) {
    case 'announcement':
      return {
        ...common,
        text: text('text', 140, 'Order online with confidence.'),
        ...action(),
      };
    case 'hero':
      return {
        ...common,
        ...heading(),
        ...action(),
        ...action('secondary'),
        alignment: enumValue(
          'alignment',
          STOREFRONT_SECTION_ALIGNMENTS,
          'left',
        ),
        showImage: raw.showImage ?? fallback.showImage ?? true,
        imagePosition: enumValue(
          'imagePosition',
          STOREFRONT_IMAGE_POSITIONS,
          'background',
        ),
      };
    case 'categoryShowcase':
      return { ...common, ...heading() };
    case 'featuredProducts': {
      const source = enumValue(
        'source',
        STOREFRONT_PRODUCT_SOURCES,
        'featured',
      );
      return {
        ...common,
        ...heading(),
        source,
        category: source === 'category' ? text('category', 80) : '',
        limit: clampInteger(raw.limit ?? fallback.limit, 2, 12, 4),
      };
    }
    case 'promoBanner':
      return {
        ...common,
        ...heading(),
        ...action(),
        alignment: enumValue(
          'alignment',
          STOREFRONT_SECTION_ALIGNMENTS,
          'left',
        ),
      };
    case 'benefits': {
      const requestedItems = Array.isArray(raw.items) ? raw.items : fallback.items;
      const items = (Array.isArray(requestedItems) ? requestedItems : [])
        .slice(0, 4)
        .map((item) => {
          const value = objectValue(item);
          const icon = normalizeText(value.icon)?.toLowerCase();
          return {
            title: limitText(value.title, 60),
            body: limitText(value.body, 180),
            icon: STOREFRONT_BENEFIT_ICONS.has(icon) ? icon : 'sparkles',
          };
        })
        .filter((item) => item.title);
      return { ...common, ...heading(), items };
    }
    case 'story':
      return {
        ...common,
        ...heading(),
        alignment: enumValue(
          'alignment',
          STOREFRONT_SECTION_ALIGNMENTS,
          'left',
        ),
        showImage: raw.showImage ?? fallback.showImage ?? false,
      };
    case 'richText':
      return {
        ...common,
        ...heading(),
        content: text('content', 6000),
        alignment: enumValue(
          'alignment',
          STOREFRONT_SECTION_ALIGNMENTS,
          'left',
        ),
      };
    case 'faq': {
      const requestedItems = Array.isArray(raw.items) ? raw.items : fallback.items;
      const items = (Array.isArray(requestedItems) ? requestedItems : [])
        .slice(0, 12)
        .map((item) => {
          const value = objectValue(item);
          return {
            question: limitText(value.question, 180),
            answer: limitText(value.answer, 1000),
          };
        })
        .filter((item) => item.question && item.answer);
      return { ...common, ...heading(), items };
    }
    case 'gallery': {
      const requestedItems = Array.isArray(raw.items) ? raw.items : fallback.items;
      const items = (Array.isArray(requestedItems) ? requestedItems : [])
        .slice(0, 12)
        .map((item) => {
          const value = objectValue(item);
          return {
            imageUrl: normalizeHttpsUrl(value.imageUrl ?? value.url),
            alt: limitText(value.alt, 160) || '',
            caption: limitText(value.caption, 240) || '',
          };
        })
        .filter((item) => item.imageUrl);
      return { ...common, ...heading(), items };
    }
    case 'video':
      return {
        ...common,
        ...heading(),
        videoUrl: normalizeVideoUrl(raw.videoUrl ?? raw.url ?? fallback.videoUrl),
        caption: text('caption', 240),
      };
    case 'catalog':
      return { ...common, ...heading() };
    case 'contact':
      return {
        ...common,
        ...heading(),
        ...action(),
        alignment: enumValue(
          'alignment',
          STOREFRONT_SECTION_ALIGNMENTS,
          'center',
        ),
      };
    default:
      return common;
  }
}

function normalizeStorefrontCheckout(input = {}, fallback = {}) {
  const raw = objectValue(input);
  const base = objectValue(fallback);
  const requestedPayments = normalizeStringList(
    firstDefined(raw, ['paymentMethods', 'payment_methods']) ?? base.paymentMethods,
  ).filter((method) => CHECKOUT_PAYMENT_METHODS.has(method));
  const paymentMethods = requestedPayments.length ? requestedPayments : ['manual'];
  const requestedFulfillment = normalizeStringList(
    firstDefined(raw, ['fulfillmentMethods', 'fulfillment_methods']) ?? base.fulfillmentMethods,
  ).filter((method) => CHECKOUT_FULFILLMENT_METHODS.has(method));
  const fulfillmentMethods = requestedFulfillment.length
    ? requestedFulfillment
    : ['pickup', 'delivery'];
  const requestedDefault = normalizeText(
    firstDefined(raw, ['defaultPaymentMethod', 'default_payment_method']) ?? base.defaultPaymentMethod,
  )?.toLowerCase();

  return {
    paymentMethods,
    defaultPaymentMethod: paymentMethods.includes(requestedDefault) ? requestedDefault : paymentMethods[0],
    fulfillmentMethods,
    defaultFulfillmentMethod: fulfillmentMethods.includes(
      normalizeText(
        firstDefined(raw, ['defaultFulfillmentMethod', 'default_fulfillment_method']) ??
          base.defaultFulfillmentMethod,
      )?.toLowerCase(),
    )
      ? normalizeText(
          firstDefined(raw, ['defaultFulfillmentMethod', 'default_fulfillment_method']) ??
            base.defaultFulfillmentMethod,
        ).toLowerCase()
      : fulfillmentMethods[0],
    showDeliveryAddress: booleanValue(
      firstDefined(raw, ['showDeliveryAddress', 'show_delivery_address']),
      base.showDeliveryAddress ?? true,
    ),
    showOrderNote: booleanValue(
      firstDefined(raw, ['showOrderNote', 'show_order_note']),
      base.showOrderNote ?? true,
    ),
    showOrderTracking: booleanValue(
      firstDefined(raw, ['showOrderTracking', 'show_order_tracking']),
      base.showOrderTracking ?? true,
    ),
    requireCustomerName: true,
    requirePhone: true,
    checkoutTitle:
      limitText(firstDefined(raw, ['checkoutTitle', 'checkout_title']) ?? base.checkoutTitle, 60) ||
      'Checkout',
    checkoutButtonLabel:
      limitText(
        firstDefined(raw, ['checkoutButtonLabel', 'checkout_button_label', 'buttonLabel']) ??
          base.checkoutButtonLabel,
        40,
      ) || 'Place order',
    successMessage:
      limitText(firstDefined(raw, ['successMessage', 'success_message']) ?? base.successMessage, 180) ||
      'Your order has been received. The business will confirm it shortly.',
  };
}

function checkoutForActiveGateways(checkout, activeProviders = []) {
  const normalized = normalizeStorefrontCheckout(checkout, {});
  const active = new Set(normalizeStringList(activeProviders));
  const paymentMethods = normalized.paymentMethods.filter(
    (method) => method === 'manual' || active.has(method),
  );
  if (!paymentMethods.length) paymentMethods.push('manual');
  return {
    ...normalized,
    paymentMethods,
    defaultPaymentMethod: paymentMethods.includes(normalized.defaultPaymentMethod)
      ? normalized.defaultPaymentMethod
      : paymentMethods[0],
  };
}

async function listStorefrontThemes(target, businessId, options = {}) {
  await ensureStorefrontThemeSchema(target);
  const branchId = normalizeBranchId(options.branchId);
  const storefrontType = normalizeStorefrontType(options.storefrontType);
  const result = await run(
    target,
    `SELECT * FROM storefront_themes
     WHERE business_id = $1 AND branch_id = $2 AND storefront_type = $3
     ORDER BY is_published DESC, updated_at DESC, name ASC`,
    [businessId, branchId, storefrontType],
  );
  return result.rows.map(normalizeStorefrontThemeRow);
}

async function getStorefrontTheme(target, businessId, themeId) {
  await ensureStorefrontThemeSchema(target);
  const result = await run(
    target,
    'SELECT * FROM storefront_themes WHERE business_id = $1 AND id = $2 LIMIT 1',
    [businessId, normalizeThemeId(themeId)],
  );
  return result.rows.length ? normalizeStorefrontThemeRow(result.rows[0]) : null;
}

async function loadPublishedStorefrontTheme(target, businessId, options = {}) {
  await ensureStorefrontThemeSchema(target);
  const branchId = normalizeBranchId(options.branchId);
  const storefrontType = normalizeStorefrontType(options.storefrontType);
  const result = await run(
    target,
    `SELECT * FROM storefront_themes
     WHERE business_id = $1 AND branch_id = $2 AND storefront_type = $3
       AND is_published = true
     LIMIT 1`,
    [businessId, branchId, storefrontType],
  );
  if (result.rows.length) return normalizeStorefrontThemeRow(result.rows[0]);
  return defaultStorefrontTheme({
    branchId,
    storefrontType,
    brandColor: options.brandColor,
  });
}

async function createStorefrontTheme(target, businessId, input = {}, options = {}) {
  await ensureStorefrontThemeSchema(target);
  const normalized = normalizeStorefrontThemeInput(input, options);
  const id = crypto.randomUUID();
  const result = await run(
    target,
    `INSERT INTO storefront_themes (
       id, business_id, branch_id, storefront_type, name, preset,
       design_json, checkout_json, source, is_published, created_by,
       created_at, updated_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, false, $10, NOW(), NOW())
     RETURNING *`,
    [
      id,
      businessId,
      normalized.branchId,
      normalized.storefrontType,
      normalized.name,
      normalized.preset,
      JSON.stringify(storefrontThemeDesignForStorage(normalized)),
      JSON.stringify(normalized.checkout),
      normalized.source,
      options.createdBy || null,
    ],
  );
  return normalizeStorefrontThemeRow(result.rows[0]);
}

async function updateStorefrontTheme(target, businessId, themeId, input = {}, options = {}) {
  const existing = await getStorefrontTheme(target, businessId, themeId);
  if (!existing) throw createError(404, 'Theme was not found.');
  const normalized = normalizeStorefrontThemeInput(input, {
    ...options,
    existing,
    storefrontType: existing.storefrontType,
    branchId: existing.branchId,
  });
  const result = await run(
    target,
    `UPDATE storefront_themes
     SET name = $3, preset = $4, design_json = $5::jsonb,
         checkout_json = $6::jsonb, source = $7, updated_at = NOW()
     WHERE business_id = $1 AND id = $2
     RETURNING *`,
    [
      businessId,
      existing.id,
      normalized.name,
      normalized.preset,
      JSON.stringify(storefrontThemeDesignForStorage(normalized)),
      JSON.stringify(normalized.checkout),
      normalized.source,
    ],
  );
  return normalizeStorefrontThemeRow(result.rows[0]);
}

async function duplicateStorefrontTheme(target, businessId, themeId, input = {}, options = {}) {
  const existing = await getStorefrontTheme(target, businessId, themeId);
  if (!existing) throw createError(404, 'Theme was not found.');
  return createStorefrontTheme(
    target,
    businessId,
    {
      ...existing,
      name: limitText(input.name, 80) || `${existing.name} copy`,
      source: input.source || 'duplicate',
      isPublished: false,
    },
    { ...options, storefrontType: existing.storefrontType, branchId: existing.branchId },
  );
}

async function publishStorefrontTheme(target, businessId, themeId) {
  const theme = await getStorefrontTheme(target, businessId, themeId);
  if (!theme) throw createError(404, 'Theme was not found.');
  await run(
    target,
    `UPDATE storefront_themes
     SET is_published = false, updated_at = NOW()
     WHERE business_id = $1 AND branch_id = $2 AND storefront_type = $3
       AND is_published = true AND id <> $4`,
    [businessId, theme.branchId, theme.storefrontType, theme.id],
  );
  const result = await run(
    target,
    `UPDATE storefront_themes
     SET is_published = true, published_at = NOW(), updated_at = NOW()
     WHERE business_id = $1 AND id = $2
     RETURNING *`,
    [businessId, theme.id],
  );
  return normalizeStorefrontThemeRow(result.rows[0]);
}

async function deleteStorefrontTheme(target, businessId, themeId) {
  const theme = await getStorefrontTheme(target, businessId, themeId);
  if (!theme) throw createError(404, 'Theme was not found.');
  if (theme.isPublished) {
    throw createError(409, 'Publish another theme before deleting the live theme.');
  }
  await run(
    target,
    'DELETE FROM storefront_themes WHERE business_id = $1 AND id = $2',
    [businessId, theme.id],
  );
  return theme;
}

function normalizeStorefrontThemeRow(row) {
  const storedDesign = parseJson(row.design_json, {});
  const storefrontType = normalizeStorefrontType(row.storefront_type);
  return {
    id: row.id,
    branchId: normalizeBranchId(row.branch_id),
    storefrontType,
    name: normalizeText(row.name) || 'Theme',
    preset: normalizePreset(row.preset),
    design: normalizeStorefrontThemeDesign(storedDesign, {}),
    sections: normalizeStorefrontThemeSections(storedDesign.sections, [], {
      storefrontType,
    }),
    checkout: normalizeStorefrontCheckout(parseJson(row.checkout_json, {}), {}),
    source: normalizeThemeSource(row.source),
    isPublished: Boolean(row.is_published),
    createdBy: row.created_by || null,
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
    publishedAt: toIsoString(row.published_at),
  };
}

function normalizeStorefrontType(value) {
  const clean = normalizeText(value)?.toLowerCase();
  return STOREFRONT_TYPES.has(clean) ? clean : 'retail';
}

function normalizeBranchId(value) {
  return limitText(value, 120) || 'main_branch';
}

function normalizePreset(value) {
  const clean = normalizeText(value)?.toLowerCase();
  return Object.prototype.hasOwnProperty.call(STOREFRONT_THEME_PRESETS, clean)
    ? clean
    : 'studio';
}

function normalizeThemeSource(value) {
  const clean = normalizeText(value)?.toLowerCase().replace(/[^a-z0-9_]+/g, '_');
  return ['manual', 'ai', 'duplicate', 'import', 'system'].includes(clean) ? clean : 'manual';
}

function normalizeThemeId(value) {
  const clean = normalizeText(value);
  if (!clean || clean.length > 120) throw createError(400, 'Theme id is required.');
  return clean;
}

function storefrontThemeDesignForStorage(theme) {
  return {
    ...theme.design,
    sections: theme.sections,
  };
}

function normalizeStorefrontSectionType(value) {
  const token = normalizeEnumToken(value);
  return (
    [...STOREFRONT_SECTION_TYPES].find(
      (candidate) => normalizeEnumToken(candidate) === token,
    ) || null
  );
}

function normalizeEnumToken(value) {
  return normalizeText(value)?.toLowerCase().replace(/[^a-z0-9]+/g, '') || '';
}

function normalizeSectionId(value, fallback) {
  const clean = (limitText(value, 60) || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return clean || fallback;
}

function clampInteger(value, minimum, maximum, fallback) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, parsed));
}

function normalizeColor(value, fallback) {
  const clean = normalizeText(value);
  if (!clean) return fallback;
  const withHash = clean.startsWith('#') ? clean : `#${clean}`;
  return /^#[0-9a-f]{6}$/i.test(withHash) ? withHash.toLowerCase() : fallback;
}

function normalizeStringList(value) {
  const list = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.split(/[,|]/)
      : [];
  return [...new Set(list.map((item) => normalizeText(item)?.toLowerCase()).filter(Boolean))];
}

function firstDefined(source, keys) {
  for (const key of keys) {
    if (source[key] !== undefined && source[key] !== null) return source[key];
  }
  return undefined;
}

function booleanValue(value, fallback) {
  if (value == null) return Boolean(fallback);
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const clean = String(value).trim().toLowerCase();
  if (['true', 'yes', '1', 'on'].includes(clean)) return true;
  if (['false', 'no', '0', 'off'].includes(clean)) return false;
  return Boolean(fallback);
}

function objectValue(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  return parseJson(value, {});
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function limitText(value, maxLength) {
  const clean = normalizeText(value);
  return clean ? clean.slice(0, maxLength) : null;
}

function normalizeText(value) {
  if (value == null) return null;
  const clean = String(value).trim();
  return clean || null;
}

function normalizeHttpsUrl(value) {
  const clean = normalizeText(value);
  if (!clean) return null;
  try {
    const url = new URL(clean);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch (_) {
    return null;
  }
}

function normalizeVideoUrl(value) {
  const url = normalizeHttpsUrl(value);
  if (!url) return null;
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    if (host === 'youtu.be') {
      const id = parsed.pathname.split('/').filter(Boolean)[0];
      return id ? `https://www.youtube.com/embed/${encodeURIComponent(id)}` : null;
    }
    if (host === 'youtube.com' || host === 'www.youtube.com') {
      if (parsed.pathname.startsWith('/embed/')) return parsed.toString();
      const id = parsed.searchParams.get('v');
      return id ? `https://www.youtube.com/embed/${encodeURIComponent(id)}` : null;
    }
    if (host === 'vimeo.com' || host === 'www.vimeo.com') {
      const id = parsed.pathname.split('/').filter(Boolean)[0];
      return id && /^\d+$/.test(id)
        ? `https://player.vimeo.com/video/${id}`
        : null;
    }
    if (host === 'player.vimeo.com' && parsed.pathname.startsWith('/video/')) {
      return parsed.toString();
    }
  } catch (_) {
    return null;
  }
  return null;
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function run(target, sql, params = []) {
  if (typeof target === 'function') return target(sql, params);
  return target.query(sql, params);
}

module.exports = {
  CHECKOUT_PAYMENT_METHODS,
  STOREFRONT_THEME_PRESETS,
  checkoutForActiveGateways,
  createStorefrontTheme,
  defaultStorefrontTheme,
  defaultStorefrontSections,
  deleteStorefrontTheme,
  duplicateStorefrontTheme,
  ensureStorefrontThemeSchema,
  getStorefrontTheme,
  listStorefrontThemes,
  loadPublishedStorefrontTheme,
  normalizeStorefrontCheckout,
  normalizeStorefrontThemeDesign,
  normalizeStorefrontThemeInput,
  normalizeStorefrontThemeSections,
  normalizeStorefrontThemeRow,
  presetStorefrontTheme,
  publishStorefrontTheme,
  storefrontThemePresets,
  updateStorefrontTheme,
};
