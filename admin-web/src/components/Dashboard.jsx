import { useState, useEffect } from 'react'
import AiConfigPanel from './AiConfigPanel'

export default function Dashboard({ token, onLogout }) {
  const [stats, setStats] = useState({ totalBusinesses: 0, activeSubscriptions: 0, totalUsers: 0 })
  const [businesses, setBusinesses] = useState([])
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('businesses')

  useEffect(() => {
    fetchDashboardData()
  }, [])

  const fetchDashboardData = async () => {
    setLoading(true)
    try {
      const headers = { 'Authorization': `Bearer ${token}` }
      
      const [statsRes, bizRes, usersRes] = await Promise.all([
        fetch('/api/platform/dashboard', { headers }),
        fetch('/api/platform/businesses', { headers }),
        fetch('/api/platform/users', { headers })
      ])

      if (statsRes.ok && bizRes.ok && usersRes.ok) {
        const statsData = await statsRes.json()
        const bizData = await bizRes.json()
        const usersData = await usersRes.json()
        
        setStats(statsData.data)
        setBusinesses(bizData.data || [])
        setUsers(usersData.data || [])
      }
    } catch (err) {
      console.error('Failed to fetch dashboard data:', err)
    } finally {
      setLoading(false)
    }
  }

  const getStatusBadge = (status) => {
    switch(status) {
      case 'active': return <span className="badge badge-success">Active</span>
      case 'trialing': return <span className="badge badge-info">Trial</span>
      case 'past_due': return <span className="badge badge-warning">Past Due</span>
      case 'canceled': return <span className="badge badge-danger">Canceled</span>
      case 'unpaid': return <span className="badge badge-danger">Unpaid</span>
      default: return <span className="badge" style={{ background: 'var(--bg-tertiary)' }}>{status || 'Unknown'}</span>
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
          <h1 className="brand-name" style={{ fontSize: '1.25rem' }}>Velora POS Platform</h1>
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
              🤖 AI Config
            </button>
          </div>

          <div style={{ padding: '1.5rem', minHeight: '400px' }}>
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
                        <th>Plan</th>
                        <th>Status</th>
                        <th>Expires</th>
                      </tr>
                    </thead>
                    <tbody>
                      {businesses.length === 0 ? (
                        <tr><td colSpan="6" style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No businesses found</td></tr>
                      ) : (
                        businesses.map(b => (
                          <tr key={b.id}>
                            <td style={{ color: 'var(--text-muted)' }}>{new Date(b.created_at).toLocaleDateString()}</td>
                            <td style={{ fontWeight: 500, color: 'white' }}>{b.name}</td>
                            <td>
                              <div>{b.owner_name}</div>
                              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{b.owner_email}</div>
                            </td>
                            <td><span style={{ textTransform: 'capitalize' }}>{b.plan || 'N/A'}</span></td>
                            <td>{getStatusBadge(b.status)}</td>
                            <td style={{ color: 'var(--text-muted)' }}>{b.expires_at ? new Date(b.expires_at).toLocaleDateString() : 'N/A'}</td>
                          </tr>
                        ))
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
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  )
}
