import { useCallback, useEffect, useMemo, useState } from 'react'
import AiConfigPanel from './AiConfigPanel'
import SubscriptionPlansPanel from './SubscriptionPlansPanel'
import { friendlyError } from '../utils/errors'

const sellingModeLabels = {
  products: 'Products only',
  services: 'Services only',
  combo: 'Products + Services',
}
const sellingModeOptions = Object.keys(sellingModeLabels)

const modules = [
  { id: 'overview', label: 'Overview', icon: 'grid', caption: 'Platform health' },
  { id: 'businesses', label: 'Businesses', icon: 'store', caption: 'Accounts & branches' },
  { id: 'users', label: 'Contacts', icon: 'users', caption: 'Users & marketing' },
  { id: 'notifications', label: 'Notifications', icon: 'bell', caption: 'Customer updates' },
  { id: 'billing', label: 'Plans & billing', icon: 'card', caption: 'Pricing & gateways' },
  { id: 'ai', label: 'Piki AI', icon: 'sparkles', caption: 'Models & diagnostics' },
]

const moduleCopy = {
  overview: ['Platform overview', 'Monitor adoption, subscriptions, and issues across Piki POS.'],
  businesses: ['Businesses', 'Manage business access, selling modes, plans, branches, and owner contacts.'],
  users: ['Customer contacts', 'View user details and export opted-in contact data for compliant marketing workflows.'],
  notifications: ['Notifications', 'Send in-app announcements to every business or a precise audience.'],
  billing: ['Plans, billing & integrations', 'Manage subscriptions, prices, app releases, Flutterwave, messaging, and readiness.'],
  ai: ['Piki AI control center', 'Configure models, voice, web search, and run connection diagnostics.'],
}

function Icon({ name, size = 20 }) {
  const paths = {
    grid: <><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></>,
    store: <><path d="M3 10h18"/><path d="M5 10v10h14V10"/><path d="M4 4h16l1 6a3 3 0 0 1-5 2 3 3 0 0 1-4 0 3 3 0 0 1-4 0 3 3 0 0 1-5-2l1-6Z"/></>,
    users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></>,
    card: <><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h2"/></>,
    sparkles: <><path d="m12 3-1.2 3.2L8 8l2.8 1.8L12 13l1.2-3.2L16 8l-2.8-1.8L12 3Z"/><path d="m5 14-.8 2.2L2 17l2.2.8L5 20l.8-2.2L8 17l-2.2-.8L5 14Z"/><path d="m19 13-.7 1.8-1.8.7 1.8.7L19 18l.7-1.8 1.8-.7-1.8-.7L19 13Z"/></>,
    search: <><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></>,
    refresh: <><path d="M20 12a8 8 0 1 1-2.34-5.66L20 8"/><path d="M20 3v5h-5"/></>,
    download: <><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></>,
    logout: <><path d="M10 17l5-5-5-5"/><path d="M15 12H3"/><path d="M21 19V5a2 2 0 0 0-2-2h-6"/></>,
    menu: <><path d="M4 6h16M4 12h16M4 18h16"/></>,
    close: <><path d="m6 6 12 12M18 6 6 18"/></>,
    arrow: <><path d="M5 12h14M13 6l6 6-6 6"/></>,
  }
  return <svg className="ui-icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name] || paths.grid}</svg>
}

function formatDate(value, fallback = '—') {
  if (!value) return fallback
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? fallback : date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
}

function statusBadge(status) {
  const tone = ['active', 'paid', 'success'].includes(status) ? 'success'
    : ['grace', 'past_due', 'warning'].includes(status) ? 'warning'
      : ['expired', 'canceled', 'unpaid', 'critical'].includes(status) ? 'danger' : 'info'
  return <span className={`status-pill ${tone}`}>{String(status || 'unknown').replaceAll('_', ' ')}</span>
}

function EmptyState({ icon = 'search', title, message }) {
  return <div className="admin-empty"><span><Icon name={icon} size={26}/></span><h3>{title}</h3><p>{message}</p></div>
}

