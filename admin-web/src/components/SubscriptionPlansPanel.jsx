import { useCallback, useEffect, useMemo, useState } from 'react'
import { friendlyError } from '../utils/errors'

const FEATURE_LABELS = {
  pos: 'POS',
  products: 'Products',
  categories: 'Categories',
  purchases: 'Purchases',
  sales: 'Sales',
  dashboard: 'Dashboard',
  kopesha: 'Kopesha',
  profit_loss: 'Profit & Loss',
  reports: 'Reports',
  settings: 'Settings',
  shifts: 'Shifts',
  services: 'Services',
  agent: 'Piki AI',
  stock_list: 'Stock List',
  transfers: 'Transfers',
  branches: 'Branches',
  audit_logs: 'Audit Logs',
  proactive_piki: 'Proactive Piki',
}

const defaultFeatures = Object.keys(FEATURE_LABELS)

const SELLING_MODE_LABELS = {
  products: 'Products only',
  services: 'Services only',
  combo: 'Products + Services',
}

const defaultSellingModes = Object.keys(SELLING_MODE_LABELS)

const GATEWAY_FIELDS = {
  mpesa: {
    public: [
      ['baseUrl', 'Daraja Base URL'],
      ['shortcode', 'Shortcode'],
      ['callbackUrl', 'Callback URL'],
    ],
    secret: [
      ['consumerKey', 'Consumer Key'],
      ['consumerSecret', 'Consumer Secret'],
      ['passkey', 'Passkey'],
    ],
  },
  google_pay: {
    public: [
      ['environment', 'Environment'],
      ['merchantId', 'Merchant ID'],
      ['merchantName', 'Merchant Name'],
      ['gateway', 'Gateway'],
      ['gatewayMerchantId', 'Gateway Merchant ID'],
    ],
    secret: [
      ['gatewayChargeUrl', 'Gateway Charge URL'],
      ['gatewayApiKey', 'Gateway API Key'],
    ],
  },
}

const MESSAGE_GATEWAY_FIELDS = {
  whatsapp: {
    public: [
      ['baseUrl', 'Graph API Base URL'],
      ['apiVersion', 'API Version'],
      ['phoneNumberId', 'Phone Number ID'],
    ],
    secret: [['accessToken', 'Access Token']],
  },
  africas_talking: {
    public: [
      ['baseUrl', 'Messaging URL'],
      ['username', 'Username'],
      ['senderId', 'Default Sender ID'],
    ],
    secret: [['apiKey', 'API Key']],
  },
}

function clonePlan(plan) {
  if (!plan) return null
  return JSON.parse(JSON.stringify(plan))
}

function cloneGateway(gateway) {
  if (!gateway) return null
  return {
    ...JSON.parse(JSON.stringify(gateway)),
    countriesInput: (gateway.countries || []).join(', '),
  }
}

function priceFor(plan, countryCode, provider) {
  return (plan.prices || []).find(
    (price) => price.countryCode === countryCode && price.provider === provider,
  )
}

function upsertPrice(plan, nextPrice) {
  const prices = (plan.prices || []).filter(
    (price) =>
      !(
        price.countryCode === nextPrice.countryCode &&
        price.provider === nextPrice.provider &&
        price.billingPeriod === nextPrice.billingPeriod
      ),
  )
  return {
    ...plan,
    prices: [...prices, nextPrice],
  }
}

function isHttpsUrl(value) {
  try {
    return new URL(String(value || '')).protocol === 'https:'
  } catch {
    return false
  }
}

