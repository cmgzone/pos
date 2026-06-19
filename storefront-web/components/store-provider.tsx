"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
} from "react";
import type {
  Catalog,
  CatalogItem,
  ProductVariant,
  CartItem,
  Branch,
} from "@/lib/types";

interface StoreContextValue {
  catalog: Catalog | null;
  setCatalog: (catalog: Catalog | null) => void;
  selectedBranch: Branch | null;
  setSelectedBranch: (branch: Branch) => void;
  cart: CartItem[];
  addToCart: (item: CatalogItem, variant?: ProductVariant, quantity?: number) => void;
  updateQuantity: (key: string, quantity: number) => void;
  removeFromCart: (key: string) => void;
  clearCart: () => void;
  cartTotal: number;
  cartCount: number;
  isCartOpen: boolean;
  setIsCartOpen: (open: boolean) => void;
}

const StoreContext = createContext<StoreContextValue | undefined>(undefined);

function makeCartKey(item: CatalogItem, variant?: ProductVariant): string {
  return variant ? `${item.id}::${variant.id}` : item.id;
}

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [selectedBranch, setSelectedBranch] = useState<Branch | null>(null);
  const [cart, setCart] = useState<CartItem[]>([]);
  const [isCartOpen, setIsCartOpen] = useState(false);

  const addToCart = useCallback(
    (item: CatalogItem, variant?: ProductVariant, quantity = 1) => {
      const key = makeCartKey(item, variant);
      setCart((prev) => {
        const existing = prev.find((i) => i.key === key);
        if (existing) {
          return prev.map((i) =>
            i.key === key
              ? { ...i, quantity: i.quantity + quantity }
              : i
          );
        }
        return [...prev, { key, item, variant, quantity }];
      });
      setIsCartOpen(true);
    },
    []
  );

  const updateQuantity = useCallback((key: string, quantity: number) => {
    setCart((prev) =>
      prev
        .map((i) => (i.key === key ? { ...i, quantity } : i))
        .filter((i) => i.quantity > 0)
    );
  }, []);

  const removeFromCart = useCallback((key: string) => {
    setCart((prev) => prev.filter((i) => i.key !== key));
  }, []);

  const clearCart = useCallback(() => {
    setCart([]);
  }, []);

  const cartTotal = useMemo(() => {
    return cart.reduce((total, { item, variant, quantity }) => {
      const price = variant ? variant.price : item.price;
      return total + price * quantity;
    }, 0);
  }, [cart]);

  const cartCount = useMemo(
    () => cart.reduce((count, { quantity }) => count + quantity, 0),
    [cart]
  );

  return (
    <StoreContext.Provider
      value={{
        catalog,
        setCatalog,
        selectedBranch,
        setSelectedBranch,
        cart,
        addToCart,
        updateQuantity,
        removeFromCart,
        clearCart,
        cartTotal,
        cartCount,
        isCartOpen,
        setIsCartOpen,
      }}
    >
      {children}
    </StoreContext.Provider>
  );
}

export function useStore() {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error("useStore must be used within a StoreProvider");
  }
  return context;
}
