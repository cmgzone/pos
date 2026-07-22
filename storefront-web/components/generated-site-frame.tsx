"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Catalog, CatalogItem, ProductVariant, StorefrontSection } from "@/lib/types";
import { useStore } from "./store-provider";
import { QuickViewModal } from "./quick-view-modal";

const PLATFORM_BINDING_CSS = `
:where(.piki-binding-brand) { display:flex; align-items:center; gap:12px; min-width:0; font-weight:800; }
:where(.piki-binding-brand) img { width:42px; height:42px; object-fit:cover; border-radius:12px; }
:where(.piki-binding-brand) span { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
:where(.piki-binding-store-intro) h1 { margin:0; }
:where(.piki-binding-store-intro) p { margin:10px 0 0; }
:where(.piki-binding-store-tagline) { font-weight:800; }
:where(.piki-binding-cover) { display:block; width:100%; height:auto; object-fit:cover; }
:where(.piki-binding-navigation) { display:flex; align-items:center; gap:18px; flex-wrap:wrap; }
:where(.piki-binding-navigation) button, :where(.piki-binding-cart), :where(.piki-binding-whatsapp) { border:0; background:transparent; color:inherit; cursor:pointer; font:inherit; }
:where(.piki-binding-navigation) button { font-size:13px; opacity:.72; }
:where(.piki-binding-cart), :where(.piki-binding-whatsapp) { padding:11px 16px; border-radius:999px; background:var(--piki-accent,#d14343); color:var(--piki-accent-contrast,#fff); font-weight:800; }
:where(.piki-binding-categories) { display:grid; gap:7px; }
:where(.piki-binding-category) { width:100%; display:flex; justify-content:space-between; gap:12px; padding:11px 12px; border:0; border-radius:10px; background:transparent; color:inherit; cursor:pointer; text-align:left; font:inherit; }
:where(.piki-binding-category):hover, :where(.piki-binding-category)[aria-current="true"] { background:var(--piki-binding-surface,rgba(127,127,127,.12)); }
:where(.piki-binding-search) { width:100%; margin-bottom:24px; padding:14px 16px; border:1px solid var(--piki-binding-line,rgba(127,127,127,.24)); border-radius:12px; background:transparent; color:inherit; font:inherit; outline:none; }
:where(.piki-binding-search):focus { border-color:var(--piki-accent,#d14343); box-shadow:0 0 0 3px color-mix(in srgb,var(--piki-accent,#d14343) 14%,transparent); }
:where(.piki-binding-products) { display:grid; grid-template-columns:repeat(auto-fill,minmax(min(210px,100%),1fr)); gap:20px; }
:where(.piki-binding-product) { min-width:0; overflow:hidden; border:1px solid var(--piki-binding-line,rgba(127,127,127,.18)); border-radius:16px; background:var(--piki-binding-card,rgba(255,255,255,.7)); }
:where(.piki-binding-product-image) { position:relative; aspect-ratio:4/5; overflow:hidden; background:var(--piki-binding-surface,rgba(127,127,127,.1)); }
:where(.piki-binding-product-image) img { width:100%; height:100%; object-fit:cover; }
:where(.piki-binding-product-placeholder) { width:100%; height:100%; display:grid; place-items:center; font-size:12px; opacity:.5; }
:where(.piki-binding-product-badge) { position:absolute; left:10px; top:10px; padding:6px 8px; border-radius:999px; background:var(--piki-accent,#d14343); color:var(--piki-accent-contrast,#fff); font-size:10px; font-weight:900; }
:where(.piki-binding-product-body) { padding:15px; }
:where(.piki-binding-product-category) { margin:0 0 5px; font-size:10px; font-weight:800; text-transform:uppercase; letter-spacing:.12em; opacity:.55; }
:where(.piki-binding-product) h3 { margin:0; font-size:15px; line-height:1.35; }
:where(.piki-binding-price) { display:flex; align-items:baseline; gap:8px; margin:10px 0 14px; font-weight:900; }
:where(.piki-binding-price) del { font-size:12px; font-weight:500; opacity:.5; }
:where(.piki-binding-product-meta) { display:flex; align-items:center; justify-content:space-between; gap:10px; margin:-5px 0 13px; font-size:10px; font-weight:800; opacity:.62; }
:where(.piki-binding-stock)[data-low="true"] { color:#b45309; opacity:1; }
:where(.piki-binding-add) { width:100%; padding:11px 13px; border:0; border-radius:10px; background:var(--piki-accent,#d14343); color:var(--piki-accent-contrast,#fff); cursor:pointer; font:inherit; font-size:12px; font-weight:900; }
:where(.piki-binding-add):disabled { cursor:not-allowed; opacity:.45; }
:where(.piki-binding-empty) { grid-column:1/-1; padding:60px 20px; text-align:center; opacity:.62; }
:where(.piki-binding-single-product) { display:grid; grid-template-columns:minmax(0,1.15fr) minmax(320px,.85fr); gap:clamp(28px,6vw,88px); align-items:start; }
:where(.piki-binding-single-gallery) { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
:where(.piki-binding-single-image) { position:relative; overflow:hidden; min-height:180px; aspect-ratio:1/1; border-radius:18px; background:var(--piki-binding-surface,rgba(127,127,127,.1)); }
:where(.piki-binding-single-image):first-child { grid-column:1/-1; aspect-ratio:4/3; }
:where(.piki-binding-single-image) img { width:100%; height:100%; object-fit:cover; }
:where(.piki-binding-single-info) { position:sticky; top:110px; padding:clamp(22px,4vw,42px); border:1px solid var(--piki-binding-line,rgba(127,127,127,.18)); border-radius:22px; background:var(--piki-binding-card,rgba(255,255,255,.72)); }
:where(.piki-binding-single-info) h1 { margin:8px 0 0; font-size:clamp(34px,5vw,64px); line-height:1; letter-spacing:-.04em; }
:where(.piki-binding-single-description) { margin:20px 0; white-space:pre-line; font-size:15px; line-height:1.75; opacity:.72; }
:where(.piki-binding-single-options) { display:flex; flex-wrap:wrap; gap:8px; margin:18px 0; }
:where(.piki-binding-single-option) { padding:8px 11px; border:1px solid var(--piki-binding-line,rgba(127,127,127,.2)); border-radius:999px; font-size:11px; font-weight:800; }
:where(.piki-binding-single-buy) { display:grid; gap:12px; margin-top:22px; }
:where(.piki-binding-single-buy) .piki-binding-add { min-height:52px; font-size:14px; }
:where(.piki-binding-single-trust) { margin:0; font-size:11px; line-height:1.55; opacity:.6; }
:where(.piki-binding-missing) { padding:64px 24px; border:1px dashed var(--piki-binding-line,rgba(127,127,127,.25)); border-radius:20px; text-align:center; }
.piki-inspect-mode [data-piki-inspect-hover="true"] { outline:3px solid #c45a00 !important; outline-offset:4px; cursor:crosshair !important; }
.piki-inspect-mode [data-piki-inspect-selected="true"] { outline:4px solid #d14343 !important; outline-offset:5px; box-shadow:0 0 0 9px rgba(209,67,67,.14) !important; }
.piki-inspector-box { position:fixed; z-index:2147483646; pointer-events:none; border:2px solid #c45a00; border-radius:4px; box-shadow:0 0 0 3px rgba(196,90,0,.18); }
.piki-inspector-box[data-selected="true"] { border-width:3px; border-color:#d14343; box-shadow:0 0 0 5px rgba(209,67,67,.18); }
.piki-inspector-badge { position:absolute; left:-2px; top:0; max-width:min(360px,90vw); transform:translateY(calc(-100% - 7px)); overflow:hidden; padding:5px 8px; border-radius:6px; background:#17171a; color:#fff; font:700 11px/1.25 Inter,system-ui,sans-serif; text-overflow:ellipsis; white-space:nowrap; box-shadow:0 5px 18px rgba(0,0,0,.28); }
@media (max-width:820px) { :where(.piki-binding-single-product) { grid-template-columns:1fr; } :where(.piki-binding-single-info) { position:static; } }
:where(.piki-binding-page) { min-height:70vh; }
:where(.piki-binding-page-heading) { padding:clamp(64px,9vw,130px) clamp(20px,8vw,120px); background:var(--piki-binding-surface,rgba(127,127,127,.08)); }
:where(.piki-binding-page-heading) h1 { max-width:900px; margin:8px 0 0; font-size:clamp(42px,7vw,88px); line-height:.98; letter-spacing:-.045em; }
:where(.piki-binding-page-heading) p { max-width:680px; margin:18px 0 0; font-size:clamp(16px,2vw,20px); line-height:1.65; opacity:.68; }
:where(.piki-binding-page-section) { padding:clamp(42px,6vw,88px) clamp(20px,8vw,120px); }
:where(.piki-binding-page-section)[data-style="surface"] { background:var(--piki-binding-surface,rgba(127,127,127,.08)); }
:where(.piki-binding-page-section)[data-style="accent"] { background:var(--piki-accent,#d14343); color:var(--piki-accent-contrast,#fff); }
:where(.piki-binding-page-section)[data-style="contrast"] { background:#171717; color:#fff; }
:where(.piki-binding-page-section)[data-width="narrow"] .piki-binding-page-inner { width:min(680px,100%); }
:where(.piki-binding-page-section)[data-width="wide"] .piki-binding-page-inner { width:min(1240px,100%); }
:where(.piki-binding-page-section)[data-align="center"] { text-align:center; }
:where(.piki-binding-page-section)[data-align="right"] { text-align:right; }
:where(.piki-binding-page-eyebrow) { margin:0 0 9px; text-transform:uppercase; letter-spacing:.16em; font-size:11px; font-weight:900; opacity:.62; }
:where(.piki-binding-page-section) h2 { margin:0 0 14px; font-size:clamp(28px,4vw,52px); line-height:1.05; letter-spacing:-.03em; }
:where(.piki-binding-page-copy) { margin:0; white-space:pre-line; font-size:16px; line-height:1.75; opacity:.74; }
:where(.piki-binding-page-items) { display:grid; grid-template-columns:repeat(auto-fit,minmax(min(240px,100%),1fr)); gap:14px; margin-top:28px; text-align:left; }
:where(.piki-binding-page-item) { padding:18px; border:1px solid var(--piki-binding-line,rgba(127,127,127,.18)); border-radius:14px; }
:where(.piki-binding-page-item) h3 { margin:0 0 7px; font-size:16px; }
:where(.piki-binding-page-item) p { margin:0; line-height:1.55; opacity:.7; }
:where(.piki-binding-page-item) img { width:100%; aspect-ratio:4/3; object-fit:cover; border-radius:10px; }
:where(.piki-binding-page-action) { display:inline-flex; margin-top:24px; padding:12px 17px; border:0; border-radius:999px; background:var(--piki-accent,#d14343); color:var(--piki-accent-contrast,#fff); cursor:pointer; font:inherit; font-weight:900; }
:where(.piki-binding-footer) { display:flex; justify-content:space-between; gap:24px; flex-wrap:wrap; padding:30px clamp(20px,5vw,72px); border-top:1px solid var(--piki-binding-line,rgba(127,127,127,.18)); font-size:12px; opacity:.72; }
`;