function gatewayConfigurationError(gateway) {
  if (!gateway?.isActive) return ''

  if (gateway.provider === 'mpesa') {
    const publicConfig = gateway.publicConfig || {}
    const secretConfig = gateway.secretConfig || {}
    const missing = []
    if (!publicConfig.baseUrl) missing.push('Daraja base URL')
    if (!publicConfig.shortcode) missing.push('shortcode')
    if (!publicConfig.callbackUrl) missing.push('callback URL')
    if (!secretConfig.consumerKey) missing.push('consumer key')
    if (!secretConfig.consumerSecret) missing.push('consumer secret')
    if (!secretConfig.passkey) missing.push('passkey')
    if (missing.length) {
      return `Complete M-Pesa settings before enabling: ${missing.join(', ')}.`
    }
    if (!isHttpsUrl(publicConfig.baseUrl)) {
      return 'Daraja base URL must be a valid HTTPS URL.'
    }
    if (!isHttpsUrl(publicConfig.callbackUrl)) {
      return 'M-Pesa callback URL must be a valid HTTPS URL.'
    }
  }

  if (gateway.provider === 'google_pay') {
    const publicConfig = gateway.publicConfig || {}
    const secretConfig = gateway.secretConfig || {}
    const missing = []
    if (!publicConfig.merchantId) missing.push('merchant ID')
    if (!publicConfig.gateway || publicConfig.gateway === 'example') {
      missing.push('payment gateway')
    }
    if (
      !publicConfig.gatewayMerchantId ||
      publicConfig.gatewayMerchantId === 'exampleGatewayMerchantId'
    ) {
      missing.push('gateway merchant ID')
    }
    if (missing.length) {
      return `Complete Google Pay settings before enabling: ${missing.join(', ')}.`
    }
    if (
      secretConfig.gatewayChargeUrl &&
      !isHttpsUrl(secretConfig.gatewayChargeUrl)
    ) {
      return 'Google Pay charge URL must be a valid HTTPS URL.'
    }
  }

  return ''
}