export default function Dashboard({ token, onLogout }) {
  const [stats, setStats] = useState({})
  const [businesses, setBusinesses] = useState([])
  const [users, setUsers] = useState([])
  const [plans, setPlans] = useState([])
  const [notifications, setNotifications] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeModule, setActiveModule] = useState('overview')
  const [message, setMessage] = useState('')
  const [search, setSearch] = useState('')
  const [assignmentState, setAssignmentState] = useState({})
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [deleteConfirmText, setDeleteConfirmText] = useState('')
  const [deletingAll, setDeletingAll] = useState(false)
  const [notificationSaving, setNotificationSaving] = useState(false)
  const [notificationDraft, setNotificationDraft] = useState({
    title: '', message: '', severity: 'info', audience: 'all',
    businessId: '', plan: '', countryCode: '', expiresAt: '',
  })

  const headers = useMemo(() => ({ Authorization: `Bearer ${token}` }), [token])

  const loadJson = useCallback(async (url, fallback) => {
    const response = await fetch(url, { headers })
    const body = await response.json().catch(() => ({}))
    if (!response.ok || body.ok !== true) throw new Error(body.error || `Could not load ${url}`)
    return body.data ?? fallback
  }, [headers])

  const fetchDashboardData = useCallback(async ({ quiet = false } = {}) => {
    if (!quiet) setLoading(true)
    setMessage('')
    const requests = [
      ['/api/platform/dashboard', {}],
      ['/api/platform/businesses', []],
      ['/api/platform/users', []],
      ['/api/platform/plans', []],
      ['/api/platform/notifications', []],
    ]
    const results = await Promise.allSettled(requests.map(([url, fallback]) => loadJson(url, fallback)))
    const setters = [setStats, setBusinesses, setUsers, setPlans, setNotifications]
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') setters[index](result.value || requests[index][1])
    })
    const failures = results.filter((item) => item.status === 'rejected')
    if (failures.length) setMessage(failures.map((item) => friendlyError(item.reason, 'Could not load data.')).join(' • '))
    setLoading(false)
  }, [loadJson])

  useEffect(() => { fetchDashboardData() }, [fetchDashboardData])

  const filteredBusinesses = useMemo(() => {
    const term = search.trim().toLowerCase()
    if (!term) return businesses
    return businesses.filter((item) => [item.name, item.owner_name, item.owner_email, item.owner_phone, item.country_code, item.plan].some((value) => String(value || '').toLowerCase().includes(term)))
  }, [businesses, search])

  const filteredUsers = useMemo(() => {
    const term = search.trim().toLowerCase()
    if (!term) return users
    return users.filter((item) => [item.name, item.email, item.phone, item.business_name, item.role].some((value) => String(value || '').toLowerCase().includes(term)))
  }, [users, search])

  const selectModule = (id) => {
    setActiveModule(id)
    setSearch('')
    setSidebarOpen(false)
  }

  const sellingModesForPlan = (plan) => plan?.availableSellingModes || plan?.sellingModes || []
  const compatibleMode = (plan, preferred) => sellingModesForPlan(plan).includes(preferred)
    ? preferred : sellingModeOptions.find((mode) => sellingModesForPlan(plan).includes(mode)) || ''

  const assignBusinessPlan = async (business, planCode, preferredMode) => {
    const plan = plans.find((item) => item.code === planCode)
    const mode = compatibleMode(plan, preferredMode)
    if (!mode) return
    setAssignmentState((current) => ({ ...current, [business.id]: { saving: true } }))
    try {
      const response = await fetch(`/api/platform/businesses/${business.id}/subscription`, {
        method: 'PUT', headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan: planCode, sellingMode: mode, status: 'active' }),
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok !== true) throw new Error(body.error || 'Could not update subscription')
      setBusinesses((current) => current.map((item) => item.id === business.id
        ? { ...item, plan: body.data?.plan || planCode, selling_mode: body.data?.selling_mode || mode, status: body.data?.status || 'active', expires_at: body.data?.expires_at || item.expires_at }
        : item))
      setAssignmentState((current) => ({ ...current, [business.id]: { saved: true } }))
    } catch (error) {
      setAssignmentState((current) => ({ ...current, [business.id]: { error: friendlyError(error, 'Update failed.') } }))
    }
  }

  const sendNotification = async (event) => {
    event.preventDefault()
    setNotificationSaving(true)
    setMessage('')
    try {
      const response = await fetch('/api/platform/notifications', {
        method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify(notificationDraft),
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok !== true) throw new Error(body.error || 'Could not send notification')
      setNotifications((current) => [body.data, ...current])
      setNotificationDraft({ title: '', message: '', severity: 'info', audience: 'all', businessId: '', plan: '', countryCode: '', expiresAt: '' })
      setMessage('Notification published successfully.')
    } catch (error) {
      setMessage(friendlyError(error, 'Could not send notification.'))
    } finally { setNotificationSaving(false) }
  }

  const removeNotification = async (id) => {
    try {
      const response = await fetch(`/api/platform/notifications/${id}`, { method: 'DELETE', headers })
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok !== true) throw new Error(body.error || 'Could not remove notification')
      setNotifications((current) => current.filter((item) => item.id !== id))
    } catch (error) { setMessage(friendlyError(error, 'Could not remove notification.')) }
  }

  const exportContacts = () => {
    const rows = [['Name', 'Phone', 'Email', 'Business', 'Role', 'Joined'], ...filteredUsers.map((u) => [u.name, u.phone, u.email, u.business_name, u.role, u.created_at])]
    const csv = rows.map((row) => row.map((cell) => {
      const text = String(cell || '').replaceAll('"', '""')
      const safe = /^[=+\-@]/.test(text) ? `\t${text}` : text
      return `"${safe}"`
    }).join(',')).join('\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
    const link = document.createElement('a'); link.href = url; link.download = `piki-contacts-${new Date().toISOString().slice(0, 10)}.csv`; link.click(); URL.revokeObjectURL(url)
  }

  const deleteAllData = async () => {
    setDeletingAll(true)
    try {
      const response = await fetch('/api/platform/all-data', { method: 'DELETE', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify({ confirm: 'DELETE EVERYTHING' }) })
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok !== true) throw new Error(body.error || 'Could not delete data')
      setBusinesses([]); setUsers([]); setStats({}); setShowDeleteModal(false); setDeleteConfirmText(''); setMessage(body.data?.message || 'All data deleted.')
    } catch (error) { setMessage(friendlyError(error, 'Could not delete data.')) }
    finally { setDeletingAll(false) }
  }

  const [title, subtitle] = moduleCopy[activeModule]

  return <div className="admin-shell">
    <aside className={`admin-sidebar ${sidebarOpen ? 'is-open' : ''}`}>
      <div className="admin-brand"><span className="admin-brand-mark">P</span><div><strong>Piki POS</strong><small>Super admin</small></div><button className="icon-button sidebar-close" onClick={() => setSidebarOpen(false)} aria-label="Close navigation"><Icon name="close"/></button></div>
      <nav className="admin-nav" aria-label="Admin modules">
        <span className="admin-nav-label">Workspace</span>
        {modules.map((item) => <button key={item.id} className={activeModule === item.id ? 'is-active' : ''} onClick={() => selectModule(item.id)}><span><Icon name={item.icon}/></span><div><strong>{item.label}</strong><small>{item.caption}</small></div></button>)}
      </nav>
      <div className="admin-sidebar-footer"><div className="operator-avatar">SA</div><div><strong>Platform operator</strong><small>Full access</small></div><button className="icon-button" onClick={onLogout} title="Sign out"><Icon name="logout"/></button></div>
    </aside>
    {sidebarOpen && <button className="sidebar-scrim" onClick={() => setSidebarOpen(false)} aria-label="Close navigation backdrop"/>}

    <div className="admin-workspace">
      <header className="admin-topbar">
        <button className="icon-button mobile-menu" onClick={() => setSidebarOpen(true)} aria-label="Open navigation"><Icon name="menu"/></button>
        <div className="admin-breadcrumb"><span>Admin</span><b>/</b><strong>{title}</strong></div>
        <div className="topbar-actions"><span className="live-indicator"><i/>Platform live</span><button className="icon-button" onClick={() => fetchDashboardData({ quiet: true })} title="Refresh data"><Icon name="refresh"/></button></div>
      </header>

      <main className="admin-main">
        <section className="module-heading"><div><span className="eyebrow">Piki control center</span><h1>{title}</h1><p>{subtitle}</p></div>{(activeModule === 'businesses' || activeModule === 'users') && <div className="admin-search"><Icon name="search" size={18}/><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder={`Search ${activeModule}...`} aria-label={`Search ${activeModule}`}/></div>}</section>
        {message && <div className="admin-banner" role="status">{message}<button onClick={() => setMessage('')} aria-label="Dismiss"><Icon name="close" size={16}/></button></div>}
        {loading ? <div className="admin-loading"><span/><p>Loading platform data…</p></div> : <>
          {activeModule === 'overview' && <Overview stats={stats} businesses={businesses} notifications={notifications} onOpen={selectModule}/>}
          {activeModule === 'businesses' && <Businesses businesses={filteredBusinesses} plans={plans} assignmentState={assignmentState} onAssign={assignBusinessPlan} onDeleteAll={() => setShowDeleteModal(true)}/>}
          {activeModule === 'users' && <Users users={filteredUsers} onExport={exportContacts}/>}
          {activeModule === 'notifications' && <Notifications draft={notificationDraft} setDraft={setNotificationDraft} onSubmit={sendNotification} saving={notificationSaving} businesses={businesses} plans={plans} notifications={notifications} onRemove={removeNotification}/>}
          {activeModule === 'billing' && <div className="module-surface legacy-module-surface"><SubscriptionPlansPanel token={token}/></div>}
          {activeModule === 'ai' && <div className="module-surface"><AiConfigPanel token={token}/></div>}
        </>}
      </main>
    </div>

    {showDeleteModal && <div className="admin-modal-backdrop" role="presentation"><div className="admin-modal" role="dialog" aria-modal="true"><span className="danger-icon">!</span><h2>Delete all platform data?</h2><p>This permanently removes every business, user, subscription, product, sale, and customer record. This cannot be undone.</p><label className="form-group"><span className="form-label">Type DELETE to confirm</span><input className="form-input" value={deleteConfirmText} onChange={(e) => setDeleteConfirmText(e.target.value)} autoFocus/></label><div className="modal-actions"><button className="btn btn-secondary" onClick={() => { setShowDeleteModal(false); setDeleteConfirmText('') }}>Cancel</button><button className="btn danger-button" disabled={deleteConfirmText !== 'DELETE' || deletingAll} onClick={deleteAllData}>{deletingAll ? 'Deleting…' : 'Delete everything'}</button></div></div></div>}
  </div>
}

