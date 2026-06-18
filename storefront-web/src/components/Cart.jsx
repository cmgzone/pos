import { useState } from 'react'
import { classNames, cartKey } from '../utils'
import Checkout from './Checkout.jsx'
import TrackOrder from './TrackOrder.jsx'

export default function Cart({
  open,
  onClose,
  items,
  total,
  money,
  onUpdateQty,
  onRemove,
  onSubmitOrder,
  onTrackOrder,
  lastOrder,
  whatsappConfirmUrl,
  freeShipThreshold,
  pushToast,
}) {
  const [view, setView] = useState('cart')

  const close = () => {
    onClose()
    setTimeout(() => setView('cart'), 250)
  }

  const freeShipPct =
    freeShipThreshold > 0 ? Math.min(100, Math.round((total / freeShipThreshold) * 100)) : 0
  const freeShipUnlocked = freeShipThreshold > 0 && total >= freeShipThreshold

  return (
    <>
      <div className={classNames('cart-backdrop', open && 'open')} onClick={close} aria-hidden="true" />
      <aside className={classNames('cart-drawer', open && 'open')} aria-label="Cart and checkout">
        <div className="cart-head">
          <div className="cart-tabs">
            <button
              type="button"
              className={classNames('cart-tab', view === 'cart' && 'active')}
              onClick={() => setView('cart')}
            >
              Cart ({items.reduce((sum, i) => sum + i.qty, 0)})
            </button>
            <button
              type="button"
              className={classNames('cart-tab', view === 'track' && 'active')}
              onClick={() => setView('track')}
            >
              Track order
            </button>
          </div>
          <button type="button" className="cart-close" onClick={close} aria-label="Close cart">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {view === 'cart' && (
          <>
            {freeShipThreshold > 0 && items.length > 0 && (
              <div className="ship-bar">
                <div className="ship-text">
                  {freeShipUnlocked ? (
                    <>You have unlocked <b>free delivery</b>.</>
                  ) : (
                    <>Add <b>{money(freeShipThreshold - total)}</b> more to unlock free delivery.</>
                  )}
                </div>
                <div className="ship-track">
                  <div className="ship-fill" style={{ width: `${freeShipPct}%` }} />
                </div>
              </div>
            )}

            {items.length === 0 ? (
              <div className="cart-empty">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={1.6}
                    d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-9 2a2 2 0 11-4 0 2 2 0 014 0z"
                  />
                </svg>
                <p>Your cart is empty.</p>
                <button type="button" className="btn btn-ghost" onClick={close}>
                  Continue shopping
                </button>
              </div>
            ) : (
              <div className="cart-body">
                {items.map((entry) => {
                  const key = cartKey(entry.item, entry.variant ? entry.variant.id : null)
                  const price = entry.variant ? entry.variant.price : entry.item.price
                  const title = entry.variant ? `${entry.item.name} (${entry.variant.name})` : entry.item.name
                  return (
                    <div className="cart-item" key={key}>
                      {entry.item.imageUrl ? (
                        <img src={entry.item.imageUrl} className="cart-item-img" alt="" />
                      ) : (
                        <div className="cart-item-img cart-item-ph" aria-hidden="true">
                          <svg width="26" height="26" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={1.6}
                              d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                            />
                          </svg>
                        </div>
                      )}
                      <div className="cart-item-info">
                        <div className="cart-item-title">{title}</div>
                        <div className="cart-item-price">{money(price)}</div>
                      </div>
                      <div className="cart-item-actions">
                        <div className="qty">
                          <button
                            type="button"
                            className="qty-btn"
                            onClick={() => onUpdateQty(key, -1)}
                            aria-label="Decrease quantity"
                          >
                            &minus;
                          </button>
                          <span className="qty-display">{entry.qty}</span>
                          <button
                            type="button"
                            className="qty-btn"
                            onClick={() => onUpdateQty(key, 1)}
                            aria-label="Increase quantity"
                          >
                            +
                          </button>
                        </div>
                        <button
                          type="button"
                          className="remove-btn"
                          onClick={() => onRemove(key)}
                          aria-label="Remove item"
                        >
                          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={2}
                              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6M1 7h22M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3"
                            />
                          </svg>
                        </button>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}

            {items.length > 0 && (
              <Checkout
                total={total}
                money={money}
                lastOrder={lastOrder}
                whatsappConfirmUrl={whatsappConfirmUrl}
                onSubmitOrder={onSubmitOrder}
                pushToast={pushToast}
              />
            )}
          </>
        )}

        {view === 'track' && <TrackOrder onTrackOrder={onTrackOrder} pushToast={pushToast} />}
      </aside>
    </>
  )
}
