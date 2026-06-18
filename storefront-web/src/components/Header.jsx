import { useEffect, useMemo, useState } from 'react'

import { classNames } from '../utils'

export default function Header({ catalog, loading, error }) {
  const business = catalog?.business
  const brand = business?.brand || {}
  const name = business?.name || 'Online Store'
  const tagline = brand.tagline || 'Online catalog'
  const description =
    brand.description ||
    'Shop products and services, choose variants, and send your order directly to the store.'
  const logoUrl = brand.logoUrl || null
  const coverUrl = brand.coverUrl || null
  const brandCoverUrls = brand.coverUrls
  const coverUrls = useMemo(() => {
    const raw = Array.isArray(brandCoverUrls) && brandCoverUrls.length
      ? brandCoverUrls
      : coverUrl
        ? [coverUrl]
        : []
    const seen = new Set()
    return raw
      .map((url) => String(url || '').trim())
      .filter((url) => url && !seen.has(url) && seen.add(url))
      .slice(0, 8)
  }, [brandCoverUrls, coverUrl])
  const coverSignature = coverUrls.join('|')
  const [activeCoverIndex, setActiveCoverIndex] = useState(0)
  const storeInitial = String(name || '').trim().charAt(0).toUpperCase() || 'P'
  const branchName = business?.selectedBranch?.name

  useEffect(() => {
    setActiveCoverIndex(0)
  }, [coverSignature])

  useEffect(() => {
    if (coverUrls.length <= 1) return undefined
    const timer = window.setInterval(() => {
      setActiveCoverIndex((current) => (current + 1) % coverUrls.length)
    }, 5000)
    return () => window.clearInterval(timer)
  }, [coverSignature, coverUrls.length])

  if (error) {
    return (
      <header className="store-header is-error">
        <div className="wrap">
          <div className="store-header-error">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
            <div>
              <h1>Store unavailable</h1>
              <p>{error}</p>
            </div>
          </div>
        </div>
      </header>
    )
  }

  return (
    <header className="store-header">
      <div className={classNames('store-cover', coverUrls.length === 0 && 'is-placeholder')}>
        {coverUrls.length > 0 ? (
          <div className="store-cover-slides" aria-hidden="true">
            {coverUrls.map((url, index) => (
              <img
                key={`${url}-${index}`}
                src={url}
                alt=""
                className={classNames(
                  'store-cover-img',
                  index === activeCoverIndex && 'is-active',
                  coverUrls.length === 1 && 'is-single',
                )}
              />
            ))}
          </div>
        ) : (
          <div className="store-cover-glow" aria-hidden="true" />
        )}
        <div className="store-cover-shade" aria-hidden="true" />
        {coverUrls.length > 1 && (
          <div className="store-cover-dots" aria-hidden="true">
            {coverUrls.map((url, index) => (
              <span
                key={`${url}-dot-${index}`}
                className={classNames(index === activeCoverIndex && 'is-active')}
              />
            ))}
          </div>
        )}
      </div>

      <div className="wrap store-header-inner">
        <div className={classNames('store-logo', !logoUrl && 'is-initial')}>
          {logoUrl ? (
            <img src={logoUrl} alt={`${name} logo`} />
          ) : (
            <span aria-hidden="true">{storeInitial}</span>
          )}
        </div>
        <div className="store-meta">
          {loading && !catalog ? (
            <>
              <div className="skeleton-line w-lg" />
              <div className="skeleton-line w-md" />
              <div className="skeleton-line w-sm" />
            </>
          ) : (
            <>
              <h1 className="store-name">{name}</h1>
              <p className="store-tagline">{tagline}</p>
              <p className="store-description">{description}</p>
              {branchName && (
                <p className="store-branch">
                  <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M17.657 16.657L13.414 20.9a2 2 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                    />
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                  </svg>
                  {branchName}
                </p>
              )}
            </>
          )}
        </div>
      </div>
    </header>
  )
}
