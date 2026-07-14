export interface BusinessBrand {
  logoUrl?: string | null;
  coverUrl?: string | null;
  coverUrls?: string[];
  primaryColor?: string | null;
  tagline?: string | null;
  description?: string | null;
}

export type StorefrontType = "retail" | "services" | "restaurant";

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
  fontFamily: "inter" | "modern" | "serif" | "rounded" | "system";
  heroStyle: "cover" | "split" | "minimal";
  cardStyle: "bordered" | "elevated" | "minimal";
  imageRatio: "square" | "portrait" | "landscape";
  density: "comfortable" | "compact";
  cornerStyle: "sharp" | "soft" | "rounded" | "pill";
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
  stock?: number;
  available?: boolean;
}

export interface CatalogItem {
  id: string;
  name: string;
  price: number;
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
  durationMinutes?: number | null;
  itemType?: "product" | "service";
  type?: "product" | "service";
  productId?: string | null;
  serviceId?: string | null;
}

export interface Catalog {
  business: Business;
  storefront: Storefront;
  currency: string;
  currencyCode: string;
  theme: StorefrontTheme;
  checkout: StorefrontCheckoutSettings;
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