function Overview({ stats, businesses, notifications, onOpen }) {
  const recent = businesses.slice(0, 5)
  const cards = [
    ['Businesses', stats.totalBusinesses || 0, `${stats.trialSubscriptions || 0} on trial`, 'store', 'violet'],
    ['Active subscriptions', stats.activeSubscriptions || 0, `${stats.expiringSubscriptions || 0} expire in 7 days`, 'card', 'green'],
    ['Platform users', stats.totalUsers || 0, `${stats.totalDevices || 0} connected devices`, 'users', 'blue'],
    ['Announcements', notifications.length, 'Published notification history', 'bell', 'amber'],
  ]
  return <div className="overview-stack">
    <div className="metric-grid">{cards.map(([label, value, note, icon, tone]) => <article className="metric-card" key={label}><span className={`metric-icon ${tone}`}><Icon name={icon}/></span><div><p>{label}</p><strong>{value}</strong><small>{note}</small></div></article>)}</div>
    <div className="overview-grid">
      <section className="module-surface"><div className="surface-header"><div><h2>Newest businesses</h2><p>Recently created platform accounts</p></div><button className="text-button" onClick={() => onOpen('businesses')}>View all <Icon name="arrow" size={16}/></button></div>{recent.length ? <div className="activity-list">{recent.map((b) => <div key={b.id}><span className="business-avatar">{String(b.name || 'B').slice(0, 2).toUpperCase()}</span><div><strong>{b.name}</strong><small>{b.owner_name || b.owner_email || 'Owner not provided'}</small></div>{statusBadge(b.status)}<time>{formatDate(b.created_at)}</time></div>)}</div> : <EmptyState title="No businesses yet" message="New accounts will appear here."/>}</section>
      <section className="module-surface quick-actions"><div className="surface-header"><div><h2>Quick actions</h2><p>Common platform workflows</p></div></div>{[
        ['Send an announcement', 'Reach all or selected businesses', 'notifications', 'bell'],
        ['Review subscriptions', 'Plans, pricing, payments and releases', 'billing', 'card'],
        ['Test Piki AI', 'Check models and web search', 'ai', 'sparkles'],
      ].map(([label, note, target, icon]) => <button key={target} onClick={() => onOpen(target)}><span><Icon name={icon}/></span><div><strong>{label}</strong><small>{note}</small></div><Icon name="arrow" size={17}/></button>)}</section>
    </div>
  </div>
}

