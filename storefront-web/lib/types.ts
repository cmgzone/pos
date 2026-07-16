export interface BusinessBrand {
  logoUrl?: string | null;
  coverUrl?: string | null;
  coverUrls?: string[];
  primaryColor?: string | null;
  tagline?: string | null;
  description?: string | null;
}

export type StorefrontType = "retail" | "services" | "restaurant";
export type StorefrontAppearance = "light" | "dark";
export type StorefrontFontFamily =
  | "inter"
  | "modern"
  | "serif"
  | "rounded"
  | "system"
  | "poppins"
  | "playfair"
  | "montserrat"
  | "nunito"
  | "oswald"
  | "merriweather";

export interface Storefront {
  type: StorefrontType;
  label: string;
  title: string;
  description: string;
  browseLabel: string;
}

export interface StorefrontThemeDesign {
  backgroundColor: string;
  textColor: string;
  mutedColor: string;
  surfaceColor: string;
  surfaceElevatedColor: string;
  borderColor: string;
  accentColor: string;
  fontFamily: StorefrontFontFamily;
  headingFontFamily: StorefrontFontFamily;
  bodyFontFamily: StorefrontFontFamily;
  heroStyle: "cover" | "split" | "minimal";
  cardStyle: "bordered" | "elevated" | "minimal";
  imageRatio: "square" | "portrait" | "landscape";
  density: "comfortable" | "compact";
  cornerStyle: "sharp" | "soft" | "rounded" | "pill";
  headingScale: "compact" | "balanced" | "display";
  contentWidth: "compact" | "standard" | "wide" | "full";
  sectionSpacing: "tight" | "standard" | "airy";
  buttonStyle: "solid" | "outline" | "soft";
  navigationStyle: "minimal" | "centered" | "expanded";
  iconStyle: "plain" | "boxed" | "circle";
  motionStyle: "none" | "subtle" | "expressive";
  productColumns: number;
}

export type StorefrontSectionType =
  | "announcement"
  | "hero"
  | "categoryShowcase"
  | "featuredProducts"
  | "promoBanner"
  | "benefits"
  | "story"
  | "richText"
  | "faq"
  | "gallery"
  | "video"
  | "catalog"
  | "contact";

export type StorefrontSectionAction =
  | "none"
  | "catalog"
  | "whatsapp"
  | "trackOrder";

export interface StorefrontBenefit {
  title: string;
  body: string;
  icon: "sparkles" | "shield" | "truck" | "clock" | "heart" | "message" | "star";
}

export interface StorefrontFaqItem {
  question: string;
  answer: string;
}

export interface StorefrontGalleryItem {
  imageUrl: string;
  alt?: string;
  caption?: string;
}

export interface StorefrontSection {
  id: string;
  type: StorefrontSectionType;
  enabled: boolean;
  style: "default" | "surface" | "accent" | "contrast";
  width?: "narrow" | "contained" | "wide" | "full";
  spacing?: "none" | "compact" | "comfortable" | "spacious";
  columns?: number;
  imagePosition?: "left" | "right" | "top" | "background";
  icon?: string;
  eyebrow?: string;
  title?: string;
  body?: string;
  text?: string;
  buttonLabel?: string;
  buttonAction?: StorefrontSectionAction;
  secondaryButtonLabel?: string;
  secondaryButtonAction?: StorefrontSectionAction;
  alignment?: "left" | "center" | "right";
  showImage?: boolean;
  source?: "featured" | "all" | "category";
  category?: string;
  limit?: number;
  items?: Array<StorefrontBenefit | StorefrontFaqItem | StorefrontGalleryItem>;
  content?: string;
  videoUrl?: string | null;
  caption?: string;
}

export interface StorefrontPageLink {
  id: string;
  title: string;
  label: string;
  slug: string;
  pageType: string;
}

export interface StorefrontPage extends StorefrontPageLink {
  navigationLabel: string;
  showInNavigation: boolean;
  seoTitle: string;
  seoDescription: string;
  sections: StorefrontSection[];
  status: "draft" | "published" | "archived";
}

export interface StorefrontCheckoutSettings {
  paymentMethods: ("manual" | "mpesa")[];
  defaultPaymentMethod: "manual" | "mpesa";
  fulfillmentMethods: ("pickup" | "delivery")[];
  defaultFulfillmentMethod: "pickup" | "delivery";
  showDeliveryAddress: boolean;
  showOrderNote: boolean;
  showOrderTracking: boolean;
  checkoutTitle: string;
  checkoutButtonLabel: string;
  successMessage: string;
}