export function GeneratedSiteFrame({
  catalog,
  onTrackOrder,
  inspectMode = false,
  onComponentSelected,
}: {
  catalog: Catalog;
  onTrackOrder: () => void;
  inspectMode?: boolean;
  onComponentSelected?: (selection: PikiComponentSelection) => void;
}) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const { addToCart, setIsCartOpen } = useStore();
  const [height, setHeight] = useState(900);
  const [quickViewItem, setQuickViewItem] = useState<CatalogItem | null>(null);
  const [selectedVariant, setSelectedVariant] = useState<ProductVariant>();
  const build = catalog.siteBuild!;
  const scope = `${build.id}:${build.codeHash}`;
  const srcDoc = useMemo(
    () => buildSiteDocument(catalog, scope, inspectMode),
    [catalog, inspectMode, scope],
  );

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.source !== frameRef.current?.contentWindow) return;
      const data = event.data;
      if (!data || data.scope !== scope || data.channel !== "piki-generated-site") return;
      if (data.type === "inspector-ready") {
        window.chrome?.webview?.postMessage(JSON.stringify({
          channel: "piki-storefront-studio",
          type: "inspector-ready",
        }));
        return;
      }
      if (data.type === "resize") {
        const next = Number(data.height);
        if (Number.isFinite(next)) setHeight(Math.max(500, Math.min(20_000, next)));
        return;
      }
      if (data.type === "section-selected" && data.selection) {
        onComponentSelected?.({
          ...(data.selection as PikiComponentSelection),
          siteBuildId: build.id,
          siteMode: build.singleProductId ? "single_product" : "catalog",
          selectedProductId: build.singleProductId || undefined,
        });
        return;
      }
      if (data.type === "open-cart") {
        setIsCartOpen(true);
        return;
      }
      if (data.type === "add-product") {
        const item = catalog.products.find((candidate) => candidate.id === data.productId);
        if (!item) return;
        if (item.source === "external_api") {
          if (item.externalCheckoutUrl) {
            window.open(item.externalCheckoutUrl, "_blank", "noopener,noreferrer");
          }
        } else if (item.hasVariants && (item.variants?.length || 0) > 0) {
          setSelectedVariant(undefined);
          setQuickViewItem(item);
        } else {
          addToCart(item);
        }
        return;
      }
      if (data.type === "navigate" && typeof data.path === "string") {
        window.location.href = data.path.startsWith("/") ? data.path : "/";
        return;
      }
      if (data.type === "whatsapp" && catalog.business.whatsappNumber) {
        const phone = catalog.business.whatsappNumber.replace(/[^\d]/g, "");
        if (phone) window.open(`https://wa.me/${phone}`, "_blank", "noopener,noreferrer");
        return;
      }
      if (data.type === "track-order") {
        onTrackOrder();
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [
    addToCart,
    build.id,
    build.singleProductId,
    catalog.business.whatsappNumber,
    catalog.products,
    onComponentSelected,
    onTrackOrder,
    scope,
    setIsCartOpen,
  ]);

  return (
    <>
      <iframe
        ref={frameRef}
        title={build.name}
        srcDoc={srcDoc}
        sandbox="allow-scripts"
        className="block w-full border-0 bg-background"
        style={{ height }}
      />
      {quickViewItem && (
        <QuickViewModal
          item={quickViewItem}
          currencySymbol={catalog.currencySymbol}
          currencyCode={catalog.currencyCode}
          selectedVariant={selectedVariant}
          onVariantChange={setSelectedVariant}
          onClose={() => {
            setQuickViewItem(null);
            setSelectedVariant(undefined);
          }}
          onAdd={() => addToCart(quickViewItem, selectedVariant)}
        />
      )}
    </>
  );
}