function Businesses({ businesses, plans, assignmentState, onAssign, onDeleteAll }) {
  return <div className="module-surface"><div className="surface-header"><div><h2>Business accounts</h2><p>{businesses.length} result{businesses.length === 1 ? '' : 's'} with owner and branch visibility</p></div></div>{businesses.length ? <div className="responsive-table"><table className="admin-table"><thead><tr><th>Business</th><th>Owner contact</th><th>Operations</th><th>Subscription</th><th>Last active</th></tr></thead><tbody>{businesses.map((b) => { const state = assignmentState[b.id] || {}; const currentPlan = plans.find((p) => p.code === (b.plan || 'trial')); return <tr key={b.id}><td data-label="Business"><div className="identity-cell"><span className="business-avatar">{String(b.name || 'B').slice(0, 2).toUpperCase()}</span><div><strong>{b.name}</strong><small>{b.country_code || 'GLOBAL'} · Joined {formatDate(b.created_at)}</small></div></div></td><td data-label="Owner contact"><div className="contact-stack"><strong>{b.owner_name || 'Not provided'}</strong><a href={b.owner_phone ? `tel:${b.owner_phone}` : undefined}>{b.owner_phone || 'No phone number'}</a><a href={b.owner_email ? `mailto:${b.owner_email}` : undefined}>{b.owner_email || 'No email'}</a></div></td><td data-label="Operations"><div className="operation-counts"><span><b>{b.branch_count || 0}</b> branches</span><span><b>{b.device_count || 0}</b> devices</span></div><select className="form-input compact-input" value={b.selling_mode || 'combo'} disabled={state.saving} onChange={(e) => onAssign(b, b.plan || 'trial', e.target.value)}>{sellingModeOptions.map((mode) => <option key={mode} value={mode} disabled={!sellingModesFor(b, currentPlan).includes(mode)}>{sellingModeLabels[mode]}</option>)}</select></td><td data-label="Subscription"><div className="subscription-cell">{statusBadge(b.status)}<select className="form-input compact-input" value={b.plan || 'trial'} disabled={state.saving} onChange={(e) => onAssign(b, e.target.value, b.selling_mode || 'combo')}>{plans.map((p) => <option key={p.code} value={p.code} disabled={!sellingModesFor(b, p).length}>{p.name}</option>)}</select><small>{state.saving ? 'Saving…' : state.saved ? 'Saved' : state.error || `Expires ${formatDate(b.expires_at)}`}</small></div></td><td data-label="Last active">{formatDate(b.last_seen_at, 'Never')}</td></tr>})}</tbody></table></div> : <EmptyState title="No matching businesses" message="Try a different name, phone, email, country, or plan."/>}<div className="danger-zone"><div><strong>Danger zone</strong><p>Remove all tenant and transaction data from the platform.</p></div><button className="btn danger-button" onClick={onDeleteAll}>Delete all data</button></div></div>
}