export default function SubscriptionPlansPanel({ token }) {
  const [plans, setPlans] = useState([])
  const [features, setFeatures] = useState(defaultFeatures)
  const [subscriptionSettings, setSubscriptionSettings] = useState({
    trialDays: 30,
  })
  const [gateways, setGateways] = useState([])
  const [gatewayDrafts, setGatewayDrafts] = useState({})
  const [messageGateways, setMessageGateways] = useState([])
  const [messageGatewayDrafts, setMessageGatewayDrafts] = useState({})
  const [selectedCode, setSelectedCode] = useState('')
  const [draft, setDraft] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savingSubscriptionSettings, setSavingSubscriptionSettings] =
    useState(false)
  const [savingGateway, setSavingGateway] = useState('')
  const [savingMessageGateway, setSavingMessageGateway] = useState('')
  const [message, setMessage] = useState('')

  const selectedPlan = useMemo(
    () => plans.find((plan) => plan.code === selectedCode) || plans[0] || null,
    [plans, selectedCode],
  )

  const loadPlans = useCallback(async () => {
    setLoading(true)
    setMessage('')
    try {
      const headers = { Authorization: `Bearer ${token}` }
      const loadApi = async (url) => {
        const response = await fetch(url, { headers })
        const body = await response.json().catch(() => ({}))
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || `Could not load ${url}`)
        }
        return body
      }
      const [
        plansResult,
        subscriptionSettingsResult,
        gatewayResult,
        messageGatewayResult,
      ] =
        await Promise.allSettled([
          loadApi('/api/platform/plans'),
          loadApi('/api/platform/subscription-settings'),
          loadApi('/api/platform/payment-gateways'),
          loadApi('/api/platform/message-gateways'),
        ])
      if (plansResult.status === 'rejected') {
        throw plansResult.reason
      }
      const body = plansResult.value
      const nextPlans = body.data || []
      setPlans(nextPlans)
      setFeatures(body.features || defaultFeatures)
      const nextSelected = nextPlans[0]?.code || ''
      setSelectedCode(nextSelected)
      setDraft(clonePlan(nextPlans.find((plan) => plan.code === nextSelected) || nextPlans[0]))

      if (subscriptionSettingsResult.status === 'fulfilled') {
        setSubscriptionSettings(subscriptionSettingsResult.value.data)
      }
      if (gatewayResult.status === 'fulfilled') {
        const nextGateways = gatewayResult.value.data || []
        setGateways(nextGateways)
        setGatewayDrafts(
          Object.fromEntries(
            nextGateways.map((gateway) => [gateway.provider, cloneGateway(gateway)]),
          ),
        )
      }
      if (messageGatewayResult.status === 'fulfilled') {
        const nextMessageGateways = messageGatewayResult.value.data || []
        setMessageGateways(nextMessageGateways)
        setMessageGatewayDrafts(
          Object.fromEntries(
            nextMessageGateways.map((gateway) => [
              gateway.provider,
              cloneGateway(gateway),
            ]),
          ),
        )
      }
      const failures = [
        subscriptionSettingsResult,
        gatewayResult,
        messageGatewayResult,
      ]
        .filter((item) => item.status === 'rejected')
        .map((item) => friendlyError(item.reason, 'Some settings could not be loaded.'))
        .filter(Boolean)
      if (failures.length > 0) {
        setMessage(failures.join(' | '))
      }
    } catch (error) {
      setMessage(friendlyError(error, 'Could not load subscription plans.'))
    } finally {
      setLoading(false)
    }
  }, [token])

  useEffect(() => {
    loadPlans()
  }, [loadPlans])

  useEffect(() => {
    if (selectedPlan) {
      setDraft(clonePlan(selectedPlan))
    }
  }, [selectedPlan])

  const updateDraft = (patch) => {
    setDraft((current) => ({ ...current, ...patch }))
  }

  const saveSubscriptionSettings = async () => {
    setSavingSubscriptionSettings(true)
    setMessage('')
    try {
      const response = await fetch('/api/platform/subscription-settings', {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(subscriptionSettings),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save subscription settings')
      }
      setSubscriptionSettings(body.data)
      setMessage('Subscription settings saved')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save subscription settings.'))
    } finally {
      setSavingSubscriptionSettings(false)
    }
  }

  const updateFeature = (feature, enabled) => {
    setDraft((current) => {
      const currentFeatures = current.features || []
      const nextFeatures = enabled
        ? Array.from(new Set([...currentFeatures, feature]))
        : currentFeatures.filter((item) => item !== feature)
      return { ...current, features: nextFeatures }
    })
  }

  const updateSellingMode = (mode, enabled) => {
    setDraft((current) => {
      const currentModes = current.sellingModes || defaultSellingModes
      const nextModes = enabled
        ? Array.from(new Set([...currentModes, mode]))
        : currentModes.filter((item) => item !== mode)
      return { ...current, sellingModes: nextModes.length ? nextModes : currentModes }
    })
  }

  const updateMoney = (countryCode, provider, currency, amountMajor) => {
    setDraft((current) => {
      const existing =
        priceFor(current, countryCode, provider) || {
          countryCode,
          provider,
          currency,
          billingPeriod: 'monthly',
          isActive: true,
        }
      return upsertPrice(current, {
        ...existing,
        currency,
        amountMinor: Math.max(0, Math.round(Number(amountMajor || 0) * 100)),
      })
    })
  }

  const savePlan = async () => {
    if (!draft) return
    setSaving(true)
    setMessage('')
    try {
      const response = await fetch(`/api/platform/plans/${draft.code}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(draft),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save subscription plan')
      }
      setPlans((current) =>
        current.map((plan) => (plan.code === body.data.code ? body.data : plan)),
      )
      setDraft(clonePlan(body.data))
      setMessage('Plan saved')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save subscription plan.'))
    } finally {
      setSaving(false)
    }
  }

  const updateGatewayDraft = (provider, patch) => {
    setGatewayDrafts((current) => ({
      ...current,
      [provider]: {
        ...(current[provider] || {}),
        ...patch,
      },
    }))
  }

  const updateGatewayConfig = (provider, group, key, value) => {
    setGatewayDrafts((current) => {
      const gateway = current[provider] || {}
      return {
        ...current,
        [provider]: {
          ...gateway,
          [group]: {
            ...(gateway[group] || {}),
            [key]: value,
          },
        },
      }
    })
  }

  const saveGateway = async (provider) => {
    const gateway = gatewayDrafts[provider]
    if (!gateway) return
    setSavingGateway(provider)
    setMessage('')
    try {
      const validationError = gatewayConfigurationError(gateway)
      if (validationError) {
        throw new Error(validationError)
      }
      const response = await fetch(`/api/platform/payment-gateways/${provider}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          displayName: gateway.displayName,
          isActive: gateway.isActive,
          countries: String(gateway.countriesInput || '')
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean),
          publicConfig: gateway.publicConfig || {},
          secretConfig: gateway.secretConfig || {},
        }),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save payment gateway')
      }
      const nextGateway = body.data
      setGateways((current) =>
        current.map((item) =>
          item.provider === nextGateway.provider ? nextGateway : item,
        ),
      )
      setGatewayDrafts((current) => ({
        ...current,
        [nextGateway.provider]: cloneGateway(nextGateway),
      }))
      setMessage('Payment gateway saved')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save payment gateway.'))
    } finally {
      setSavingGateway('')
    }
  }

  const updateMessageGatewayDraft = (provider, patch) => {
    setMessageGatewayDrafts((current) => ({
      ...current,
      [provider]: {
        ...(current[provider] || {}),
        ...patch,
      },
    }))
  }

  const updateMessageGatewayConfig = (provider, group, key, value) => {
    setMessageGatewayDrafts((current) => {
      const gateway = current[provider] || {}
      return {
        ...current,
        [provider]: {
          ...gateway,
          [group]: {
            ...(gateway[group] || {}),
            [key]: value,
          },
        },
      }
    })
  }

  const saveMessageGateway = async (provider) => {
    const gateway = messageGatewayDrafts[provider]
    if (!gateway) return
    setSavingMessageGateway(provider)
    setMessage('')
    try {
      const response = await fetch(`/api/platform/message-gateways/${provider}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          displayName: gateway.displayName,
          isActive: gateway.isActive,
          countries: String(gateway.countriesInput || '')
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean),
          publicConfig: gateway.publicConfig || {},
          secretConfig: gateway.secretConfig || {},
        }),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save message gateway')
      }
      const nextGateway = body.data
      setMessageGateways((current) =>
        current.map((item) =>
          item.provider === nextGateway.provider ? nextGateway : item,
        ),
      )
      setMessageGatewayDrafts((current) => ({
        ...current,
        [nextGateway.provider]: cloneGateway(nextGateway),
      }))
      setMessage('Message gateway saved')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save message gateway.'))
    } finally {
      setSavingMessageGateway('')
    }
  }

  if (loading) {
    return <div style={{ color: 'var(--text-muted)' }}>Loading plans...</div>
  }

  if (!draft) {
    return <div style={{ color: 'var(--text-muted)' }}>No plans found.</div>
  }

  const kenyaPrice = priceFor(draft, 'KE', 'mpesa') || { amountMinor: 0 }
  const googlePrice =
    priceFor(draft, 'GLOBAL', 'google_pay') || { amountMinor: 0 }

  return (
    <div className="subscription-admin-stack">
      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>New Shop Trial</h3>
            <p>
              Choose how long new shops can use the trial plan. Existing
              subscriptions keep their current expiry dates.
            </p>
          </div>
        </div>
        <div className="editor-grid">
          <label className="form-group">
            <span className="form-label">Trial Period (days)</span>
            <input
              className="form-input"
              type="number"
              min="1"
              max="365"
              step="1"
              value={subscriptionSettings.trialDays ?? 30}
              onChange={(event) =>
                setSubscriptionSettings((current) => ({
                  ...current,
                  trialDays: Number(event.target.value),
                }))
              }
            />
          </label>
        </div>
        <div className="editor-actions">
          <span className="gateway-status">
            Applies when a new business starts its free trial.
          </span>
          <button
            className="btn btn-primary"
            disabled={savingSubscriptionSettings}
            onClick={saveSubscriptionSettings}
          >
            {savingSubscriptionSettings ? 'Saving...' : 'Save Trial Period'}
          </button>
        </div>
      </section>

      <div className="plans-layout">
        <div className="plans-sidebar">
          {plans.map((plan) => (
            <button
              key={plan.code}
              className={`plan-row ${draft.code === plan.code ? 'is-active' : ''}`}
              onClick={() => setSelectedCode(plan.code)}
            >
              <span>{plan.name}</span>
              <small>{plan.isActive ? 'Active' : 'Hidden'}</small>
            </button>
          ))}
        </div>

        <div className="plan-editor">
          <div className="editor-grid">
            <label className="form-group">
              <span className="form-label">Name</span>
              <input
                className="form-input"
                value={draft.name || ''}
                onChange={(event) => updateDraft({ name: event.target.value })}
              />
            </label>
            <label className="form-group">
              <span className="form-label">Sort Order</span>
              <input
                className="form-input"
                type="number"
                value={draft.sortOrder ?? 0}
                onChange={(event) =>
                  updateDraft({ sortOrder: Number(event.target.value) })
                }
              />
            </label>
          </div>

          <label className="form-group">
            <span className="form-label">Description</span>
            <input
              className="form-input"
              value={draft.description || ''}
              onChange={(event) => updateDraft({ description: event.target.value })}
            />
          </label>

          <div className="editor-grid">
            {[
              ['maxBranches', 'Branches'],
              ['maxEmployees', 'Employees'],
              ['maxAiAgents', 'AI seats'],
              ['aiRateHourly', 'AI hourly'],
              ['aiRateWeekly', 'AI weekly'],
              ['aiRateMonthly', 'AI monthly'],
            ].map(([key, label]) => (
              <label className="form-group" key={key}>
                <span className="form-label">{label}</span>
                <input
                  className="form-input"
                  type="number"
                  min="0"
                  value={draft[key] ?? 0}
                  onChange={(event) => updateDraft({ [key]: Number(event.target.value) })}
                />
              </label>
            ))}
          </div>

          <div className="editor-grid">
            <label className="form-group">
              <span className="form-label">Kenya M-Pesa Price (KES)</span>
              <input
                className="form-input"
                type="number"
                min="0"
                step="1"
                value={(kenyaPrice.amountMinor || 0) / 100}
                onChange={(event) =>
                  updateMoney('KE', 'mpesa', 'KES', event.target.value)
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Google Pay Price (USD)</span>
              <input
                className="form-input"
                type="number"
                min="0"
                step="0.01"
                value={((googlePrice.amountMinor || 0) / 100).toFixed(2)}
                onChange={(event) =>
                  updateMoney('GLOBAL', 'google_pay', 'USD', event.target.value)
                }
              />
            </label>
          </div>

          <div className="feature-grid">
            {features.map((feature) => (
              <label key={feature} className="feature-toggle">
                <input
                  type="checkbox"
                  checked={(draft.features || []).includes(feature)}
                  onChange={(event) => updateFeature(feature, event.target.checked)}
                />
                <span>{FEATURE_LABELS[feature] || feature}</span>
              </label>
            ))}
          </div>

          <div className="selling-mode-panel">
            <div className="gateway-panel-header">
              <div>
                <h3>Selling Modes</h3>
                <p>Registration can offer only the modes this plan and its features support.</p>
              </div>
            </div>
            <div className="feature-grid">
              {defaultSellingModes.map((mode) => (
                <label key={mode} className="feature-toggle">
                  <input
                    type="checkbox"
                    checked={(draft.sellingModes || defaultSellingModes).includes(mode)}
                    onChange={(event) => updateSellingMode(mode, event.target.checked)}
                  />
                  <span>{SELLING_MODE_LABELS[mode]}</span>
                </label>
              ))}
            </div>
          </div>

          <div className="editor-actions">
            <label className="feature-toggle">
              <input
                type="checkbox"
                checked={draft.isActive !== false}
                onChange={(event) => updateDraft({ isActive: event.target.checked })}
              />
              <span>Visible for checkout</span>
            </label>
            <button className="btn btn-primary" disabled={saving} onClick={savePlan}>
              {saving ? 'Saving...' : 'Save Plan'}
            </button>
          </div>
        </div>
      </div>

      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>Payment Gateways</h3>
            <p>Only enabled gateways with active plan prices appear in the POS app.</p>
          </div>
        </div>
        <div className="gateway-grid">
          {gateways.map((gateway) => {
            const gatewayDraft = gatewayDrafts[gateway.provider] || cloneGateway(gateway)
            const fields = GATEWAY_FIELDS[gateway.provider] || { public: [], secret: [] }
            return (
              <div className="gateway-card" key={gateway.provider}>
                <div className="gateway-card-header">
                  <label className="feature-toggle">
                    <input
                      type="checkbox"
                      checked={gatewayDraft.isActive === true}
                      onChange={(event) =>
                        updateGatewayDraft(gateway.provider, {
                          isActive: event.target.checked,
                        })
                      }
                    />
                    <span>{gatewayDraft.displayName}</span>
                  </label>
                  <small>{gateway.provider}</small>
                </div>

                <div className="editor-grid">
                  <label className="form-group">
                    <span className="form-label">Display Name</span>
                    <input
                      className="form-input"
                      value={gatewayDraft.displayName || ''}
                      onChange={(event) =>
                        updateGatewayDraft(gateway.provider, {
                          displayName: event.target.value,
                        })
                      }
                    />
                  </label>
                  <label className="form-group">
                    <span className="form-label">Countries</span>
                    <input
                      className="form-input"
                      value={gatewayDraft.countriesInput || ''}
                      onChange={(event) =>
                        updateGatewayDraft(gateway.provider, {
                          countriesInput: event.target.value,
                        })
                      }
                    />
                  </label>
                </div>

                <div className="gateway-field-grid">
                  {fields.public.map(([key, label]) => (
                    <label className="form-group" key={key}>
                      <span className="form-label">{label}</span>
                      <input
                        className="form-input"
                        type={key.toLowerCase().includes('url') ? 'url' : 'text'}
                        value={gatewayDraft.publicConfig?.[key] || ''}
                        onChange={(event) =>
                          updateGatewayConfig(
                            gateway.provider,
                            'publicConfig',
                            key,
                            event.target.value,
                          )
                        }
                      />
                    </label>
                  ))}
                  {fields.secret.map(([key, label]) => (
                    <label className="form-group" key={key}>
                      <span className="form-label">{label}</span>
                      <input
                        className="form-input"
                        type={key.toLowerCase().includes('url') ? 'url' : 'password'}
                        value={gatewayDraft.secretConfig?.[key] || ''}
                        onChange={(event) =>
                          updateGatewayConfig(
                            gateway.provider,
                            'secretConfig',
                            key,
                            event.target.value,
                          )
                        }
                      />
                    </label>
                  ))}
                </div>

                <div className="editor-actions">
                  <span className="gateway-status">
                    {gatewayDraft.isActive ? 'Visible to app' : 'Hidden from app'}
                  </span>
                  <button
                    className="btn btn-primary"
                    disabled={savingGateway === gateway.provider}
                    onClick={() => saveGateway(gateway.provider)}
                  >
                    {savingGateway === gateway.provider ? 'Saving...' : 'Save Gateway'}
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      </section>

      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>Message Gateways</h3>
            <p>Configure provider-backed WhatsApp and SMS sending for businesses that enable API messaging.</p>
          </div>
        </div>
        <div className="gateway-grid">
          {messageGateways.map((gateway) => {
            const gatewayDraft =
              messageGatewayDrafts[gateway.provider] || cloneGateway(gateway)
            const fields = MESSAGE_GATEWAY_FIELDS[gateway.provider] || {
              public: [],
              secret: [],
            }
            return (
              <div className="gateway-card" key={gateway.provider}>
                <div className="gateway-card-header">
                  <label className="feature-toggle">
                    <input
                      type="checkbox"
                      checked={gatewayDraft.isActive === true}
                      onChange={(event) =>
                        updateMessageGatewayDraft(gateway.provider, {
                          isActive: event.target.checked,
                        })
                      }
                    />
                    <span>{gatewayDraft.displayName}</span>
                  </label>
                  <small>{gateway.provider}</small>
                </div>

                <div className="editor-grid">
                  <label className="form-group">
                    <span className="form-label">Display Name</span>
                    <input
                      className="form-input"
                      value={gatewayDraft.displayName || ''}
                      onChange={(event) =>
                        updateMessageGatewayDraft(gateway.provider, {
                          displayName: event.target.value,
                        })
                      }
                    />
                  </label>
                  <label className="form-group">
                    <span className="form-label">Countries</span>
                    <input
                      className="form-input"
                      value={gatewayDraft.countriesInput || ''}
                      onChange={(event) =>
                        updateMessageGatewayDraft(gateway.provider, {
                          countriesInput: event.target.value,
                        })
                      }
                    />
                  </label>
                </div>

                <div className="gateway-field-grid">
                  {fields.public.map(([key, label]) => (
                    <label className="form-group" key={key}>
                      <span className="form-label">{label}</span>
                      <input
                        className="form-input"
                        value={gatewayDraft.publicConfig?.[key] || ''}
                        onChange={(event) =>
                          updateMessageGatewayConfig(
                            gateway.provider,
                            'publicConfig',
                            key,
                            event.target.value,
                          )
                        }
                      />
                    </label>
                  ))}
                  {fields.secret.map(([key, label]) => (
                    <label className="form-group" key={key}>
                      <span className="form-label">{label}</span>
                      <input
                        className="form-input"
                        type="password"
                        value={gatewayDraft.secretConfig?.[key] || ''}
                        onChange={(event) =>
                          updateMessageGatewayConfig(
                            gateway.provider,
                            'secretConfig',
                            key,
                            event.target.value,
                          )
                        }
                      />
                    </label>
                  ))}
                </div>

                <div className="editor-actions">
                  <span className="gateway-status">
                    {gatewayDraft.isActive ? 'API sending enabled' : 'API sending hidden'}
                  </span>
                  <button
                    className="btn btn-primary"
                    disabled={savingMessageGateway === gateway.provider}
                    onClick={() => saveMessageGateway(gateway.provider)}
                  >
                    {savingMessageGateway === gateway.provider
                      ? 'Saving...'
                      : 'Save Gateway'}
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      </section>

      {message && <div className="admin-message">{message}</div>}
    </div>
  )
}