export interface StorefrontTheme {
  id?: string | null;
  branchId: string;
  storefrontType: StorefrontType;
  name: string;
  preset: string;
  design: StorefrontThemeDesign;
  sections: StorefrontSection[];
  checkout: StorefrontCheckoutSettings;
  source: string;
  isPublished: boolean;
}

export interface Branch {
  id: string;
  name: string;
}

export interface Business {
  id: string;
  name: string;
  countryCode: string;
  whatsappNumber?: string | null;
  brand: BusinessBrand;
  branches: Branch[];
  selectedBranch: Branch;
}

export interface ProductVariant {
  id: string;
  name: string;
  price: number;
  compareAtPrice?: number | null;
  stock?: number;
  available?: boolean;
}

export interface CatalogItem {
  id: string;
  name: string;
  price: number;
  compareAtPrice?: number | null;
  discountPercent?: number | null;
  promotionLabel?: string | null;
  stock: number;
  unit?: string;
  saleUnit?: string;
  stockUnit?: string;
  imageUrl?: string | null;
  imageUrls?: string[];
  brand?: string | null;
  description?: string | null;
  category?: string | null;
  showOnline?: boolean;
  isFeatured?: boolean;
  trackStock?: boolean;
  hasVariants?: boolean;
  updatedAt?: string;
  soldQty?: number;
  variants?: ProductVariant[];
  source?: "external_api" | string;
  externalCheckoutUrl?: string | null;
  durationMinutes?: number | null;
  itemType?: "product" | "service";
  type?: "product" | "service";
  productId?: string | null;
  serviceId?: string | null;
}

export interface StorefrontCampaign {
  id: string;
  branchId: string;
  storefrontType: StorefrontType;
  name: string;
  slug: string;
  eyebrow?: string | null;
  title: string;
  description?: string | null;
  badgeLabel?: string | null;
  buttonLabel: string;
  heroImageUrl?: string | null;
  productIds: string[];
  highlights: string[];
  startsAt?: string | null;
  endsAt?: string | null;
}

export interface Catalog {
  preview?: boolean;
  business: Business;
  storefront: Storefront;
  currency: string;
  currencyCode: string;
  theme: StorefrontTheme;
  checkout: StorefrontCheckoutSettings;
  campaign?: StorefrontCampaign | null;
  page?: StorefrontPage | null;
  pages?: StorefrontPageLink[];
  currencySymbol: string;
  currencyLabel: string;
  categories: string[];
  products: CatalogItem[];
  updatedAt?: string;
}

export interface CartItem {
  key: string;
  item: CatalogItem;
  variant?: ProductVariant;
  quantity: number;
}

export interface CustomerInfo {
  customerName: string;
  phone: string;
  deliveryAddress?: string;
  fulfillmentMethod?: "pickup" | "delivery";
  note?: string;
}

export interface OrderPayload {
  branchId: string;
  storefrontType?: StorefrontType;
  paymentMethod?: "manual" | "mpesa";
  customerName: string;
  phone: string;
  deliveryAddress?: string;
  fulfillmentMethod?: "pickup" | "delivery";
  note?: string;
  items: {
    itemType: "product" | "service";
    productId?: string;
    serviceId?: string;
    variantId?: string;
    quantity: number;
  }[];
}

export interface Order {
  id: string;
  orderNumber: string;
  status: string;
  subtotal: number;
  customerName: string;
  phone?: string;
  deliveryAddress?: string;
  fulfillmentMethod?: string;
  note?: string;
  paymentMethod?: string;
  paymentStatus?: string;
  deliveryStatus?: string;
  trackingCode?: string;
  createdAt: string;
  items: {
    productName: string;
  paymentRequestId?: string;
    quantity: number;
    unitPrice: number;
    lineTotal: number;
  }[];
}

export interface StorefrontBootstrap {
  businessId?: string;
  branchId?: string;
  business?: Business;
  catalog?: Catalog;
}

declare global {
  interface Window {
    __STOREFRONT__?: StorefrontBootstrap;
    __STOREFRONT_CATALOG__?: Catalog;
  }
}