function sellingModesFor(business, plan) {
  const modes = plan?.availableSellingModes || plan?.sellingModes || []
  return modes.includes(business.selling_mode || 'combo') ? modes : [business.selling_mode || 'combo', ...modes]
}

function Users({ users, onExport }) {
  return <div className="module-surface"><div className="surface-header"><div><h2>People directory</h2><p>{users.length} result{users.length === 1 ? '' : 's'} · Phone numbers are visible only to platform super admins</p></div><button className="btn btn-secondary" onClick={onExport}><Icon name="download" size={17}/> Export CSV</button></div>{users.length ? <div className="responsive-table"><table className="admin-table"><thead><tr><th>Person</th><th>Phone</th><th>Email</th><th>Business</th><th>Access</th><th>Last seen</th></tr></thead><tbody>{users.map((u) => <tr key={u.id}><td data-label="Person"><div className="identity-cell"><span className="user-avatar">{String(u.name || u.email || 'U').slice(0, 2).toUpperCase()}</span><div><strong>{u.name || 'Name not set'}</strong><small>Joined {formatDate(u.created_at)}</small></div></div></td><td data-label="Phone"><a className={u.phone ? 'phone-link' : 'muted-value'} href={u.phone ? `tel:${u.phone}` : undefined}>{u.phone || 'Not provided'}</a></td><td data-label="Email"><a href={`mailto:${u.email}`}>{u.email}</a></td><td data-label="Business">{u.business_name || 'Unassigned'}</td><td data-label="Access"><span className="role-pill">{u.role}</span></td><td data-label="Last seen">{formatDate(u.last_seen_at, 'Never')}</td></tr>)}</tbody></table></div> : <EmptyState title="No matching contacts" message="Try another name, phone number, email, business, or role."/>}<div className="privacy-note"><strong>Responsible marketing</strong><p>Exported contact data should only be used where the customer has consented and in line with local privacy and anti-spam rules.</p></div></div>
}

