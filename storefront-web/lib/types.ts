export interface BusinessBrand {
  logoUrl?: string | null;
  coverUrl?: string | null;
  coverUrls?: string[];
  primaryColor?: string | null;
  tagline?: string | null;
  description?: string | null;
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
  stock: number;
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
  currency: string;
  currencyCode: string;
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
  createdAt: string;
  items: {
    productName: string;
    quantity: number;
    unitPrice: number;
    lineTotal: number;
  }[];
}

export interface StorefrontBootstrap {
  businessId?: string;
  business?: Business;
  catalog?: Catalog;
}

declare global {
  interface Window {
    __STOREFRONT__?: StorefrontBootstrap;
    __STOREFRONT_CATALOG__?: Catalog;
  }
}
