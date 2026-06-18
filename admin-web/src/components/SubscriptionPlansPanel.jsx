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
  google_play: {
    public: [['packageName', 'Android Package Name']],
    secret: [
      ['serviceAccountEmail', 'Service Account Email'],
      ['serviceAccountPrivateKey', 'Service Account Private Key'],
    ],
  },
  paypal: {
    public: [['baseUrl', 'PayPal API Base URL']],
    secret: [
      ['clientId', 'Client ID'],
      ['clientSecret', 'Client Secret'],
    ],
  },
  flutterwave: {
    public: [['baseUrl', 'Flutterwave API Base URL']],
    secret: [['secretKey', 'Secret Key']],
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

const DEFAULT_ETIMS_CONFIG = {
  providerName: 'KRA eTIMS OSCU/VSCU',
  isActive: false,
  baseUrl: '',
  submitPath: '/invoices',
  publicConfig: {
    authHeaderName: 'Authorization',
    authHeaderPrefix: 'Bearer',
    timeoutMs: '20000',
  },
  secretConfig: {
    apiKey: '',
  },
}

function clonePlan(plan) {
  if (!plan) return null
  const cloned = JSON.parse(JSON.stringify(plan))
  cloned.prices = (cloned.prices || []).filter(
    (price) => price.provider !== 'mpesa' && price.provider !== 'google_pay',
  )
  return cloned
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

  if (gateway.provider === 'google_play') {
    const publicConfig = gateway.publicConfig || {}
    const secretConfig = gateway.secretConfig || {}
    const missing = []
    if (!publicConfig.packageName) missing.push('Android package name')
    if (!secretConfig.serviceAccountEmail) missing.push('service account email')
    if (!secretConfig.serviceAccountPrivateKey) missing.push('service account private key')
    if (missing.length) {
      return `Complete Google Play settings before enabling: ${missing.join(', ')}.`
    }
  }

  if (gateway.provider === 'paypal') {
    if (!isHttpsUrl(gateway.publicConfig?.baseUrl)) return 'PayPal API URL must use HTTPS.'
    if (!gateway.secretConfig?.clientId || !gateway.secretConfig?.clientSecret) {
      return 'PayPal client ID and client secret are required.'
    }
  }

  if (gateway.provider === 'flutterwave') {
    if (!isHttpsUrl(gateway.publicConfig?.baseUrl)) {
      return 'Flutterwave API URL must use HTTPS.'
    }
    if (!gateway.secretConfig?.secretKey) return 'Flutterwave secret key is required.'
  }

  return ''
}

export default function SubscriptionPlansPanel({ token }) {
  const [plans, setPlans] = useState([])
  const [features, setFeatures] = useState(defaultFeatures)
  const [subscriptionSettings, setSubscriptionSettings] = useState({
    trialDays: 30,
    graceDays: 5,
  })
  const [appVersion, setAppVersion] = useState({
    latestVersion: '',
    minimumVersion: '',
    apkUrl: '',
    androidVersion: '',
    androidMinimumVersion: '',
    androidUrl: '',
    windowsVersion: '',
    windowsMinimumVersion: '',
    windowsUrl: '',
    releaseNotes: '',
  })
  const [readiness, setReadiness] = useState(null)
  const [gateways, setGateways] = useState([])
  const [gatewayDrafts, setGatewayDrafts] = useState({})
  const [messageGateways, setMessageGateways] = useState([])
  const [messageGatewayDrafts, setMessageGatewayDrafts] = useState({})
  const [etimsConfig, setEtimsConfig] = useState(DEFAULT_ETIMS_CONFIG)
  const [selectedCode, setSelectedCode] = useState('')
  const [draft, setDraft] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savingSubscriptionSettings, setSavingSubscriptionSettings] =
    useState(false)
  const [savingAppVersion, setSavingAppVersion] = useState(false)
  const [uploadingRelease, setUploadingRelease] = useState('')
  const [savingGateway, setSavingGateway] = useState('')
  const [savingMessageGateway, setSavingMessageGateway] = useState('')
  const [savingEtimsConfig, setSavingEtimsConfig] = useState(false)
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
        etimsResult,
        appVersionResult,
        readinessResult,
      ] =
        await Promise.allSettled([
          loadApi('/api/platform/plans'),
          loadApi('/api/platform/subscription-settings'),
          loadApi('/api/platform/payment-gateways'),
          loadApi('/api/platform/message-gateways'),
          loadApi('/api/platform/etims-config'),
          loadApi('/api/platform/app-version'),
          loadApi('/api/platform/readiness'),
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
        const nextGateways = (gatewayResult.value.data || []).filter(
          (gateway) =>
            gateway.provider !== 'mpesa' && gateway.provider !== 'google_pay',
        )
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
      if (etimsResult.status === 'fulfilled') {
        setEtimsConfig({
          ...DEFAULT_ETIMS_CONFIG,
          ...(etimsResult.value.data || {}),
          publicConfig: {
            ...DEFAULT_ETIMS_CONFIG.publicConfig,
            ...((etimsResult.value.data || {}).publicConfig || {}),
          },
          secretConfig: {
            ...DEFAULT_ETIMS_CONFIG.secretConfig,
            ...((etimsResult.value.data || {}).secretConfig || {}),
          },
        })
      }
      if (appVersionResult.status === 'fulfilled') {
        setAppVersion(appVersionResult.value.data)
      }
      if (readinessResult.status === 'fulfilled') {
        setReadiness(readinessResult.value.data)
      }
      const failures = [
        subscriptionSettingsResult,
        gatewayResult,
        messageGatewayResult,
        etimsResult,
        appVersionResult,
        readinessResult,
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

  const saveAppVersion = async () => {
    setSavingAppVersion(true)
    setMessage('')
    try {
      const response = await fetch('/api/platform/app-version', {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(appVersion),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save app version settings')
      }
      setAppVersion(body.data)
      setMessage('App release settings saved')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save app release settings.'))
    } finally {
      setSavingAppVersion(false)
    }
  }

  const uploadAppRelease = async (platform, file) => {
    if (!file) return
    const isAndroid = platform === 'android'
    const platformLabel = isAndroid ? 'Android APK' : 'Windows app'
    const version = (
      isAndroid
        ? appVersion.androidVersion || appVersion.latestVersion
        : appVersion.windowsVersion
    )?.trim()
    if (!version) {
      setMessage(`Enter the ${platformLabel} latest version before uploading.`)
      return
    }

    setUploadingRelease(platform)
    setMessage('')
    try {
      const params = new URLSearchParams({
        version,
        fileName: file.name || `${platform}-release`,
      })
      const response = await fetch(`/api/platform/app-release/${platform}?${params}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': file.type || 'application/octet-stream',
        },
        body: file,
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || `Could not upload ${platformLabel}`)
      }
      const nextVersion = { ...(body.data || {}) }
      delete nextVersion.upload
      setAppVersion(nextVersion)
      setMessage(`${platformLabel} uploaded and release endpoint updated`)
    } catch (error) {
      setMessage(friendlyError(error, `Could not upload ${platformLabel}.`))
    } finally {
      setUploadingRelease('')
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

  const updateGooglePlayProductId = (storeProductId) => {
    setDraft((current) => ({
      ...current,
      prices: (current.prices || []).map((price) =>
        price.provider === 'google_play' ? { ...price, storeProductId } : price,
      ),
    }))
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

  const updateEtimsConfig = (patch) => {
    setEtimsConfig((current) => ({ ...current, ...patch }))
  }

  const updateEtimsConfigGroup = (group, key, value) => {
    setEtimsConfig((current) => ({
      ...current,
      [group]: {
        ...(current[group] || {}),
        [key]: value,
      },
    }))
  }

  const saveEtimsConfig = async () => {
    setSavingEtimsConfig(true)
    setMessage('')
    try {
      if (etimsConfig.isActive && !isHttpsUrl(etimsConfig.baseUrl)) {
        throw new Error('KRA/eTIMS provider URL must be a valid HTTPS URL.')
      }
      const response = await fetch('/api/platform/etims-config', {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(etimsConfig),
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not save KRA/eTIMS configuration')
      }
      setEtimsConfig({
        ...DEFAULT_ETIMS_CONFIG,
        ...body.data,
        publicConfig: {
          ...DEFAULT_ETIMS_CONFIG.publicConfig,
          ...(body.data.publicConfig || {}),
        },
        secretConfig: {
          ...DEFAULT_ETIMS_CONFIG.secretConfig,
          ...(body.data.secretConfig || {}),
        },
      })
      setMessage('KRA/eTIMS connector saved')
      loadPlans()
    } catch (error) {
      setMessage(friendlyError(error, 'Could not save KRA/eTIMS configuration.'))
    } finally {
      setSavingEtimsConfig(false)
    }
  }

  if (loading) {
    return <div style={{ color: 'var(--text-muted)' }}>Loading plans...</div>
  }

  if (!draft) {
    return <div style={{ color: 'var(--text-muted)' }}>No plans found.</div>
  }

  const playKenyaPrice = priceFor(draft, 'KE', 'google_play') || { amountMinor: 0 }
  const playGlobalPrice = priceFor(draft, 'GLOBAL', 'google_play') || { amountMinor: 0 }
  const flutterwaveKenyaPrice = priceFor(draft, 'KE', 'flutterwave') || { amountMinor: 0 }
  const flutterwaveGlobalPrice = priceFor(draft, 'GLOBAL', 'flutterwave') || { amountMinor: 0 }
  const paypalGlobalPrice = priceFor(draft, 'GLOBAL', 'paypal') || { amountMinor: 0 }
  const googlePlayProductId = playKenyaPrice.storeProductId || playGlobalPrice.storeProductId || ''

  return (
    <div className="subscription-admin-stack">
      {readiness && (
        <section className="gateway-panel">
          <div className="gateway-panel-header">
            <div>
              <h3>Production Readiness</h3>
              <p>
                Launch status: {readiness.status === 'ready'
                  ? 'ready'
                  : readiness.status === 'blocked'
                    ? 'blocked'
                    : 'needs attention'}.
                {' '}
                {readiness.criticalCount || 0} critical,
                {' '}
                {readiness.warningCount || 0} warning.
              </p>
            </div>
          </div>
          <div className="gateway-grid">
            {(readiness.checks || []).map((check) => (
              <div className="gateway-card" key={check.key}>
                <div className="gateway-card-header">
                  <strong>{check.label}</strong>
                  <span className="gateway-status">
                    {check.status === 'pass'
                      ? 'OK'
                      : check.status === 'fail'
                        ? 'Blocker'
                        : 'Warning'}
                  </span>
                </div>
                <p>{check.message}</p>
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>New Shop Trial</h3>
            <p>
              Choose how long new shops can use the trial plan and how long
              they can keep working before the app becomes read-only.
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
          <label className="form-group">
            <span className="form-label">Grace Period (days)</span>
            <input
              className="form-input"
              type="number"
              min="0"
              max="30"
              step="1"
              value={subscriptionSettings.graceDays ?? 5}
              onChange={(event) =>
                setSubscriptionSettings((current) => ({
                  ...current,
                  graceDays: Number(event.target.value),
                }))
              }
            />
          </label>
        </div>
        <div className="editor-actions">
          <span className="gateway-status">
            Existing subscriptions keep their current expiry dates.
          </span>
          <button
            className="btn btn-primary"
            disabled={savingSubscriptionSettings}
            onClick={saveSubscriptionSettings}
          >
            {savingSubscriptionSettings ? 'Saving...' : 'Save Trial Settings'}
          </button>
        </div>
      </section>

      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>Hosted App Releases</h3>
            <p>
              Upload signed Android APKs and Windows installers. The app checks
              this endpoint and prompts users when a newer version is available.
            </p>
          </div>
        </div>
        <div className="gateway-card">
          <div className="gateway-card-header">
            <strong>Android APK</strong>
            <small>
              {appVersion.androidUrl || appVersion.apkUrl
                ? 'Hosted'
                : 'Not uploaded'}
            </small>
          </div>
          <div className="editor-grid">
            <label className="form-group">
              <span className="form-label">Latest Version</span>
              <input
                className="form-input"
                placeholder="1.0.1+2"
                value={appVersion.androidVersion || appVersion.latestVersion || ''}
                onChange={(event) =>
                  setAppVersion((current) => ({
                    ...current,
                    latestVersion: event.target.value,
                    androidVersion: event.target.value,
                  }))
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Minimum Supported Version</span>
              <input
                className="form-input"
                placeholder="1.0.0+1"
                value={
                  appVersion.androidMinimumVersion ||
                  appVersion.minimumVersion ||
                  ''
                }
                onChange={(event) =>
                  setAppVersion((current) => ({
                    ...current,
                    minimumVersion: event.target.value,
                    androidMinimumVersion: event.target.value,
                  }))
                }
              />
            </label>
          </div>
          <label className="form-group">
            <span className="form-label">APK Download URL</span>
            <input
              className="form-input"
              placeholder="/downloads/app/android/..."
              value={appVersion.androidUrl || appVersion.apkUrl || ''}
              onChange={(event) =>
                setAppVersion((current) => ({
                  ...current,
                  apkUrl: event.target.value,
                  androidUrl: event.target.value,
                }))
              }
            />
          </label>
          <label className="form-group">
            <span className="form-label">Upload Signed APK</span>
            <input
              className="form-input"
              type="file"
              accept=".apk"
              disabled={uploadingRelease === 'android'}
              onChange={(event) => {
                uploadAppRelease('android', event.target.files?.[0])
                event.target.value = ''
              }}
            />
          </label>
        </div>
        <div className="gateway-card">
          <div className="gateway-card-header">
            <strong>Windows App</strong>
            <small>{appVersion.windowsUrl ? 'Hosted' : 'Not uploaded'}</small>
          </div>
          <div className="editor-grid">
            <label className="form-group">
              <span className="form-label">Latest Version</span>
              <input
                className="form-input"
                placeholder="1.0.1"
                value={appVersion.windowsVersion || ''}
                onChange={(event) =>
                  setAppVersion((current) => ({
                    ...current,
                    windowsVersion: event.target.value,
                  }))
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Minimum Supported Version</span>
              <input
                className="form-input"
                placeholder="1.0.0"
                value={appVersion.windowsMinimumVersion || ''}
                onChange={(event) =>
                  setAppVersion((current) => ({
                    ...current,
                    windowsMinimumVersion: event.target.value,
                  }))
                }
              />
            </label>
          </div>
          <label className="form-group">
            <span className="form-label">Windows Download URL</span>
            <input
              className="form-input"
              placeholder="/downloads/app/windows/..."
              value={appVersion.windowsUrl || ''}
              onChange={(event) =>
                setAppVersion((current) => ({
                  ...current,
                  windowsUrl: event.target.value,
                }))
              }
            />
          </label>
          <label className="form-group">
            <span className="form-label">Upload Windows Installer</span>
            <input
              className="form-input"
              type="file"
              accept=".zip,.exe,.msi"
              disabled={uploadingRelease === 'windows'}
              onChange={(event) => {
                uploadAppRelease('windows', event.target.files?.[0])
                event.target.value = ''
              }}
            />
          </label>
        </div>
        <label className="form-group">
          <span className="form-label">Release Notes</span>
          <textarea
            className="form-input"
            rows="3"
            value={appVersion.releaseNotes || ''}
            onChange={(event) =>
              setAppVersion((current) => ({
                ...current,
                releaseNotes: event.target.value,
              }))
            }
          />
        </label>
        <div className="editor-actions">
          <span className="gateway-status">
            {uploadingRelease
              ? 'Uploading release file...'
              : (appVersion.androidUrl || appVersion.apkUrl) &&
                  appVersion.windowsUrl
                ? 'Android and Windows release endpoints are configured.'
                : 'Upload Android and Windows builds before production rollout.'}
          </span>
          <button
            className="btn btn-primary"
            disabled={savingAppVersion || Boolean(uploadingRelease)}
            onClick={saveAppVersion}
          >
            {savingAppVersion ? 'Saving...' : 'Save Release Settings'}
          </button>
        </div>
      </section>

      <section className="gateway-panel">
        <div className="gateway-panel-header">
          <div>
            <h3>KRA eTIMS Connector</h3>
            <p>
              Configure the certified OSCU/VSCU provider endpoint. Shops only
              enter their KRA PIN and device serial inside the POS app.
            </p>
          </div>
        </div>
        <div className="gateway-card">
          <div className="gateway-card-header">
            <label className="feature-toggle">
              <input
                type="checkbox"
                checked={etimsConfig.isActive === true}
                onChange={(event) =>
                  updateEtimsConfig({ isActive: event.target.checked })
                }
              />
              <span>{etimsConfig.providerName || 'KRA eTIMS OSCU/VSCU'}</span>
            </label>
            <small>{etimsConfig.isActive ? 'Active' : 'Inactive'}</small>
          </div>
          <div className="editor-grid">
            <label className="form-group">
              <span className="form-label">Provider Name</span>
              <input
                className="form-input"
                value={etimsConfig.providerName || ''}
                onChange={(event) =>
                  updateEtimsConfig({ providerName: event.target.value })
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Provider Base URL</span>
              <input
                className="form-input"
                type="url"
                placeholder="https://..."
                value={etimsConfig.baseUrl || ''}
                onChange={(event) =>
                  updateEtimsConfig({ baseUrl: event.target.value })
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Submit Path</span>
              <input
                className="form-input"
                value={etimsConfig.submitPath || '/invoices'}
                onChange={(event) =>
                  updateEtimsConfig({ submitPath: event.target.value })
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Timeout (ms)</span>
              <input
                className="form-input"
                type="number"
                min="5000"
                step="1000"
                value={etimsConfig.publicConfig?.timeoutMs || '20000'}
                onChange={(event) =>
                  updateEtimsConfigGroup(
                    'publicConfig',
                    'timeoutMs',
                    event.target.value,
                  )
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Auth Header</span>
              <input
                className="form-input"
                value={etimsConfig.publicConfig?.authHeaderName || 'Authorization'}
                onChange={(event) =>
                  updateEtimsConfigGroup(
                    'publicConfig',
                    'authHeaderName',
                    event.target.value,
                  )
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">Auth Prefix</span>
              <input
                className="form-input"
                placeholder="Bearer"
                value={etimsConfig.publicConfig?.authHeaderPrefix || ''}
                onChange={(event) =>
                  updateEtimsConfigGroup(
                    'publicConfig',
                    'authHeaderPrefix',
                    event.target.value,
                  )
                }
              />
            </label>
            <label className="form-group">
              <span className="form-label">API Key / Token</span>
              <input
                className="form-input"
                type="password"
                value={etimsConfig.secretConfig?.apiKey || ''}
                onChange={(event) =>
                  updateEtimsConfigGroup(
                    'secretConfig',
                    'apiKey',
                    event.target.value,
                  )
                }
              />
            </label>
          </div>
          <div className="editor-actions">
            <span className="gateway-status">
              {etimsConfig.isActive
                ? 'Provider will be used for live KRA/eTIMS sale submissions.'
                : 'Inactive: shops can save KRA details but submissions remain pending configuration.'}
            </span>
            <button
              className="btn btn-primary"
              disabled={savingEtimsConfig}
              onClick={saveEtimsConfig}
            >
              {savingEtimsConfig ? 'Saving...' : 'Save KRA eTIMS'}
            </button>
          </div>
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
            {[
              ['Kenya Google Play Price (KES)', 'KE', 'google_play', 'KES', playKenyaPrice, '1'],
              ['Global Google Play Price (USD)', 'GLOBAL', 'google_play', 'USD', playGlobalPrice, '0.01'],
              ['Kenya Flutterwave Price (KES)', 'KE', 'flutterwave', 'KES', flutterwaveKenyaPrice, '1'],
              ['Global Flutterwave Price (USD)', 'GLOBAL', 'flutterwave', 'USD', flutterwaveGlobalPrice, '0.01'],
              ['Global PayPal Price (USD)', 'GLOBAL', 'paypal', 'USD', paypalGlobalPrice, '0.01'],
            ].map(([label, country, provider, currency, price, step]) => (
              <label className="form-group" key={`${country}-${provider}`}>
                <span className="form-label">{label}</span>
                <input
                  className="form-input"
                  type="number"
                  min="0"
                  step={step}
                  value={(price.amountMinor || 0) / 100}
                  onChange={(event) =>
                    updateMoney(country, provider, currency, event.target.value)
                  }
                />
              </label>
            ))}
            <label className="form-group">
              <span className="form-label">Google Play Product ID</span>
              <input
                className="form-input"
                value={googlePlayProductId}
                placeholder={`piki_${draft.code}_monthly`}
                onChange={(event) => updateGooglePlayProductId(event.target.value)}
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
            <p>Subscription billing is separate from each shop's M-Pesa sales settings.</p>
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