function Notifications({ draft, setDraft, onSubmit, saving, businesses, plans, notifications, onRemove }) {
  const update = (key, value) => setDraft((current) => ({ ...current, [key]: value }))
  const targetLabel = (item) => item.audience === 'all' ? 'All businesses' : item.audience === 'business' ? item.targetBusinessName || 'Selected business' : item.audience === 'plan' ? `${item.targetPlan} plan` : item.targetCountry
  return <div className="notification-layout"><form className="module-surface notification-composer" onSubmit={onSubmit}><div className="surface-header"><div><h2>New announcement</h2><p>Delivered to the POS notification center on the next refresh.</p></div></div><div className="editor-grid"><label className="form-group field-span-2"><span className="form-label">Title</span><input className="form-input" maxLength="120" required value={draft.title} onChange={(e) => update('title', e.target.value)} placeholder="What should customers know?"/></label><label className="form-group field-span-2"><span className="form-label">Message</span><textarea className="form-input admin-textarea" maxLength="1000" required value={draft.message} onChange={(e) => update('message', e.target.value)} placeholder="Keep it clear, useful, and actionable."/></label><label className="form-group"><span className="form-label">Audience</span><select className="form-input" value={draft.audience} onChange={(e) => update('audience', e.target.value)}><option value="all">All businesses</option><option value="business">One business</option><option value="plan">Subscription plan</option><option value="country">Country</option></select></label><label className="form-group"><span className="form-label">Priority</span><select className="form-input" value={draft.severity} onChange={(e) => update('severity', e.target.value)}><option value="info">Information</option><option value="success">Success / good news</option><option value="warning">Warning</option><option value="critical">Critical</option></select></label>{draft.audience === 'business' && <label className="form-group field-span-2"><span className="form-label">Business</span><select className="form-input" required value={draft.businessId} onChange={(e) => update('businessId', e.target.value)}><option value="">Choose business</option>{businesses.map((b) => <option key={b.id} value={b.id}>{b.name} — {b.owner_email}</option>)}</select></label>}{draft.audience === 'plan' && <label className="form-group field-span-2"><span className="form-label">Plan</span><select className="form-input" required value={draft.plan} onChange={(e) => update('plan', e.target.value)}><option value="">Choose plan</option>{plans.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></label>}{draft.audience === 'country' && <label className="form-group field-span-2"><span className="form-label">Country code</span><input className="form-input" required maxLength="8" value={draft.countryCode} onChange={(e) => update('countryCode', e.target.value.toUpperCase())} placeholder="KE, UG, TZ…"/></label>}<label className="form-group field-span-2"><span className="form-label">Expires (optional)</span><input type="datetime-local" className="form-input" value={draft.expiresAt} onChange={(e) => update('expiresAt', e.target.value)}/></label></div><button className="btn btn-primary publish-button" disabled={saving}>{saving ? 'Publishing…' : 'Publish notification'}</button></form><section className="module-surface"><div className="surface-header"><div><h2>Published history</h2><p>{notifications.length} announcement{notifications.length === 1 ? '' : 's'}</p></div></div>{notifications.length ? <div className="notification-history">{notifications.map((item) => <article key={item.id}><span className={`notice-dot ${item.severity}`}/><div><div className="notice-meta">{statusBadge(item.severity)}<span>{targetLabel(item)}</span><time>{formatDate(item.createdAt)}</time></div><h3>{item.title}</h3><p>{item.message}</p>{item.expiresAt && <small>Expires {formatDate(item.expiresAt)}</small>}</div><button className="icon-button" onClick={() => onRemove(item.id)} title="Remove notification"><Icon name="close" size={17}/></button></article>)}</div> : <EmptyState icon="bell" title="No announcements yet" message="Published notifications will appear here."/>}</section></div>
}