export interface PikiComponentSelection {
  component: string;
  binding?: string;
  selector: string;
  parentSelector?: string;
  label: string;
  text?: string;
  element?: string;
  role?: string;
  scope?: string;
  hierarchy?: string;
  classes?: string;
  attributes?: string;
  dimensions?: string;
  styles?: string;
  siteBuildId?: string;
  siteMode?: "catalog" | "single_product";
  selectedProductId?: string;
}

function buildSiteDocument(
  catalog: Catalog,
  scope: string,
  inspectMode: boolean,
): string {
  const build = catalog.siteBuild!;
  const accent = catalog.theme.design.accentColor || catalog.business.brand.primaryColor || "#d14343";
  let markup = catalog.page || catalog.campaign
    ? build.pageHtml || build.html
    : build.html;
  const singleProductId =
    build.singleProductId ||
    bindingAttribute(markup, "piki-single-product", "product-id");
  markup = replaceSlot(markup, "piki-brand", brandMarkup(catalog));
  markup = replaceSlot(markup, "piki-store-intro", storeIntroMarkup(catalog));
  markup = replaceSlot(markup, "piki-cover", coverMarkup(catalog));
  markup = replaceSlot(markup, "piki-navigation", navigationMarkup(catalog));
  markup = replaceSlot(markup, "piki-categories", categoriesMarkup(catalog));
  markup = replaceSlot(markup, "piki-search", searchMarkup());
  markup = replaceSlot(markup, "piki-products", productsMarkup(catalog));
  markup = replaceSlot(
    markup,
    "piki-single-product",
    singleProductMarkup(catalog, singleProductId),
  );
  markup = replaceSlot(markup, "piki-cart-button", '<button type="button" class="piki-binding-cart" data-piki-binding="cart" data-piki-component="cart-button" data-piki-action="open-cart">Cart</button>');
  markup = replaceSlot(markup, "piki-whatsapp", '<button type="button" class="piki-binding-whatsapp" data-piki-binding="whatsapp" data-piki-component="whatsapp-button" data-piki-action="whatsapp">WhatsApp</button>');
  markup = replaceSlot(markup, "piki-page-content", pageMarkup(catalog));
  markup = replaceSlot(markup, "piki-footer", footerMarkup(catalog));

  const safeScope = jsonForScript(scope);
  const safeInspectMode = jsonForScript(inspectMode);
  const platformScript = `(function(){
    const scope=${safeScope};
    const inspectMode=${safeInspectMode};
    const send=(type,data={})=>parent.postMessage({channel:'piki-generated-site',scope,type,...data},'*');
    const normalize=(value)=>String(value||'').toLowerCase();
    let category='all'; let query='';
    const filter=()=>{
      document.querySelectorAll('[data-piki-product]').forEach((card)=>{
        const matchesCategory=category==='all'||card.dataset.category===category;
        const matchesQuery=!query||normalize(card.dataset.search).includes(query);
        card.hidden=!(matchesCategory&&matchesQuery);
      });
      document.querySelectorAll('[data-piki-category]').forEach((button)=>button.setAttribute('aria-current',String(button.dataset.pikiCategory===category)));
    };
    const interactiveSelector='button,a,input,select,textarea,label,[role="button"],[role="link"],[role="tab"],[role="menuitem"]';
    const contentSelector='h1,h2,h3,h4,h5,h6,p,img,picture,figure,figcaption,blockquote,li,article,nav,aside,section,header,footer,main,[data-piki-component],[data-piki-binding]';
    const componentFor=(target)=>{
      if(!(target instanceof Element)||target.closest('[data-piki-inspector-ignore]'))return null;
      return target.closest(interactiveSelector)||target.closest(contentSelector)||target.closest('div,span');
    };
    const selectorFor=(element)=>{
      if(!element)return '';
      const parts=[]; let current=element;
      while(current&&current!==document.body&&parts.length<6){
        let part=current.tagName.toLowerCase();
        if(current.id)part+='#'+CSS.escape(current.id);
        else {
          const classes=Array.from(current.classList).filter((name)=>!name.startsWith('piki-inspect')).slice(0,2);
          if(classes.length)part+='.'+classes.map((name)=>CSS.escape(name)).join('.');
          const siblings=current.parentElement?Array.from(current.parentElement.children).filter((item)=>item.tagName===current.tagName):[];
          if(siblings.length>1)part+=':nth-of-type('+(siblings.indexOf(current)+1)+')';
        }
        parts.unshift(part);
        const candidate=parts.join(' > ');
        try{if(document.querySelectorAll(candidate).length===1)return candidate;}catch(_error){}
        current=current.parentElement;
      }
      return parts.join(' > ');
    };
    const componentName=(element)=>{
      const explicit=element.dataset.pikiComponent||element.dataset.pikiBinding;
      if(explicit)return explicit;
      if(element.matches('h1,h2,h3,h4,h5,h6'))return 'heading';
      if(element.matches('p,blockquote,figcaption'))return 'text';
      if(element.matches('img,picture,figure'))return 'image';
      if(element.matches('button,[role="button"]'))return 'button';
      if(element.matches('a,[role="link"]'))return 'link';
      if(element.matches('input,select,textarea'))return 'form-control';
      return element.tagName.toLowerCase();
    };
    const compactLabel=(element)=>{
      const ownText=Array.from(element.childNodes).filter((node)=>node.nodeType===Node.TEXT_NODE).map((node)=>node.textContent||'').join(' ').replace(/\\s+/g,' ').trim();
      const labelled=element.dataset.pikiLabel||element.getAttribute('aria-label')||element.getAttribute('alt')||element.getAttribute('title')||element.getAttribute('placeholder')||ownText;
      const heading=element.querySelector('h1,h2,h3,[aria-label]');
      return String(labelled||heading?.textContent?.trim()||componentName(element)).slice(0,160);
    };
    const describe=(element)=>{
      const binding=element.dataset.pikiBinding||'';
      const scopeElement=element.closest('[data-piki-component],[data-piki-section-id],article,nav,aside,header,footer,main,section');
      const computed=getComputedStyle(element); const rect=element.getBoundingClientRect();
      const hierarchy=[]; let current=element;
      while(current&&current!==document.body&&hierarchy.length<6){hierarchy.unshift(componentName(current));current=current.parentElement;}
      const attributes=Array.from(element.attributes).filter((attribute)=>['id','href','src','type','name','aria-label','data-piki-action','data-product-id','data-piki-section-id'].includes(attribute.name)).map((attribute)=>attribute.name+'='+attribute.value).join('; ');
      return {
        component:componentName(element),binding:binding||scopeElement?.dataset.pikiBinding||undefined,
        selector:selectorFor(element),parentSelector:selectorFor(element.parentElement),label:compactLabel(element),
        text:String(element.textContent||'').replace(/\\s+/g,' ').trim().slice(0,500),element:element.tagName.toLowerCase(),
        role:element.getAttribute('role')||undefined,scope:scopeElement?compactLabel(scopeElement):undefined,
        hierarchy:hierarchy.join(' > '),classes:Array.from(element.classList).filter((name)=>!name.startsWith('piki-inspect')).join(' ').slice(0,500),
        attributes:attributes.slice(0,500),dimensions:Math.round(rect.width)+' × '+Math.round(rect.height)+' px',
        styles:['display:'+computed.display,'position:'+computed.position,'font:'+computed.fontFamily+' '+computed.fontSize,'color:'+computed.color,'background:'+computed.backgroundColor,'spacing:'+computed.margin+'/'+computed.padding].join('; ').slice(0,700)
      };
    };
    const overlay=document.createElement('div');overlay.className='piki-inspector-box';overlay.hidden=true;overlay.innerHTML='<div class="piki-inspector-badge"></div>';document.body.appendChild(overlay);
    const draw=(element,selectedState)=>{
      if(!element){overlay.hidden=true;return;}
      const rect=element.getBoundingClientRect();
      if(rect.width<=0||rect.height<=0){overlay.hidden=true;return;}
      overlay.hidden=false;overlay.dataset.selected=String(Boolean(selectedState));overlay.style.left=rect.left+'px';overlay.style.top=rect.top+'px';overlay.style.width=rect.width+'px';overlay.style.height=rect.height+'px';
      const badge=overlay.firstElementChild;if(badge)badge.textContent=componentName(element)+' · '+compactLabel(element);
    };
    let hovered=null;let selected=null;
    if(inspectMode){
      document.body.classList.add('piki-inspect-mode');
      document.addEventListener('pointerover',(event)=>{const element=componentFor(event.target);if(!element)return;if(hovered&&hovered!==element)delete hovered.dataset.pikiInspectHover;hovered=element;element.dataset.pikiInspectHover='true';draw(element,element===selected);},true);
      document.addEventListener('pointerout',(event)=>{const element=componentFor(event.target);if(element&&element!==selected)delete element.dataset.pikiInspectHover;if(hovered===element)hovered=null;if(selected)draw(selected,true);else draw(null,false);},true);
      const redraw=()=>draw(selected||hovered,Boolean(selected));window.addEventListener('scroll',redraw,true);window.addEventListener('resize',redraw);
      send('inspector-ready');
    }
    document.addEventListener('click',(event)=>{
      if(inspectMode){
        const component=componentFor(event.target);
        if(component){
          event.preventDefault();event.stopImmediatePropagation();
          document.querySelectorAll('[data-piki-inspect-selected]').forEach((item)=>delete item.dataset.pikiInspectSelected);
          selected=component;component.dataset.pikiInspectSelected='true';draw(component,true);
          send('section-selected',{selection:describe(component)});
        }
        return;
      }
      const target=event.target.closest('[data-piki-action],[data-piki-category],[data-piki-path]');
      if(!target)return;
      if(target.dataset.pikiCategory){category=target.dataset.pikiCategory;filter();return;}
      if(target.dataset.pikiPath){send('navigate',{path:target.dataset.pikiPath});return;}
      if(target.dataset.pikiAction==='add-product')send('add-product',{productId:target.dataset.productId});
      if(target.dataset.pikiAction==='open-cart')send('open-cart');
      if(target.dataset.pikiAction==='whatsapp')send('whatsapp');
      if(target.dataset.pikiAction==='track-order')send('track-order');
    });
    document.addEventListener('input',(event)=>{if(event.target.matches('[data-piki-search]')){query=normalize(event.target.value);filter();}});
    const resize=()=>send('resize',{height:Math.ceil(document.documentElement.scrollHeight)});
    new ResizeObserver(resize).observe(document.documentElement); window.addEventListener('load',resize); resize();
  })();`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline' https://fonts.googleapis.com; script-src 'unsafe-inline'; connect-src 'none'; font-src https://fonts.gstatic.com data:; media-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'; navigate-to 'self'"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Merriweather:wght@400;700;900&family=Montserrat:wght@400;500;600;700;800;900&family=Nunito:wght@400;500;600;700;800;900&family=Oswald:wght@400;500;600;700&family=Playfair+Display:wght@400;500;600;700;800;900&display=swap"><style>:root{--piki-accent:${escapeCssValue(accent)};--piki-accent-contrast:${readableText(accent)}}${PLATFORM_BINDING_CSS}\n${build.css}</style></head><body>${markup}<script>${platformScript}</script></body></html>`;
}

function brandMarkup(catalog: Catalog): string {
  const logo = catalog.business.brand.logoUrl;
  return `<div class="piki-binding-brand" data-piki-binding="brand" data-piki-component="brand">${logo ? `<img src="${escapeAttr(logo)}" alt="">` : ""}<span>${escapeHtml(catalog.business.name)}</span></div>`;
}

function storeIntroMarkup(catalog: Catalog): string {
  const brand = catalog.business.brand;
  return `<div class="piki-binding-store-intro" data-piki-binding="store-intro" data-piki-component="store-intro"><h1>${escapeHtml(catalog.business.name)}</h1>${brand.tagline ? `<p class="piki-binding-store-tagline">${escapeHtml(brand.tagline)}</p>` : ""}${brand.description ? `<p>${escapeHtml(brand.description)}</p>` : ""}</div>`;
}

function coverMarkup(catalog: Catalog): string {
  const image = safeTrustedImageUrl(
    catalog.business.brand.coverUrl || catalog.business.brand.coverUrls?.[0],
  );
  return image
    ? `<img class="piki-binding-cover" data-piki-binding="cover" data-piki-component="cover-image" src="${escapeAttr(image)}" alt="" loading="eager">`
    : '<div class="piki-binding-cover" data-piki-binding="cover" data-piki-component="cover-image" aria-hidden="true"></div>';
}

function navigationMarkup(catalog: Catalog): string {
  const pages = (catalog.pages || []).map((page) => `<button type="button" data-piki-path="/page/${escapeAttr(page.slug)}">${escapeHtml(page.label || page.title)}</button>`).join("");
  const portalPath = `/portal?businessId=${encodeURIComponent(catalog.business.id)}`;
  return `<nav class="piki-binding-navigation" data-piki-binding="navigation" data-piki-component="navigation" aria-label="Store navigation"><button type="button" data-piki-path="/">Shop</button>${pages}<button type="button" data-piki-path="${escapeAttr(portalPath)}">My account</button></nav>`;
}

function categoriesMarkup(catalog: Catalog): string {
  const count = (name: string) => catalog.products.filter((item) => item.category === name).length;
  return `<nav class="piki-binding-categories" data-piki-binding="categories" data-piki-component="category-navigation" aria-label="Product categories"><button type="button" class="piki-binding-category" data-piki-category="all" aria-current="true"><span>All products</span><span>${catalog.products.length}</span></button>${catalog.categories.map((name) => `<button type="button" class="piki-binding-category" data-piki-category="${escapeAttr(name)}" aria-current="false"><span>${escapeHtml(name)}</span><span>${count(name)}</span></button>`).join("")}</nav>`;
}

function searchMarkup(): string {
  return '<input class="piki-binding-search" type="search" data-piki-binding="search" data-piki-component="product-search" data-piki-search placeholder="Search products" aria-label="Search products">';
}

function productsMarkup(catalog: Catalog): string {
  if (!catalog.products.length) return '<div class="piki-binding-products" data-piki-binding="products" data-piki-component="product-catalogue"><p class="piki-binding-empty">No products are available yet.</p></div>';
  return `<div class="piki-binding-products" data-piki-binding="products" data-piki-component="product-catalogue">${catalog.products.map((item) => productMarkup(item, catalog)).join("")}</div>`;
}

function productMarkup(item: CatalogItem, catalog: Catalog): string {
  const image = item.imageUrls?.[0] || item.imageUrl;
  const variants = item.variants || [];
  const availableVariants = variants.filter((variant) => variant.available !== false);
  const hasVariants = Boolean(item.hasVariants && variants.length > 0);
  const externalUnavailable = item.source === "external_api" && !item.externalCheckoutUrl;
  const outOfStock = externalUnavailable || (hasVariants
    ? availableVariants.length === 0
    : item.trackStock !== false && item.stock <= 0);
  const category = item.category || "";
  const search = [item.name, item.brand, item.category, item.description].filter(Boolean).join(" ").toLowerCase();
  const variantPrices = (availableVariants.length ? availableVariants : variants).map((variant) => variant.price);
  const displayPrice = hasVariants && variantPrices.length ? Math.min(...variantPrices) : item.price;
  const price = `${hasVariants ? "From " : ""}${catalog.currencySymbol}${Number(displayPrice || 0).toLocaleString()}`;
  const compare = item.compareAtPrice && item.compareAtPrice > displayPrice ? `${catalog.currencySymbol}${Number(item.compareAtPrice).toLocaleString()}` : "";
  const stockLabel = externalUnavailable
    ? "Unavailable"
    : outOfStock
    ? "Sold out"
    : hasVariants
      ? `${availableVariants.length} ${availableVariants.length === 1 ? "option" : "options"}`
      : item.trackStock !== false && item.stock <= 5
        ? `Only ${Math.max(0, item.stock)} left`
        : "In stock";
  const buttonLabel = externalUnavailable
    ? "Unavailable"
    : outOfStock
    ? "Sold out"
    : item.externalCheckoutUrl
      ? "View product"
      : hasVariants
        ? "Choose options"
        : "Add to cart";
  return `<article class="piki-binding-product" data-piki-product data-piki-component="product-card" data-piki-label="${escapeAttr(item.name)}" data-product-id="${escapeAttr(item.id)}" data-category="${escapeAttr(category)}" data-search="${escapeAttr(search)}"><div class="piki-binding-product-image" data-piki-component="product-image">${image ? `<img src="${escapeAttr(image)}" alt="${escapeAttr(item.name)}" loading="lazy">` : '<div class="piki-binding-product-placeholder">No image</div>'}${item.discountPercent ? `<span class="piki-binding-product-badge">-${Math.round(item.discountPercent)}%</span>` : ""}</div><div class="piki-binding-product-body">${category ? `<p class="piki-binding-product-category">${escapeHtml(category)}</p>` : ""}<h3 data-piki-component="product-title">${escapeHtml(item.name)}</h3><div class="piki-binding-price" data-piki-component="product-price"><span>${escapeHtml(price)}</span>${compare ? `<del>${escapeHtml(compare)}</del>` : ""}</div><div class="piki-binding-product-meta" data-piki-component="product-availability"><span>${hasVariants ? "Variants available" : escapeHtml(item.unit || item.saleUnit || "Product")}</span><span class="piki-binding-stock" data-low="${String(!outOfStock && !hasVariants && item.trackStock !== false && item.stock <= 5)}">${escapeHtml(stockLabel)}</span></div><button type="button" class="piki-binding-add" data-piki-component="product-action" data-piki-action="add-product" data-product-id="${escapeAttr(item.id)}" ${outOfStock ? "disabled" : ""}>${buttonLabel}</button></div></article>`;
}

function singleProductMarkup(catalog: Catalog, productId?: string | null): string {
  const item = catalog.products.find((candidate) => candidate.id === productId);
  if (!item) {
    return '<section class="piki-binding-missing" data-piki-binding="single-product" data-piki-component="single-product"><h2>Product unavailable</h2><p>The selected product is no longer available in this store.</p></section>';
  }
  const images = (item.imageUrls?.length ? item.imageUrls : [item.imageUrl])
    .map((image) => safeTrustedImageUrl(image))
    .filter(Boolean)
    .slice(0, 5);
  const variants = item.variants || [];
  const availableVariants = variants.filter((variant) => variant.available !== false);
  const hasVariants = Boolean(item.hasVariants && variants.length);
  const externalUnavailable = item.source === "external_api" && !item.externalCheckoutUrl;
  const outOfStock = externalUnavailable || (hasVariants
    ? availableVariants.length === 0
    : item.trackStock !== false && item.stock <= 0);
  const variantPrices = (availableVariants.length ? availableVariants : variants)
    .map((variant) => variant.price);
  const displayPrice = hasVariants && variantPrices.length
    ? Math.min(...variantPrices)
    : item.price;
  const price = `${hasVariants ? "From " : ""}${catalog.currencySymbol}${Number(displayPrice || 0).toLocaleString()}`;
  const compare = item.compareAtPrice && item.compareAtPrice > displayPrice
    ? `${catalog.currencySymbol}${Number(item.compareAtPrice).toLocaleString()}`
    : "";
  const stockLabel = externalUnavailable
    ? "Unavailable"
    : outOfStock
      ? "Sold out"
      : hasVariants
        ? `${availableVariants.length} ${availableVariants.length === 1 ? "option" : "options"} available`
        : item.trackStock !== false && item.stock <= 5
          ? `Only ${Math.max(0, item.stock)} left`
          : "In stock";
  const buttonLabel = externalUnavailable
    ? "Unavailable"
    : outOfStock
      ? "Sold out"
      : item.externalCheckoutUrl
        ? "View product"
        : hasVariants
          ? "Choose options"
          : "Add to cart";
  const gallery = images.length
    ? images.map((image, index) => `<figure class="piki-binding-single-image"><img src="${escapeAttr(image)}" alt="${escapeAttr(index === 0 ? item.name : `${item.name} view ${index + 1}`)}" loading="${index === 0 ? "eager" : "lazy"}">${index === 0 && item.discountPercent ? `<span class="piki-binding-product-badge">-${Math.round(item.discountPercent)}%</span>` : ""}</figure>`).join("")
    : '<div class="piki-binding-single-image"><div class="piki-binding-product-placeholder">Add product photography in Piki POS</div></div>';
  const options = hasVariants
    ? `<div class="piki-binding-single-options" aria-label="Available options">${availableVariants.map((variant) => `<span class="piki-binding-single-option">${escapeHtml(variant.name)}</span>`).join("")}</div>`
    : "";
  return `<section class="piki-binding-single-product" data-piki-binding="single-product" data-piki-component="single-product" data-piki-label="${escapeAttr(item.name)}"><div class="piki-binding-single-gallery" data-piki-component="product-gallery" data-piki-label="${escapeAttr(`${item.name} gallery`)}">${gallery}</div><div class="piki-binding-single-info" data-piki-component="product-information" data-piki-label="${escapeAttr(`${item.name} information`)}">${item.category ? `<p class="piki-binding-product-category">${escapeHtml(item.category)}</p>` : ""}<h1>${escapeHtml(item.name)}</h1>${item.brand ? `<p>${escapeHtml(item.brand)}</p>` : ""}<div class="piki-binding-price"><span>${escapeHtml(price)}</span>${compare ? `<del>${escapeHtml(compare)}</del>` : ""}</div>${item.description ? `<p class="piki-binding-single-description">${escapeHtml(item.description)}</p>` : ""}${options}<div class="piki-binding-product-meta"><span>${escapeHtml(item.unit || item.saleUnit || "Product")}</span><span class="piki-binding-stock" data-low="${String(!outOfStock && !hasVariants && item.trackStock !== false && item.stock <= 5)}">${escapeHtml(stockLabel)}</span></div><div class="piki-binding-single-buy" data-piki-component="product-purchase"><button type="button" class="piki-binding-add" data-piki-action="add-product" data-product-id="${escapeAttr(item.id)}" ${outOfStock ? "disabled" : ""}>${buttonLabel}</button><p class="piki-binding-single-trust">Live pricing and availability are verified by the store at checkout.</p></div></div></section>`;
}

function footerMarkup(catalog: Catalog): string {
  return `<footer class="piki-binding-footer" data-piki-binding="footer" data-piki-component="footer"><span>© ${new Date().getFullYear()} ${escapeHtml(catalog.business.name)}</span><span>Secure ordering powered by Piki</span></footer>`;
}

function pageMarkup(catalog: Catalog): string {
  const page = catalog.page;
  if (!page) return campaignMarkup(catalog);
  const sections = page.sections
    .filter((section) => section.enabled !== false && section.type !== "announcement")
    .map((section) => pageSectionMarkup(section))
    .join("");
  return `<main class="piki-binding-page"><header class="piki-binding-page-heading"><p class="piki-binding-page-eyebrow">${escapeHtml(page.pageType || "Page")}</p><h1>${escapeHtml(page.title)}</h1>${page.seoDescription ? `<p>${escapeHtml(page.seoDescription)}</p>` : ""}</header>${sections}</main>`;
}

function campaignMarkup(catalog: Catalog): string {
  const campaign = catalog.campaign;
  if (!campaign) return "";
  const productIds = new Set(campaign.productIds || []);
  const products = catalog.products.filter((item) => productIds.has(item.id));
  const heroImage = safeTrustedImageUrl(campaign.heroImageUrl);
  const highlights = (campaign.highlights || [])
    .map(
      (highlight) =>
        `<li class="piki-binding-page-item">${escapeHtml(highlight)}</li>`,
    )
    .join("");
  return `<main class="piki-binding-page piki-binding-campaign"><header class="piki-binding-page-heading">${campaign.badgeLabel ? `<p class="piki-binding-page-eyebrow">${escapeHtml(campaign.badgeLabel)}</p>` : campaign.eyebrow ? `<p class="piki-binding-page-eyebrow">${escapeHtml(campaign.eyebrow)}</p>` : ""}<h1>${escapeHtml(campaign.title)}</h1>${campaign.description ? `<p>${escapeHtml(campaign.description)}</p>` : ""}${campaign.buttonLabel ? `<a class="piki-binding-page-action" href="#piki-campaign-products">${escapeHtml(campaign.buttonLabel)}</a>` : ""}${heroImage ? `<img class="piki-binding-cover" src="${escapeAttr(heroImage)}" alt="" loading="eager">` : ""}</header>${highlights ? `<section class="piki-binding-page-section" data-style="surface"><div class="piki-binding-page-inner"><ul class="piki-binding-page-items">${highlights}</ul></div></section>` : ""}<section id="piki-campaign-products" class="piki-binding-page-section"><div class="piki-binding-page-inner"><p class="piki-binding-page-eyebrow">Campaign selection</p><h2>${escapeHtml(campaign.name)}</h2>${productsMarkup({ ...catalog, products })}</div></section></main>`;
}

function pageSectionMarkup(section: StorefrontSection): string {
  const items = (section.items || []).map((item) => {
    if ("question" in item) {
      return `<div class="piki-binding-page-item"><h3>${escapeHtml(item.question)}</h3><p>${escapeHtml(item.answer)}</p></div>`;
    }
    if ("imageUrl" in item) {
      const image = safeTrustedImageUrl(item.imageUrl);
      return `<figure class="piki-binding-page-item">${image ? `<img src="${escapeAttr(image)}" alt="${escapeAttr(item.alt || "")}" loading="lazy">` : ""}${item.caption ? `<figcaption>${escapeHtml(item.caption)}</figcaption>` : ""}</figure>`;
    }
    return `<div class="piki-binding-page-item"><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.body)}</p></div>`;
  }).join("");
  const copy = section.content || section.body || section.text || "";
  const action = pageActionMarkup(section.buttonAction, section.buttonLabel);
  return `<section class="piki-binding-page-section" data-piki-component="page-section" data-piki-section-id="${escapeAttr(section.id)}" data-piki-label="${escapeAttr(section.title || section.type)}" data-style="${escapeAttr(section.style || "default")}" data-width="${escapeAttr(section.width || "contained")}" data-align="${escapeAttr(section.alignment || "left")}"><div class="piki-binding-page-inner">${section.eyebrow ? `<p class="piki-binding-page-eyebrow">${escapeHtml(section.eyebrow)}</p>` : ""}${section.title ? `<h2>${escapeHtml(section.title)}</h2>` : ""}${copy ? `<p class="piki-binding-page-copy">${escapeHtml(copy)}</p>` : ""}${items ? `<div class="piki-binding-page-items">${items}</div>` : ""}${action}</div></section>`;
}

function pageActionMarkup(action: string | undefined, label: string | undefined): string {
  if (!label || !action || action === "none") return "";
  if (action === "catalog") {
    return `<button type="button" class="piki-binding-page-action" data-piki-path="/">${escapeHtml(label)}</button>`;
  }
  if (action === "whatsapp" || action === "trackOrder") {
    const trustedAction = action === "trackOrder" ? "track-order" : "whatsapp";
    return `<button type="button" class="piki-binding-page-action" data-piki-action="${trustedAction}">${escapeHtml(label)}</button>`;
  }
  return "";
}

function safeTrustedImageUrl(value: unknown): string {
  const url = String(value || "").trim();
  return /^(https:\/\/|data:image\/)/i.test(url) ? url : "";
}

function replaceSlot(markup: string, slot: string, replacement: string): string {
  const paired = new RegExp(`<${slot}(?:\\s[^>]*)?>[\\s\\S]*?<\\/${slot}\\s*>`, "gi");
  const selfClosing = new RegExp(`<${slot}(?:\\s[^>]*)?\\s*\\/>`, "gi");
  return markup.replace(paired, replacement).replace(selfClosing, replacement);
}

function bindingAttribute(
  markup: string,
  slot: string,
  attribute: string,
): string | null {
  const opening = markup.match(new RegExp(`<${slot}\\b([^>]*)>`, "i"));
  if (!opening) return null;
  const match = (opening[1] || "").match(
    new RegExp(`(?:^|\\s)${attribute}\\s*=\\s*(["'])(.*?)\\1`, "i"),
  );
  return match?.[2]?.trim() || null;
}

function escapeHtml(value: unknown): string {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

function escapeAttr(value: unknown): string {
  return escapeHtml(value).replaceAll("`", "&#96;");
}

function escapeCssValue(value: string): string {
  return /^#[0-9a-f]{6}$/i.test(value) ? value : "#d14343";
}

function readableText(color: string): string {
  if (!/^#[0-9a-f]{6}$/i.test(color)) return "#ffffff";
  const red = parseInt(color.slice(1, 3), 16);
  const green = parseInt(color.slice(3, 5), 16);
  const blue = parseInt(color.slice(5, 7), 16);
  return red * 0.299 + green * 0.587 + blue * 0.114 > 160 ? "#111111" : "#ffffff";
}

function jsonForScript(value: unknown): string {
  return JSON.stringify(value).replaceAll("<", "\\u003c").replaceAll("\u2028", "\\u2028").replaceAll("\u2029", "\\u2029");
}
