import { useEffect, useMemo, useState } from 'react'
import { apiUrl, readApiJson } from '../utils/api'

const CONNECT_CONTEXT_KEY = 'piki_whatsapp_connect_context'
const CONNECT_STATE_KEY = 'piki_whatsapp_connect_state'

function readUrlParams() {
  const params = new URLSearchParams(window.location.search)
  const hash = window.location.hash.replace(/^#/, '')
  if (hash) {
    const hashParams = new URLSearchParams(hash)
    hashParams.forEach((value, key) => {
      if (!params.has(key)) {
        params.set(key, value)
      }
    })
  }
  return params
}

function firstValue(sources, keys) {
  for (const source of sources) {
    if (!source) continue
    for (const key of keys) {
      const value =
        source instanceof URLSearchParams ? source.get(key) : source[key]
      if (typeof value === 'string' && value.trim()) {
        return value.trim()
      }
    }
  }
  return ''
}

function parseJson(value) {
  if (!value || typeof value !== 'string') return null
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}

function parseEncodedState(value) {
  const clean = String(value || '').trim()
  if (!clean) return {}

  const directJson = parseJson(clean)
  if (directJson && typeof directJson === 'object') {
    return directJson
  }

  try {
    const padded = clean.replace(/-/g, '+').replace(/_/g, '/')
    const padding = padded.length % 4 ? '='.repeat(4 - (padded.length % 4)) : ''
    const decoded = atob(`${padded}${padding}`)
    const parsed = parseJson(decoded)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

function readStoredContext() {
  return (
    parseJson(sessionStorage.getItem(CONNECT_CONTEXT_KEY)) ||
    parseJson(localStorage.getItem(CONNECT_CONTEXT_KEY)) ||
    parseJson(sessionStorage.getItem(CONNECT_STATE_KEY)) ||
    parseJson(localStorage.getItem(CONNECT_STATE_KEY)) ||
    {}
  )
}

function cleanCallbackUrl() {
  if (window.location.search || window.location.hash) {
    window.history.replaceState({}, document.title, window.location.pathname)
  }
}

function buildCallbackPayload(params, state, storedContext) {
  const sources = [params, state, storedContext]
  return {
    code: firstValue(sources, ['code', 'authorizationCode']),
    deviceId: firstValue(sources, ['deviceId', 'device_id']),
    accessToken: firstValue(sources, [
      'businessAccessToken',
      'business_access_token',
      'pikiAccessToken',
    ]),
    redirectUri:
      firstValue(sources, ['redirectUri', 'redirect_uri']) ||
      `${window.location.origin}${window.location.pathname}`,
    phoneNumberId: firstValue(sources, [
      'phoneNumberId',
      'phone_number_id',
      'whatsappPhoneNumberId',
      'whatsapp_phone_number_id',
    ]),
    wabaId: firstValue(sources, [
      'wabaId',
      'waba_id',
      'whatsappBusinessAccountId',
      'whatsapp_business_account_id',
    ]),
    displayPhoneNumber: firstValue(sources, [
      'displayPhoneNumber',
      'display_phone_number',
      'whatsappNumber',
      'whatsapp_number',
    ]),
    businessName: firstValue(sources, [
      'businessName',
      'business_name',
      'verifiedName',
      'verified_name',
    ]),
  }
}

function clearStoredContext() {
  sessionStorage.removeItem(CONNECT_CONTEXT_KEY)
  sessionStorage.removeItem(CONNECT_STATE_KEY)
  localStorage.removeItem(CONNECT_CONTEXT_KEY)
  localStorage.removeItem(CONNECT_STATE_KEY)
}

export default function WhatsAppConnectCallback() {
  const [status, setStatus] = useState('connecting')
  const [message, setMessage] = useState('Completing WhatsApp connection...')
  const [details, setDetails] = useState(null)

  const params = useMemo(() => readUrlParams(), [])

  useEffect(() => {
    let cancelled = false

    async function completeConnection() {
      const metaError = firstValue([params], ['error_description', 'error'])
      const state = parseEncodedState(params.get('state'))
      const storedContext = readStoredContext()
      const payload = buildCallbackPayload(params, state, storedContext)
      cleanCallbackUrl()

      if (metaError) {
        setStatus('error')
        setMessage(metaError)
        return
      }

      if (!payload.code) {
        setStatus('error')
        setMessage('Meta did not return an authorization code.')
        return
      }

      if (!payload.accessToken || !payload.deviceId) {
        setStatus('needs-context')
        setMessage(
          'This browser callback is missing the Piki business session. Start WhatsApp connection from Piki POS settings so the callback can identify the correct store.',
        )
        setDetails({
          codeReceived: true,
          redirectUri: payload.redirectUri,
          phoneNumberId: payload.phoneNumberId || '',
          wabaId: payload.wabaId || '',
        })
        return
      }

      if (!payload.phoneNumberId) {
        setStatus('needs-context')
        setMessage(
          'Meta returned the signup code, but no WhatsApp Phone Number ID was included. The Embedded Signup launch must pass phone_number_id back in state or callback data.',
        )
        setDetails({
          codeReceived: true,
          redirectUri: payload.redirectUri,
          wabaId: payload.wabaId || '',
        })
        return
      }

      try {
        const response = await fetch(apiUrl('/api/business/whatsapp-connect/complete'), {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${payload.accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            code: payload.code,
            redirectUri: payload.redirectUri,
            deviceId: payload.deviceId,
            phoneNumberId: payload.phoneNumberId,
            ...(payload.wabaId ? { wabaId: payload.wabaId } : {}),
            ...(payload.displayPhoneNumber
              ? { displayPhoneNumber: payload.displayPhoneNumber }
              : {}),
            ...(payload.businessName ? { businessName: payload.businessName } : {}),
          }),
        })
        const body = await readApiJson(response)
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || 'WhatsApp connection failed.')
        }
        clearStoredContext()
        if (!cancelled) {
          setStatus('connected')
          setMessage('WhatsApp Business API connected successfully.')
          setDetails(body.data || null)
        }
      } catch (error) {
        if (!cancelled) {
          setStatus('error')
          setMessage(
            error instanceof Error
              ? error.message
              : 'WhatsApp connection failed.',
          )
          setDetails({
            redirectUri: payload.redirectUri,
            phoneNumberId: payload.phoneNumberId,
            wabaId: payload.wabaId,
          })
        }
      }
    }

    completeConnection()
    return () => {
      cancelled = true
    }
  }, [params])

  const connected = status === 'connected'
  const waitingForContext = status === 'needs-context'

  return (
    <main className="whatsapp-callback-page">
      <section className="whatsapp-callback-card glass-panel">
        <div
          className={`whatsapp-callback-icon ${
            connected ? 'is-success' : status === 'error' ? 'is-error' : ''
          }`}
        >
          {connected ? '✓' : status === 'connecting' ? '...' : '!'}
        </div>
        <p className="callback-eyebrow">Piki POS WhatsApp setup</p>
        <h1>
          {connected
            ? 'Connection complete'
            : waitingForContext
              ? 'Action needed'
              : status === 'connecting'
                ? 'Connecting WhatsApp'
                : 'Connection failed'}
        </h1>
        <p className="callback-message">{message}</p>

        {details && (
          <div className="callback-details">
            {details.whatsappDisplayPhoneNumber && (
              <div>
                <span>Sender</span>
                <strong>{details.whatsappDisplayPhoneNumber}</strong>
              </div>
            )}
            {details.whatsappPhoneNumberId && (
              <div>
                <span>Phone Number ID</span>
                <strong>{details.whatsappPhoneNumberId}</strong>
              </div>
            )}
            {details.whatsappWabaId && (
              <div>
                <span>WABA ID</span>
                <strong>{details.whatsappWabaId}</strong>
              </div>
            )}
            {details.redirectUri && (
              <div>
                <span>Redirect URI</span>
                <strong>{details.redirectUri}</strong>
              </div>
            )}
            {details.phoneNumberId && (
              <div>
                <span>Returned Phone Number ID</span>
                <strong>{details.phoneNumberId}</strong>
              </div>
            )}
            {details.wabaId && (
              <div>
                <span>Returned WABA ID</span>
                <strong>{details.wabaId}</strong>
              </div>
            )}
          </div>
        )}

        <div className="callback-actions">
          <a className="btn btn-primary" href="/">
            Open Piki Admin
          </a>
          <button
            className="btn btn-secondary"
            type="button"
            onClick={() => window.close()}
          >
            Close tab
          </button>
        </div>
      </section>
    </main>
  )
}
