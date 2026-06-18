import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { apiUrl, readApiJson } from '../utils/api'

const FACEBOOK_ORIGINS = new Set([
  'https://www.facebook.com',
  'https://web.facebook.com',
])

function readSessionToken() {
  const params = new URLSearchParams(window.location.search)
  return (
    params.get('session') ||
    params.get('connectSession') ||
    params.get('sessionToken') ||
    ''
  ).trim()
}

function firstText(source, keys) {
  for (const key of keys) {
    const value = source?.[key]
    if (typeof value === 'string' && value.trim()) {
      return value.trim()
    }
  }
  return ''
}

function normalizeSignupData(data) {
  return {
    phoneNumberId: firstText(data, [
      'phone_number_id',
      'phoneNumberId',
      'whatsapp_phone_number_id',
    ]),
    wabaId: firstText(data, ['waba_id', 'wabaId', 'whatsapp_business_account_id']),
    displayPhoneNumber: firstText(data, [
      'display_phone_number',
      'displayPhoneNumber',
      'phone_number',
    ]),
    businessName: firstText(data, ['business_name', 'businessName', 'verified_name']),
  }
}

function loadFacebookSdk({ appId, apiVersion }) {
  return new Promise((resolve, reject) => {
    const version = apiVersion || 'v20.0'
    const init = () => {
      if (!window.FB) {
        reject(new Error('Meta login SDK failed to load.'))
        return
      }
      window.FB.init({
        appId,
        cookie: true,
        xfbml: false,
        version,
      })
      resolve(window.FB)
    }

    if (window.FB) {
      init()
      return
    }

    window.fbAsyncInit = init

    const existingScript = document.getElementById('facebook-jssdk')
    if (existingScript) {
      existingScript.addEventListener('load', init, { once: true })
      existingScript.addEventListener(
        'error',
        () => reject(new Error('Meta login SDK failed to load.')),
        { once: true },
      )
      return
    }

    const script = document.createElement('script')
    script.id = 'facebook-jssdk'
    script.async = true
    script.defer = true
    script.crossOrigin = 'anonymous'
    script.src = 'https://connect.facebook.net/en_US/sdk.js'
    script.onerror = () => reject(new Error('Meta login SDK failed to load.'))
    document.body.appendChild(script)
  })
}

