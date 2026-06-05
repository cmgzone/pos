import { useState, useEffect, useCallback } from 'react'
import AiConfigPanel from './AiConfigPanel'
import SubscriptionPlansPanel from './SubscriptionPlansPanel'
import { friendlyError } from '../utils/errors'

const sellingModeLabels = {
  products: 'Products only',
  services: 'Services only',
  combo: 'Products + Services',
}

const sellingModeOptions = ['products', 'services', 'combo']

export default function Dashboard({ token, onLogout }) {
  const [stats, setStats] = useState({ totalBusinesses: 0, activeSubscriptions: 0, totalUsers: 0 })
  const [businesses, setBusinesses] = useState([])
  const [users, setUsers] = useState([])
  const [plans, setPlans] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('businesses')
  const [loadMessage, setLoadMessage] = useState('')
  const [assignmentState, setAssignmentState] = useState({})

  const fetchDashboardData = useCallback(async () => {
    setLoading(true)
    setLoadMessage('')
    try {
      const headers = { 'Authorization': `Bearer ${token}` }

      const loadJson = async (url, fallback) => {
        const response = await fetch(url, { headers })
        const body = await response.json().catch(() => ({}))
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || `Could not load ${url}`)
        }
        return body.data ?? fallback
      }

      const [statsResult, bizResult, usersResult, plansResult] = await Promise.allSettled([
        loadJson('/api/platform/dashboard', { totalBusinesses: 0, activeSubscriptions: 0, totalUsers: 0 }),
        loadJson('/api/platform/businesses', []),
        loadJson('/api/platform/users', []),
        loadJson('/api/platform/plans', []),
      ])

      if (statsResult.status === 'fulfilled') setStats(statsResult.value)
      if (bizResult.status === 'fulfilled') setBusinesses(bizResult.value || [])
      if (usersResult.status === 'fulfilled') setUsers(usersResult.value || [])
      if (plansResult.status === 'fulfilled') setPlans(plansResult.value || [])

      const failures = [statsResult, bizResult, usersResult, plansResult]
        .filter((item) => item.status === 'rejected')
        .map((item) => friendlyError(item.reason, 'Could not load dashboard data.'))
        .filter(Boolean)
      if (failures.length > 0) {
        setLoadMessage(failures.join(' | '))
      }
    } catch (err) {
      console.error('Failed to fetch dashboard data:', err)
      setLoadMessage(friendlyError(err, 'Could not load dashboard data.'))
    } finally {
      setLoading(false)
    }
  }, [token])

  useEffect(() => {
    fetchDashboardData()
  }, [fetchDashboardData])

  const getStatusBadge = (status) => {
    switch(status) {
      case 'active': return <span className="badge badge-success">Active</span>
      case 'grace': return <span className="badge badge-warning">Grace Period</span>
      case 'expired': return <span className="badge badge-danger">Expired</span>
      case 'trialing': return <span className="badge badge-info">Trial</span>
      case 'past_due': return <span className="badge badge-warning">Past Due</span>
      case 'canceled': return <span className="badge badge-danger">Canceled</span>
      case 'unpaid': return <span className="badge badge-danger">Unpaid</span>
      default: return <span className="badge" style={{ background: 'var(--bg-tertiary)' }}>{status || 'Unknown'}</span>
    }
  }

  const sellingModesForPlan = (plan) => {
    return plan?.availableSellingModes || plan?.sellingModes || []
  }

  const planAllowsSellingMode = (plan, mode) => {
    const modes = sellingModesForPlan(plan)
    return modes.includes(mode)
  }

  const compatibleSellingModeForPlan = (plan, preferredMode) => {
    const modes = plan?.availableSellingModes || plan?.sellingModes || []
    if (preferredMode && modes.includes(preferredMode)) {
      return preferredMode
    }
    return sellingModeOptions.find((mode) => modes.includes(mode)) || ''
  }

  const assignBusinessPlan = async (
    business,
    planCode,
    sellingMode = business.selling_mode || 'combo',
  ) => {
    if (!planCode) return
    const targetPlan = plans.find((plan) => plan.code === planCode)
    const targetSellingMode = compatibleSellingModeForPlan(targetPlan, sellingMode)
    if (!targetSellingMode) {
      setAssignmentState((current) => ({
        ...current,
        [business.id]: {
          saving: false,
          message: '',
          error: 'This plan is not available for product or service selling yet.',
        },
      }))
      return
    }
    if (planCode === business.plan && targetSellingMode === (business.selling_mode || 'combo')) {
      return
    }
    setAssignmentState((current) => ({
      ...current,
      [business.id]: { saving: true, message: '', error: '' },
    }))
    try {
      const response = await fetch(`/api/platform/businesses/${business.id}/subscription`, {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          plan: planCode,
          sellingMode: targetSellingMode,
          status: 'active'
        })
      })
      const body = await response.json()
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || 'Could not update subscription')
      }
      const updated = body.data || {}
      setBusinesses((current) =>
        current.map((item) =>
          item.id === business.id
            ? {
                ...item,
                plan: updated.plan || planCode,
                status: updated.status || 'active',
                selling_mode: updated.selling_mode || targetSellingMode,
                expires_at: updated.expires_at || item.expires_at,
                grace_until: updated.grace_until || item.grace_until,
              }
            : item,
        ),
      )
      const savedMode = updated.selling_mode || targetSellingMode
      const modeChanged = savedMode !== (business.selling_mode || 'combo')
      setAssignmentState((current) => ({
        ...current,
        [business.id]: {
          saving: false,
          message: modeChanged
            ? `Saved - mode changed to ${sellingModeLabels[savedMode]}`
            : 'Saved',
          error: '',
        },
      }))
    } catch (error) {
      setAssignmentState((current) => ({
        ...current,
        [business.id]: {
          saving: false,
          message: '',
          error: friendlyError(error, 'Could not update subscription.'),
        },
      }))
    }
  }

  return (
    <div className="animate-fade-in">
      <header className="app-header">
        <div className="brand">
          <div className="brand-icon">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
            </svg>
          </div>
          <h1 className="brand-name" style={{ fontSize: '1.25rem' }}>Piki POS Platform</h1>
        </div>
        <div>
          <button onClick={onLogout} className="btn btn-secondary">
            Sign Out
          </button>
        </div>
      </header>

      <main className="container">
        
        <div className="grid-3" style={{ marginTop: '1rem' }}>
          <div className="glass-panel kpi-card">
            <span className="kpi-title">Total Businesses</span>
            <span className="kpi-value">{loading ? '-' : stats.totalBusinesses}</span>
          </div>
          <div className="glass-panel kpi-card">
            <span className="kpi-title">Active Subscriptions</span>
            <span className="kpi-value">{loading ? '-' : stats.activeSubscriptions}</span>
          </div>
          <div className="glass-panel kpi-card">
            <span className="kpi-title">Total Users</span>
            <span className="kpi-value">{loading ? '-' : stats.totalUsers}</span>
          </div>
        </div>

        <div className="glass-panel" style={{ padding: '0', overflow: 'hidden' }}>
          <div style={{ display: 'flex', borderBottom: '1px solid var(--border-subtle)', background: 'rgba(0,0,0,0.2)' }}>
            <button
              className={`btn ${activeTab === 'businesses' ? '' : 'btn-secondary'}`}
              style={{ borderRadius: 0, padding: '1rem 2rem', border: 'none', background: activeTab === 'businesses' ? 'var(--border-subtle)' : 'transparent', color: activeTab === 'businesses' ? 'white' : 'var(--text-secondary)' }}
              onClick={() => setActiveTab('businesses')}
            >
              Businesses
            </button>
            <button
              className={`btn ${activeTab === 'users' ? '' : 'btn-secondary'}`}
              style={{ borderRadius: 0, padding: '1rem 2rem', border: 'none', borderLeft: '1px solid var(--border-subtle)', background: activeTab === 'users' ? 'var(--border-subtle)' : 'transparent', color: activeTab === 'users' ? 'white' : 'var(--text-secondary)' }}
              onClick={() => setActiveTab('users')}
            >
              Users
            </button>
            <button
              className={`btn ${activeTab === 'ai' ? '' : 'btn-secondary'}`}
              style={{ borderRadius: 0, padding: '1rem 2rem', border: 'none', borderLeft: '1px solid var(--border-subtle)', background: activeTab === 'ai' ? 'var(--border-subtle)' : 'transparent', color: activeTab === 'ai' ? 'white' : 'var(--text-secondary)' }}
              onClick={() => setActiveTab('ai')}
            >
              AI Config
            </button>
            <button
              className={`btn ${activeTab === 'plans' ? '' : 'btn-secondary'}`}
              style={{ borderRadius: 0, padding: '1rem 2rem', border: 'none', borderLeft: '1px solid var(--border-subtle)', background: activeTab === 'plans' ? 'var(--border-subtle)' : 'transparent', color: activeTab === 'plans' ? 'white' : 'var(--text-secondary)' }}
              onClick={() => setActiveTab('plans')}
            >
              Plans
            </button>
          </div>

          <div style={{ padding: '1.5rem', minHeight: '400px' }}>
            {loadMessage && (
              <div className="admin-message" style={{ marginTop: 0 }}>
                {loadMessage}
              </div>
            )}
            {loading ? (
              <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '200px', color: 'var(--text-muted)' }}>
                Loading data...
              </div>
            ) : (
              <div className="table-container animate-fade-in">
                {activeTab === 'businesses' && (
                  <table className="modern-table">
                    <thead>
                      <tr>
                        <th>Joined</th>
                        <th>Business Name</th>
                        <th>Owner Info</th>
                        <th>Country</th>
                        <th>Sells</th>
                        <th>Plan</th>
                        <th>Status</th>
                        <th>Expires</th>
                        <th>Assign Plan</th>
                      </tr>
                    </thead>
                    <tbody>
                      {businesses.length === 0 ? (
                        <tr><td colSpan="9" style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No businesses found</td></tr>
                      ) : (
                        businesses.map(b => {
                          const rowState = assignmentState[b.id] || {}
                          return (
                          <tr key={b.id}>
                            <td style={{ color: 'var(--text-muted)' }}>{new Date(b.created_at).toLocaleDateString()}</td>
                            <td style={{ fontWeight: 500, color: 'white' }}>{b.name}</td>
                            <td>
                              <div>{b.owner_name}</div>
                              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{b.owner_email}</div>
                            </td>
                            <td>{b.country_code || 'GLOBAL'}</td>
                            <td>
                              <select
                                className="form-input compact-input"
                                value={b.selling_mode || 'combo'}
                                disabled={rowState.saving}
                                onChange={(event) =>
                                  assignBusinessPlan(
                                    b,
                                    b.plan || 'trial',
                                    event.target.value,
                                  )
                                }
                              >
                                {sellingModeOptions.map((mode) => {
                                  const activePlan = plans.find((plan) => plan.code === (b.plan || 'trial'))
                                  const isCurrent = mode === (b.selling_mode || 'combo')
                                  const disabled =
                                    !isCurrent && !planAllowsSellingMode(activePlan, mode)
                                  return (
                                    <option key={mode} value={mode} disabled={disabled}>
                                      {sellingModeLabels[mode]}
                                    </option>
                                  )
                                })}
                              </select>
                            </td>
                            <td><span style={{ textTransform: 'capitalize' }}>{b.plan || 'N/A'}</span></td>
                            <td>{getStatusBadge(b.status)}</td>
                            <td style={{ color: 'var(--text-muted)' }}>{b.expires_at ? new Date(b.expires_at).toLocaleDateString() : 'N/A'}</td>
                            <td>
                              <select
                                className="form-input compact-input"
                                value={b.plan || 'trial'}
                                disabled={rowState.saving}
                                onChange={(event) =>
                                  assignBusinessPlan(
                                    b,
                                    event.target.value,
                                    b.selling_mode || 'combo',
                                  )
                                }
                              >
                                {plans.map(plan => {
                                  const isCurrent = plan.code === (b.plan || 'trial')
                                  const compatibleMode = compatibleSellingModeForPlan(plan, b.selling_mode || 'combo')
                                  const disabled = !compatibleMode
                                  return (
                                    <option key={plan.code} value={plan.code} disabled={disabled}>
                                      {plan.name}
                                      {!isCurrent && compatibleMode && !planAllowsSellingMode(plan, b.selling_mode || 'combo')
                                        ? ` (${sellingModeLabels[compatibleMode]} mode)`
                                        : ''}
                                    </option>
                                  )
                                })}
                              </select>
                              {rowState.saving && <div className="row-note">Saving...</div>}
                              {rowState.message && <div className="row-note success">{rowState.message}</div>}
                              {rowState.error && <div className="row-note error">{rowState.error}</div>}
                            </td>
                          </tr>
                          )
                        })
                      )}
                    </tbody>
                  </table>
                )}

                {activeTab === 'users' && (
                  <table className="modern-table">
                    <thead>
                      <tr>
                        <th>Joined</th>
                        <th>Name</th>
                        <th>Email</th>
                        <th>Business</th>
                        <th>Role</th>
                        <th>Last Seen</th>
                      </tr>
                    </thead>
                    <tbody>
                      {users.length === 0 ? (
                        <tr><td colSpan="6" style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No users found</td></tr>
                      ) : (
                        users.map(u => (
                          <tr key={u.id}>
                            <td style={{ color: 'var(--text-muted)' }}>{new Date(u.created_at).toLocaleDateString()}</td>
                            <td style={{ fontWeight: 500, color: 'white' }}>{u.name || 'No Name'}</td>
                            <td>{u.email}</td>
                            <td>{u.business_name || 'Unassigned'}</td>
                            <td><span className="badge" style={{ background: 'var(--bg-tertiary)' }}>{u.role}</span></td>
                            <td style={{ color: 'var(--text-muted)' }}>{u.last_seen_at ? new Date(u.last_seen_at).toLocaleDateString() : 'Never'}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                )}

                {activeTab === 'ai' && (
                  <AiConfigPanel token={token} />
                )}

                {activeTab === 'plans' && (
                  <SubscriptionPlansPanel token={token} />
                )}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  )
}