export default function WhatsAppConnectLauncher() {
  const sessionToken = useMemo(() => readSessionToken(), [])
  const submittedRef = useRef(false)

  const [phase, setPhase] = useState('loading')
  const [message, setMessage] = useState('Loading WhatsApp setup...')
  const [platform, setPlatform] = useState(null)
  const [details, setDetails] = useState(null)
  const [authCode, setAuthCode] = useState('')
  const [signupData, setSignupData] = useState(null)

  useEffect(() => {
    let cancelled = false

    async function loadSession() {
      if (!sessionToken) {
        setPhase('error')
        setMessage('This WhatsApp setup link is missing a connection session.')
        return
      }

      try {
        const response = await fetch(
          apiUrl(
            `/api/business/whatsapp-connect/session/${encodeURIComponent(
              sessionToken,
            )}`,
          ),
        )
        const body = await readApiJson(response)
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || 'WhatsApp setup link is no longer valid.')
        }

        if (cancelled) return
        const nextPlatform = body.data?.platform || {}
        if (!nextPlatform.isActive || !nextPlatform.setupReady) {
          setPhase('error')
          setMessage('WhatsApp Embedded Signup is not configured in Piki Admin.')
          return
        }
        setPlatform(nextPlatform)
        setDetails(body.data || null)
        setPhase('ready')
        setMessage('Continue with Meta to verify and connect your WhatsApp number.')
      } catch (error) {
        if (!cancelled) {
          setPhase('error')
          setMessage(
            error instanceof Error
              ? error.message
              : 'WhatsApp setup could not be loaded.',
          )
        }
      }
    }

    loadSession()
    return () => {
      cancelled = true
    }
  }, [sessionToken])

  useEffect(() => {
    function handleMessage(event) {
      if (!FACEBOOK_ORIGINS.has(event.origin)) return

      let data = null
      try {
        data = JSON.parse(event.data)
      } catch {
        return
      }

      if (data?.type !== 'WA_EMBEDDED_SIGNUP') return

      if (data.event === 'FINISH') {
        const nextSignupData = normalizeSignupData(data.data || {})
        if (!nextSignupData.phoneNumberId) {
          setPhase('error')
          setMessage('Meta finished signup but did not return a phone number ID.')
          return
        }
        setSignupData(nextSignupData)
        setDetails((current) => ({ ...(current || {}), ...nextSignupData }))
        setPhase((current) =>
          current === 'connected' || current === 'completing'
            ? current
            : 'waiting',
        )
        setMessage('Meta signup finished. Waiting for authorization...')
        return
      }

      if (data.event === 'CANCEL') {
        setPhase('error')
        setMessage('WhatsApp setup was cancelled before completion.')
        return
      }

      if (data.event === 'ERROR') {
        setPhase('error')
        setMessage(data.data?.error_message || 'Meta could not complete WhatsApp setup.')
      }
    }

    window.addEventListener('message', handleMessage)
    return () => window.removeEventListener('message', handleMessage)
  }, [])

  useEffect(() => {
    if (
      submittedRef.current ||
      !sessionToken ||
      !platform ||
      !authCode ||
      !signupData?.phoneNumberId
    ) {
      return
    }

    submittedRef.current = true

    async function completeConnection() {
      setPhase('completing')
      setMessage('Saving WhatsApp connection...')
      try {
        const response = await fetch(apiUrl('/api/business/whatsapp-connect/complete'), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            connectSession: sessionToken,
            code: authCode,
            redirectUri: platform.oauthRedirectUri,
            phoneNumberId: signupData.phoneNumberId,
            ...(signupData.wabaId ? { wabaId: signupData.wabaId } : {}),
            ...(signupData.displayPhoneNumber
              ? { displayPhoneNumber: signupData.displayPhoneNumber }
              : {}),
            ...(signupData.businessName
              ? { businessName: signupData.businessName }
              : {}),
          }),
        })
        const body = await readApiJson(response)
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || 'WhatsApp connection failed.')
        }

        setPhase('connected')
        setMessage('WhatsApp Business API connected successfully.')
        setDetails(body.data || signupData)
      } catch (error) {
        submittedRef.current = false
        setPhase('error')
        setMessage(
          error instanceof Error ? error.message : 'WhatsApp connection failed.',
        )
      }
    }

    completeConnection()
  }, [authCode, platform, sessionToken, signupData])

  const launchSignup = useCallback(async () => {
    if (!platform) return
    setPhase('connecting')
    setMessage('Continue in the Meta signup window...')

    try {
      const FB = await loadFacebookSdk({
        appId: platform.appId,
        apiVersion: platform.apiVersion,
      })
      FB.login(
        (response) => {
          const nextCode = response?.authResponse?.code || ''
          if (!nextCode) {
            setPhase('error')
            setMessage('Meta login was cancelled before authorization completed.')
            return
          }
          setAuthCode(nextCode)
          setPhase((current) =>
            current === 'connected' || current === 'completing'
              ? current
              : 'waiting',
          )
          setMessage('Meta authorized Piki. Waiting for WhatsApp number details...')
        },
        {
          config_id: platform.embeddedSignupConfigId,
          response_type: 'code',
          override_default_response_type: true,
          extras: {
            sessionInfoVersion: 2,
            feature: 'whatsapp_embedded_signup',
          },
        },
      )
    } catch (error) {
      setPhase('error')
      setMessage(
        error instanceof Error ? error.message : 'Meta login could not be opened.',
      )
    }
  }, [platform])

  const connected = phase === 'connected'
  const busy = ['loading', 'connecting', 'waiting', 'completing'].includes(phase)
  const canLaunch = phase === 'ready' || phase === 'error'

  return (
    <main className="whatsapp-callback-page">
      <section className="whatsapp-callback-card glass-panel">
        <div
          className={`whatsapp-callback-icon ${
            connected ? 'is-success' : phase === 'error' ? 'is-error' : ''
          }`}
        >
          {connected ? 'OK' : busy ? '...' : '>'}
        </div>
        <p className="callback-eyebrow">Piki POS WhatsApp setup</p>
        <h1>
          {connected
            ? 'Connection complete'
            : busy
              ? 'Connecting WhatsApp'
              : phase === 'ready'
                ? 'Connect WhatsApp'
                : 'Connection failed'}
        </h1>
        <p className="callback-message">{message}</p>

        {details && (
          <div className="callback-details">
            {details.whatsappDisplayPhoneNumber && (
              <div>
                <span>Current sender</span>
                <strong>{details.whatsappDisplayPhoneNumber}</strong>
              </div>
            )}
            {details.displayPhoneNumber && (
              <div>
                <span>Selected sender</span>
                <strong>{details.displayPhoneNumber}</strong>
              </div>
            )}
            {(details.whatsappPhoneNumberId || details.phoneNumberId) && (
              <div>
                <span>Phone Number ID</span>
                <strong>{details.whatsappPhoneNumberId || details.phoneNumberId}</strong>
              </div>
            )}
            {(details.whatsappWabaId || details.wabaId) && (
              <div>
                <span>WABA ID</span>
                <strong>{details.whatsappWabaId || details.wabaId}</strong>
              </div>
            )}
            {details.sessionExpiresAt && !connected && (
              <div>
                <span>Setup link expires</span>
                <strong>{details.sessionExpiresAt}</strong>
              </div>
            )}
          </div>
        )}

        <div className="callback-actions">
          {canLaunch && platform && (
            <button className="btn btn-primary" type="button" onClick={launchSignup}>
              Continue with Meta
            </button>
          )}
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
