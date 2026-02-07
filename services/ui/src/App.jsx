import React, { useState, useEffect } from 'react'
import { Login } from './Login'
import {
    Shield, Users, Activity, LogOut, Settings, Globe, BarChart3,
    Wifi, AlertTriangle, CheckCircle, Clock, RefreshCw, Plus,
    Eye, Trash2, Download, Lock, Key, FileText, Server, Zap, Network,
    Play, Pause, Edit2, TrendingUp, HardDrive
} from 'lucide-react'

// Get CSRF token from cookie for secure POST requests
function getCSRFToken() {
    const match = document.cookie.match(/csrf_token=([^;]+)/)
    return match ? match[1] : ''
}

// Helper for authenticated POST/PUT/DELETE requests
function securePost(url, body) {
    return fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': getCSRFToken()
        },
        body: JSON.stringify(body)
    })
}

// Format bytes to human readable (KB, MB, GB)
function formatBytes(bytes) {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + sizes[i]
}

function App() {
    const [user, setUser] = useState(null)
    const [loginError, setLoginError] = useState('')
    const [peers, setPeers] = useState([])
    const [activeSubnet, setActiveSubnet] = useState('detecting...')
    const [subnetStats, setSubnetStats] = useState({ used: 0, total_capacity: 0 })
    const [loading, setLoading] = useState(true)
    const [activeTab, setActiveTab] = useState('dashboard')
    const [health, setHealth] = useState({ live: false, ready: false })
    const [systemStats, setSystemStats] = useState({})

    const [isCreateOpen, setIsCreateOpen] = useState(false)
    const [newPeerName, setNewPeerName] = useState('')
    const [creating, setCreating] = useState(false)
    const [isTemporary, setIsTemporary] = useState(false)
    const [expiryDays, setExpiryDays] = useState(7)

    const fetchPeers = () => {
        fetch('/api/v1/peers')
            .then(res => {
                if (res.status === 401) {
                    setUser(null)
                    throw new Error("Unauthorized")
                }
                if (!res.ok) throw new Error("Failed to fetch")
                return res.json()
            })
            .then(data => {
                setPeers(data.peers || [])
                if (!user) {
                    // Restore session if token is valid
                    setUser({ username: 'Operator', role: 'admin' })
                }
                setLoading(false)
            })
            .catch(err => {
                console.error("API Error:", err)
                setLoading(false)
            })
    }

    const fetchHealth = () => {
        Promise.all([
            fetch('/health/live').then(r => r.ok),
            fetch('/health/ready').then(r => r.ok)
        ]).then(([live, ready]) => {
            setHealth(prev => {
                if (prev.live === live && prev.ready === ready) return prev
                return { live, ready }
            })
        })
            .catch(() => setHealth(prev => {
                if (!prev.live && !prev.ready) return prev
                return { live: false, ready: false }
            }))
    }

    useEffect(() => {
        // Slow polling for heavy data (Peers, Network, Health Status)
        const loadHeavyData = () => {
            fetchPeers()
            fetchHealth()
            fetch('/api/v1/network/stats')
                .then(r => r.ok ? r.json() : {})
                .then(data => {
                    // Update subnet from authoritative stats response
                    if (data.subnet) {
                        setActiveSubnet(data.subnet)
                    } else if (data.current_cidr) {
                        setActiveSubnet(data.current_cidr)
                    }

                    if (data.used !== undefined) {
                        setSubnetStats({
                            used: data.used,
                            total_capacity: data.total_capacity || data.max_peers || 0
                        })
                    }
                })
                .catch(() => { })
        }

        // Fast polling for System Stats (CPU, RAM, Temp) - Realtime feel (1s)
        const loadFastData = () => {
            fetch('/api/v1/system/stats')
                .then(r => r.ok ? r.json() : {})
                .then(data => setSystemStats(data))
                .catch(() => { })
        }

        // Initial load
        loadHeavyData()
        loadFastData()

        const heavyInterval = setInterval(loadHeavyData, 5000)
        const fastInterval = setInterval(loadFastData, 1000)

        return () => {
            clearInterval(heavyInterval)
            clearInterval(fastInterval)
        }
    }, [user])

    const handleLogin = (username, password) => {
        fetch('/api/v1/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        })
            .then(async res => {
                if (!res.ok) {
                    const text = await res.text().catch(() => "Unknown error");
                    throw new Error(`Server ${res.status}: ${text.substring(0, 50)}`);
                }
                return res.json();
            })
            .then(data => {
                if (data.status === 'success') {
                    setUser({ username, role: data.role })
                    setLoginError('')
                } else {
                    setLoginError("Authentication failed")
                }
            })
            .catch(err => setLoginError("Error: " + err.message))
    }

    const handleLogout = () => {
        securePost('/api/v1/logout', {})
            .finally(() => setUser(null))
    }

    const handleCreatePeer = (e) => {
        e.preventDefault()
        if (!newPeerName.trim()) return
        if (!/^[a-zA-Z0-9_-]+$/.test(newPeerName)) {
            alert("Name must be alphanumeric only.")
            return
        }
        setCreating(true)
        const peerData = { name: newPeerName }
        if (isTemporary && expiryDays > 0) {
            peerData.expires_in = expiryDays
        }
        securePost('/api/v1/peers', peerData)
            .then(res => {
                if (!res.ok) throw new Error("Creation failed")
                return res.json()
            })
            .then(() => {
                setNewPeerName('')
                setIsTemporary(false)
                setExpiryDays(7)
                setIsCreateOpen(false)
                fetchPeers()
            })
            .catch(err => alert("Failed: " + err.message))
            .finally(() => setCreating(false))
    }

    const handleDeletePeer = (id, name) => {
        if (!confirm(`Delete peer "${name}"? This action cannot be undone.`)) return
        fetch(`/api/v1/peers/${id}`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': getCSRFToken() }
        })
            .then(res => {
                if (!res.ok) throw new Error("Delete failed")
                fetchPeers()
            })
            .catch(err => alert("Failed to delete: " + err.message))
    }

    const handleTogglePeer = (id, name, currentDisabled) => {
        const action = currentDisabled ? 'enable' : 'disable'
        if (!confirm(`${action.charAt(0).toUpperCase() + action.slice(1)} peer "${name}"?`)) return
        fetch(`/api/v1/peers/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify({ disabled: !currentDisabled })
        })
            .then(res => {
                if (!res.ok) throw new Error(`Failed to ${action}`)
                fetchPeers()
            })
            .catch(err => alert(`Failed to ${action}: ` + err.message))
    }

    const handleRenamePeer = (id, currentName) => {
        const newName = prompt(`Rename peer "${currentName}" to:`, currentName)
        if (!newName || newName === currentName) return
        if (!/^[a-zA-Z0-9_-]+$/.test(newName)) {
            alert("Name must be alphanumeric only (a-z, 0-9, -, _)")
            return
        }
        fetch(`/api/v1/peers/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify({ name: newName })
        })
            .then(res => {
                if (!res.ok) throw new Error("Rename failed")
                fetchPeers()
            })
            .catch(err => alert("Failed to rename: " + err.message))
    }

    const handleSetLimit = (id, currentLimit) => {
        const limitStr = prompt("Enter data limit in GB (0 to disable):", currentLimit || "0")
        if (limitStr === null) return

        const limit = parseInt(limitStr)
        if (isNaN(limit) || limit < 0) {
            alert("Invalid limit. Please enter a positive number.")
            return
        }

        fetch(`/api/v1/peers/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify({ data_limit_gb: limit })
        })
            .then(res => {
                if (!res.ok) throw new Error("Failed to set limit")
                fetchPeers()
            })
            .catch(err => alert("Failed to set limit: " + err.message))
    }

    const handleDownloadConfig = (id, name) => {
        window.open(`/api/v1/peers/config?id=${id}`, '_blank')
    }

    if (loading) {
        return (
            <div className="bg-base flex h-screen items-center justify-center">
                <div className="flex flex-col items-center gap-4">
                    <Shield size={48} className="text-accent-cyan animate-pulse" />
                    <div className="text-xs font-mono text-accent-cyan tracking-widest">INITIALIZING SECURE CONNECTION...</div>
                </div>
            </div>
        )
    }

    if (!user) {
        return <Login onLogin={handleLogin} error={loginError} />
    }

    return (
        <div className="bg-base" style={{ minHeight: '100vh' }}>
            <nav className="navbar">
                <div className="navbar-inner">
                    <div className="navbar-brand">
                        <Shield size={22} className="text-accent" />
                        <span>SAMNET<span className="navbar-brand-accent">WG</span></span>
                    </div>

                    <div className="navbar-nav">
                        <NavButton
                            icon={<Activity size={16} />}
                            active={activeTab === 'dashboard'}
                            onClick={() => setActiveTab('dashboard')}
                            title="Dashboard"
                        />
                        <NavButton
                            icon={<Users size={16} />}
                            active={activeTab === 'peers'}
                            onClick={() => setActiveTab('peers')}
                            title="Peers"
                        />
                        <NavButton
                            icon={<BarChart3 size={16} />}
                            active={activeTab === 'observability'}
                            onClick={() => setActiveTab('observability')}
                            title="Observability"
                        />
                        <NavButton
                            icon={<Globe size={16} />}
                            active={activeTab === 'ddns'}
                            onClick={() => setActiveTab('ddns')}
                            title="DDNS"
                        />
                        <NavButton
                            icon={<Settings size={16} />}
                            active={activeTab === 'settings'}
                            onClick={() => setActiveTab('settings')}
                            title="Settings"
                        />
                    </div>

                    <div className="flex items-center gap-3">
                        <StatusIndicator label="API" status={health.live ? 'ok' : 'fail'} />
                        <button onClick={handleLogout} className="nav-link" title="Logout">
                            <LogOut size={16} />
                        </button>
                    </div>
                </div>
            </nav>
            <main style={{ paddingTop: '72px', padding: '72px 24px 24px' }}>
                <div className="container">
                    {activeTab === 'dashboard' && <DashboardView peers={peers} health={health} subnetStats={subnetStats} systemStats={systemStats} />}
                    {activeTab === 'peers' && <PeersView peers={peers} subnet={activeSubnet} loading={loading} onOpenCreate={() => setIsCreateOpen(true)} onRefresh={fetchPeers} onDelete={handleDeletePeer} onDownload={handleDownloadConfig} onToggle={handleTogglePeer} onRename={handleRenamePeer} onSetLimit={handleSetLimit} />}
                    {activeTab === 'observability' && <ObservabilityView health={health} peers={peers} systemStats={systemStats} />}
                    {activeTab === 'ddns' && <DDNSView />}
                    {activeTab === 'settings' && <SettingsView />}
                </div>
            </main>

            <footer style={{ borderTop: '1px solid var(--border-subtle)', padding: '16px', textAlign: 'center' }}>
                <span className="text-muted text-xs">
                    SamNet-WG v1.0.4
                </span>
            </footer>

            {isCreateOpen && (
                <div className="modal-overlay" onClick={() => setIsCreateOpen(false)}>
                    <div className="modal" onClick={e => e.stopPropagation()}>
                        <div className="modal-header">
                            <h3 className="modal-title">Add New Peer</h3>
                        </div>
                        <form onSubmit={handleCreatePeer}>
                            <div className="modal-body">
                                <label className="input-label">Device Name</label>
                                <input
                                    autoFocus
                                    className="input"
                                    placeholder="e.g. macbook-pro"
                                    value={newPeerName}
                                    onChange={e => setNewPeerName(e.target.value)}
                                />

                                <div className="mt-4 flex items-center gap-2">
                                    <input
                                        type="checkbox"
                                        id="tempPeer"
                                        checked={isTemporary}
                                        onChange={e => setIsTemporary(e.target.checked)}
                                        className="w-4 h-4"
                                    />
                                    <label htmlFor="tempPeer" className="text-sm">Temporary Access (expires)</label>
                                </div>

                                {isTemporary && (
                                    <div className="mt-3">
                                        <label className="input-label">Expires in (days)</label>
                                        <select
                                            className="input"
                                            value={expiryDays}
                                            onChange={e => setExpiryDays(parseInt(e.target.value))}
                                        >
                                            <option value="1">1 day</option>
                                            <option value="3">3 days</option>
                                            <option value="7">7 days</option>
                                            <option value="14">14 days</option>
                                            <option value="30">30 days</option>
                                            <option value="90">90 days</option>
                                            <option value="365">1 year</option>
                                        </select>
                                    </div>
                                )}
                            </div>
                            <div className="modal-footer">
                                <button type="button" onClick={() => setIsCreateOpen(false)} className="btn btn-ghost">
                                    Cancel
                                </button>
                                <button type="submit" disabled={creating} className="btn btn-primary">
                                    {creating ? 'Creating...' : 'Create Peer'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    )
}



function NavButton({ icon, active, onClick, title }) {
    return (
        <button
            onClick={onClick}
            className={`nav-link ${active ? 'active' : ''}`}
            title={title}
        >
            {icon}
        </button>
    )
}

function StatusIndicator({ label, status }) {
    const statusClass = status === 'ok' ? 'badge-ok' : status === 'warn' ? 'badge-warn' : 'badge-fail'
    const dotClass = status === 'ok' ? 'status-dot-ok' : status === 'warn' ? 'status-dot-warn' : 'status-dot-fail'
    return (
        <span className={`badge ${statusClass}`}>
            <span className={`status-dot ${dotClass} status-dot-pulse`}></span>
            {label}
        </span>
    )
}

function DashboardView({ peers, health, subnetStats, systemStats }) {
    const activePeers = peers.filter(p => !p.disabled).length
    const stalePeers = peers.filter(p => p.disabled).length

    return (
        <div className="animate-fade-in">
            <div className="panel panel-accent-cyan mb-6">
                <div className="panel-body flex items-center justify-between">
                    <div className="flex items-center gap-4">
                        <div className={`status-dot ${health.live && health.ready ? 'status-dot-ok' : 'status-dot-fail'} status-dot-pulse`} style={{ width: 10, height: 10 }}></div>
                        <div>
                            <div className="text-sm font-semibold">SYSTEM STATUS</div>
                            <div className="text-xs text-muted">
                                {health.live && health.ready ? 'All systems operational' : 'Degraded - check health endpoints'}
                            </div>
                        </div>
                    </div>
                    {/* System Resources Mini-view */}
                    <div className="flex gap-6 text-xs text-muted">
                        <div className="flex items-center gap-2">
                            <Activity size={12} />
                            <span>CPU: <span className="text-primary font-mono">{systemStats?.cpu_percent ? systemStats.cpu_percent.toFixed(1) : 0}%</span></span>
                        </div>
                        <div className="flex items-center gap-2">
                            <Server size={12} />
                            <span>RAM: <span className="text-primary font-mono">{systemStats?.ram_used_mb || 0}MB / {Math.round((systemStats?.ram_total_mb || 0) / 1024)}GB</span></span>
                        </div>
                        <div className="flex items-center gap-2">
                            <Zap size={12} />
                            <span>TEMP: <span className="text-primary font-mono">{systemStats?.cpu_temp_c ? systemStats.cpu_temp_c.toFixed(1) : 0}°C</span></span>
                        </div>
                    </div>
                </div>
            </div>

            <div className="grid grid-cols-4 mb-6">
                <StatCard icon={<Users size={16} />} label="Active Peers" value={activePeers} />
                <StatCard icon={<AlertTriangle size={16} />} label="Stale Peers" value={stalePeers} accent="amber" />
                <StatCard icon={<Network size={16} />} label="Subnet Capacity" value={`${subnetStats.used} / ${subnetStats.total_capacity}`} />
                <StatCard icon={<Wifi size={16} />} label="WireGuard" value="ONLINE" isStatus statusType="ok" />
            </div>


            <div className="grid grid-cols-2">
                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title">
                            <Clock size={14} />
                            RECENT HANDSHAKES
                        </span>
                        <button className="btn btn-ghost btn-sm">
                            <RefreshCw size={12} />
                        </button>
                    </div>
                    <div className="panel-body">
                        {peers.length === 0 ? (
                            <div className="text-muted text-center py-6">No peer activity</div>
                        ) : (
                            <div className="timeline">
                                {peers.slice(0, 5).map((peer, i) => (
                                    <div key={peer.id} className="timeline-item">
                                        <div className={`timeline-dot ${i === 0 ? 'status-dot-ok' : 'bg-panel'}`} style={{ background: i === 0 ? 'var(--status-ok)' : 'var(--bg-hover)' }}></div>
                                        <div className="timeline-content">
                                            <div className="text-sm">{peer.name}</div>
                                            <div className="timeline-time">{peer.allowed_ips}</div>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                </div>

                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title">
                            <TrendingUp size={14} />
                            TOP TALKERS
                        </span>
                    </div>
                    <div className="panel-body">
                        {peers.length === 0 ? (
                            <div className="text-muted text-center py-6">No traffic data</div>
                        ) : (
                            [...peers]
                                .sort((a, b) => {
                                    const parseBytes = (s) => {
                                        if (!s) return 0
                                        const match = s.match(/([\d.]+)\s*(B|KB|MB|GB)/i)
                                        if (!match) return 0
                                        const val = parseFloat(match[1])
                                        const unit = match[2].toUpperCase()
                                        return val * ({ 'B': 1, 'KB': 1024, 'MB': 1024 * 1024, 'GB': 1024 * 1024 * 1024 }[unit] || 1)
                                    }
                                    return (parseBytes(b.rx) + parseBytes(b.tx)) - (parseBytes(a.rx) + parseBytes(a.tx))
                                })
                                .slice(0, 5)
                                .map((peer, i) => (
                                    <div key={peer.id} className="flex items-center justify-between py-2" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                                        <div className="flex items-center gap-2">
                                            <span className="text-xs font-bold text-accent" style={{ width: 16 }}>#{i + 1}</span>
                                            <span className="text-sm">{peer.name}</span>
                                        </div>
                                        <span className="text-xs font-mono text-muted">↓{peer.rx || '0 B'} ↑{peer.tx || '0 B'}</span>
                                    </div>
                                ))
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}

function StatCard({ icon, label, value, accent, isStatus, statusType }) {
    const accentColor = accent === 'amber' ? 'var(--accent-amber)' : 'var(--accent-cyan)'
    return (
        <div className="stat-card">
            <div className="stat-label" style={{ color: accentColor }}>
                {icon}
                {label}
            </div>
            {isStatus ? (
                <StatusIndicator label={value} status={statusType} />
            ) : (
                <div className="stat-value">{value}</div>
            )}
        </div>
    )
}

function HealthItem({ label, status, detail }) {
    return (
        <div className="flex items-center justify-between py-2" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
            <div className="flex items-center gap-3">
                <span className={`status-dot status-dot-${status}`}></span>
                <span className="text-sm">{label}</span>
            </div>
            <span className="text-xs font-mono text-muted">{detail}</span>
        </div>
    )
}

function PeersView({ peers, subnet, loading, onOpenCreate, onRefresh, onDelete, onDownload, onToggle, onRename, onSetLimit }) {
    return (
        <div className="animate-fade-in">
            <div className="panel">
                <div className="panel-header">
                    <div className="flex flex-col">
                        <span className="panel-title">
                            <Users size={14} />
                            CONNECTED PEERS ({peers.length})
                        </span>
                        <div className="flex items-center gap-2 mt-1">
                            <span className="badge badge-info text-[10px] font-mono px-2 py-0">ACTIVE NETWORK: {subnet}</span>
                            <span className="text-[10px] text-muted">Synced with CLI</span>
                        </div>
                    </div>
                    <div className="flex gap-2">
                        <button onClick={onRefresh} className="btn btn-ghost btn-sm">
                            <RefreshCw size={12} />
                            Refresh
                        </button>
                        <button onClick={onOpenCreate} className="btn btn-primary btn-sm">
                            <Plus size={12} />
                            New Peer
                        </button>
                    </div>
                </div>

                <div className="table-container">
                    <table className="table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Allowed IPs</th>
                                <th>Status</th>
                                <th>Last Handshake</th>
                                <th>Transfer</th>
                                <th>Limit</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {loading ? (
                                <tr><td colSpan="6" className="text-center py-6 text-muted">Loading...</td></tr>
                            ) : peers.length === 0 ? (
                                <tr>
                                    <td colSpan="6" className="text-center py-6">
                                        <div className="text-muted mb-2">No peers configured</div>
                                        <button onClick={onOpenCreate} className="btn btn-primary btn-sm">Create First Peer</button>
                                    </td>
                                </tr>
                            ) : peers.map(peer => (
                                <tr key={peer.id}>
                                    <td className="cell-primary">{peer.name}</td>
                                    <td className="cell-mono">{peer.allowed_ips}</td>
                                    <td>
                                        <span className={`badge ${peer.disabled ? 'badge-fail' : 'badge-ok'}`}>
                                            <span className={`status-dot ${peer.disabled ? 'status-dot-fail' : 'status-dot-ok'}`}></span>
                                            {peer.disabled ? 'DISABLED' : 'ACTIVE'}
                                        </span>
                                    </td>
                                    <td className="cell-mono text-muted">{peer.last_handshake || '--'}</td>
                                    <td className="cell-mono text-muted">{peer.rx || '0 B'} / {peer.tx || '0 B'}</td>
                                    <td className="min-w-[120px]">
                                        {peer.data_limit_gb > 0 ? (
                                            <div className="flex flex-col gap-1">
                                                <div className="flex justify-between text-[10px] items-center">
                                                    <span className="font-mono text-muted">{peer.data_limit_gb} GB</span>
                                                    {(() => {
                                                        const total = (peer.rx_bytes || 0) + (peer.tx_bytes || 0)
                                                        const limit = peer.data_limit_gb * 1024 * 1024 * 1024
                                                        const pct = Math.min(100, Math.round((total / limit) * 100))
                                                        return (
                                                            <span className={pct >= 90 ? "text-warn" : "text-muted"}>{pct}%</span>
                                                        )
                                                    })()}
                                                </div>
                                                <div className="h-1.5 w-full bg-base-300 rounded-full overflow-hidden">
                                                    {(() => {
                                                        const total = (peer.rx_bytes || 0) + (peer.tx_bytes || 0)
                                                        const limit = peer.data_limit_gb * 1024 * 1024 * 1024
                                                        const pct = Math.min(100, Math.round((total / limit) * 100))
                                                        return (
                                                            <div className={`h-full rounded-full ${pct >= 100 ? 'bg-fail' : pct >= 90 ? 'bg-warn' : 'bg-primary'}`} style={{ width: `${pct}%` }}></div>
                                                        )
                                                    })()}
                                                </div>
                                            </div>
                                        ) : (
                                            <span className="text-[10px] text-muted">No Limit</span>
                                        )}
                                    </td>
                                    <td>
                                        <div className="flex gap-1">
                                            <button onClick={() => onSetLimit(peer.id, peer.data_limit_gb)} className="btn btn-ghost btn-sm text-info" title="Set Data Limit">
                                                <TrendingUp size={12} />
                                            </button>
                                            <button onClick={() => onToggle(peer.id, peer.name, peer.disabled)} className={`btn btn-ghost btn-sm ${peer.disabled ? 'text-ok' : 'text-warn'}`} title={peer.disabled ? 'Enable' : 'Disable'}>
                                                {peer.disabled ? <Play size={12} /> : <Pause size={12} />}
                                            </button>
                                            <button onClick={() => onRename(peer.id, peer.name)} className="btn btn-ghost btn-sm" title="Rename">
                                                <Edit2 size={12} />
                                            </button>
                                            <a href={`/api/v1/peers/qr?id=${peer.id}`} target="_blank" className="btn btn-ghost btn-sm" title="QR Code">
                                                <Eye size={12} />
                                            </a>
                                            <button onClick={() => onDownload(peer.id, peer.name)} className="btn btn-ghost btn-sm" title="Download Config">
                                                <Download size={12} />
                                            </button>
                                            <button onClick={() => onDelete(peer.id, peer.name)} className="btn btn-ghost btn-sm text-fail" title="Delete">
                                                <Trash2 size={12} />
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    )
}


function ObservabilityView({ health, peers, systemStats }) {
    // Parse bytes from string like "1.5 MB" or "234 KB"
    const parseBytes = (s) => {
        if (!s) return 0
        const match = s.match(/([\d.]+)\s*(B|KB|MB|GB)/i)
        if (!match) return 0
        const val = parseFloat(match[1])
        const unit = match[2].toUpperCase()
        return val * ({ 'B': 1, 'KB': 1024, 'MB': 1024 * 1024, 'GB': 1024 * 1024 * 1024 }[unit] || 1)
    }

    // Calculate totals from peers
    const totalRxBytes = peers.reduce((sum, p) => sum + parseBytes(p.rx), 0)
    const totalTxBytes = peers.reduce((sum, p) => sum + parseBytes(p.tx), 0)
    const activePeers = peers.filter(p => !p.disabled).length
    const disabledPeers = peers.filter(p => p.disabled).length

    // Format uptime
    const formatUptime = (seconds) => {
        if (!seconds) return '--'
        const days = Math.floor(seconds / 86400)
        const hours = Math.floor((seconds % 86400) / 3600)
        const mins = Math.floor((seconds % 3600) / 60)
        if (days > 0) return `${days}d ${hours}h`
        if (hours > 0) return `${hours}h ${mins}m`
        return `${mins}m`
    }

    // Alerts logic
    const alerts = []
    if (systemStats?.cpu_percent > 80) alerts.push({ type: 'warn', msg: 'High CPU usage' })
    if (systemStats?.ram_percent > 85) alerts.push({ type: 'warn', msg: 'High RAM usage' })
    if (systemStats?.cpu_temp_c > 70) alerts.push({ type: 'warn', msg: 'High CPU temperature' })
    if (systemStats?.disk_percent > 90) alerts.push({ type: 'fail', msg: 'Low disk space' })
    if (!health.live) alerts.push({ type: 'fail', msg: 'API not responding' })
    if (!health.ready) alerts.push({ type: 'fail', msg: 'API not ready' })

    return (
        <div className="animate-fade-in">
            {/* Top Stats Row */}
            <div className="grid grid-cols-4 mb-6">
                <div className="stat-card">
                    <div className="stat-label"><Users size={14} /> Total Peers</div>
                    <div className="stat-value-sm font-mono">{peers.length}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label"><CheckCircle size={14} /> Active</div>
                    <div className="stat-value-sm font-mono" style={{ color: 'var(--status-ok)' }}>{activePeers}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label"><Pause size={14} /> Disabled</div>
                    <div className="stat-value-sm font-mono" style={{ color: 'var(--accent-amber)' }}>{disabledPeers}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label"><Server size={14} /> Uptime</div>
                    <div className="stat-value-sm font-mono">{formatUptime(systemStats?.uptime_seconds)}</div>
                </div>
            </div>

            {/* Second Row: Health & Traffic */}
            <div className="grid grid-cols-2 mb-6">
                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title"><CheckCircle size={14} /> HEALTH ENDPOINTS</span>
                    </div>
                    <div className="panel-body">
                        <HealthItem label="/health/live" status={health.live ? 'ok' : 'fail'} detail={health.live ? '200 OK' : 'FAIL'} />
                        <HealthItem label="/health/ready" status={health.ready ? 'ok' : 'fail'} detail={health.ready ? '200 OK' : 'FAIL'} />
                        <HealthItem label="Database" status="ok" detail="SQLite WAL" />
                        <HealthItem label="WireGuard" status="ok" detail="wg0 active" />
                    </div>
                </div>

                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title"><BarChart3 size={14} /> TRAFFIC SUMMARY</span>
                    </div>
                    <div className="panel-body">
                        <div className="flex justify-between mb-2">
                            <span className="text-muted text-xs">Total TX (Upload)</span>
                            <span className="font-mono text-xs text-accent">{formatBytes(totalTxBytes)}</span>
                        </div>
                        <div className="health-bar mb-3">
                            <div className="health-bar-fill health-bar-ok" style={{ width: `${Math.min(100, totalTxBytes / (1024 * 1024 * 100) * 100)}%` }}></div>
                        </div>
                        <div className="flex justify-between mb-2">
                            <span className="text-muted text-xs">Total RX (Download)</span>
                            <span className="font-mono text-xs" style={{ color: 'var(--accent-amber)' }}>{formatBytes(totalRxBytes)}</span>
                        </div>
                        <div className="health-bar">
                            <div className="health-bar-fill health-bar-warn" style={{ width: `${Math.min(100, totalRxBytes / (1024 * 1024 * 100) * 100)}%` }}></div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Third Row: System & Alerts */}
            <div className="grid grid-cols-2">
                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title"><Activity size={14} /> SYSTEM RESOURCES</span>
                    </div>
                    <div className="panel-body">
                        <HealthItem label="CPU" status={systemStats?.cpu_percent > 80 ? 'warn' : 'ok'} detail={`${systemStats?.cpu_percent?.toFixed(1) || 0}%`} />
                        <HealthItem label="RAM" status={systemStats?.ram_percent > 85 ? 'warn' : 'ok'} detail={`${systemStats?.ram_used_mb || 0}MB / ${Math.round((systemStats?.ram_total_mb || 0) / 1024)}GB`} />
                        <HealthItem label="Disk" status={systemStats?.disk_percent > 90 ? 'fail' : 'ok'} detail={`${systemStats?.disk_percent?.toFixed(1) || 0}%`} />
                        <HealthItem label="Temp" status={systemStats?.cpu_temp_c > 70 ? 'warn' : 'ok'} detail={`${systemStats?.cpu_temp_c?.toFixed(1) || 0}°C`} />
                    </div>
                </div>

                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title"><AlertTriangle size={14} /> ALERTS</span>
                    </div>
                    <div className="panel-body">
                        {alerts.length === 0 ? (
                            <div className="text-center py-4">
                                <CheckCircle size={24} className="text-ok mx-auto mb-2" />
                                <div className="text-sm text-muted">All systems nominal</div>
                            </div>
                        ) : (
                            alerts.map((alert, i) => (
                                <div key={i} className={`flex items-center gap-2 py-2 ${i < alerts.length - 1 ? 'border-b border-subtle' : ''}`}>
                                    <span className={`status-dot status-dot-${alert.type}`}></span>
                                    <span className="text-sm">{alert.msg}</span>
                                </div>
                            ))
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}

function DDNSView() {
    const [ddnsConfig, setDdnsConfig] = useState(null)
    const [ddnsStatus, setDdnsStatus] = useState(null)
    const [loading, setLoading] = useState(true)
    const [saving, setSaving] = useState(false)
    const [formData, setFormData] = useState({
        enabled: false,
        provider: '',
        domain: '',
        token: ''
    })

    useEffect(() => {
        Promise.all([
            fetch('/api/v1/ddns/config').then(r => r.ok ? r.json() : null).catch(() => null),
            fetch('/api/v1/ddns/status').then(r => r.ok ? r.json() : null).catch(() => null)
        ]).then(([config, status]) => {
            if (config) {
                setDdnsConfig(config)
                setFormData({
                    enabled: config.enabled || false,
                    provider: config.provider || '',
                    domain: config.domain || '',
                    token: ''
                })
            }
            if (status) setDdnsStatus(status)
            setLoading(false)
        })
    }, [])

    const handleSave = () => {
        setSaving(true)
        fetch('/api/v1/ddns/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify(formData)
        })
            .then(r => r.ok ? r.json() : Promise.reject())
            .then(() => {
                alert('DDNS configuration saved!')
                setSaving(false)
            })
            .catch(() => {
                alert('Failed to save DDNS configuration')
                setSaving(false)
            })
    }

    const handleForceUpdate = () => {
        fetch('/api/v1/ddns/force-update', { method: 'POST', headers: { 'X-CSRF-Token': getCSRFToken() } })
            .then(r => r.ok ? r.json() : Promise.reject())
            .then(() => alert('Force update triggered'))
            .catch(() => alert('Force update failed'))
    }



    if (loading) {
        return (
            <div className="animate-fade-in text-center py-12">
                <div className="text-muted">Loading DDNS configuration...</div>
            </div>
        )
    }

    return (
        <div className="animate-fade-in">
            <div className="panel panel-accent-cyan mb-6">
                <div className="panel-header">
                    <span className="panel-title"><Globe size={14} /> DDNS STATUS</span>
                    <StatusIndicator label={formData.enabled ? 'ENABLED' : 'DISABLED'} status={formData.enabled ? 'ok' : 'warn'} />
                </div>
                <div className="panel-body">
                    {ddnsStatus && ddnsStatus.last_update ? (
                        <div className="grid grid-cols-2" style={{ gap: '24px' }}>
                            <div>
                                <div className="text-xs text-muted uppercase mb-1">Provider</div>
                                <div className="font-mono">{ddnsStatus.provider || formData.provider || 'Not configured'}</div>
                            </div>
                            <div>
                                <div className="text-xs text-muted uppercase mb-1">Domain</div>
                                <div className="font-mono text-accent">{ddnsStatus.domain || formData.domain || 'Not configured'}</div>
                            </div>
                            <div>
                                <div className="text-xs text-muted uppercase mb-1">Current IP</div>
                                <div className="font-mono">{ddnsStatus.current_ip || '--'}</div>
                            </div>
                            <div>
                                <div className="text-xs text-muted uppercase mb-1">Last Update</div>
                                <div className="font-mono text-muted">{ddnsStatus.last_update || 'Never'}</div>
                            </div>
                        </div>
                    ) : (
                        <div className="text-muted text-center py-4">
                            No DDNS data available. Configure DDNS below to enable dynamic DNS updates.
                        </div>
                    )}
                </div>
            </div>

            <div className="panel mb-6">
                <div className="panel-header">
                    <span className="panel-title"><Settings size={14} /> DDNS CONFIGURATION</span>
                </div>
                <div className="panel-body">
                    <div className="grid grid-cols-2" style={{ gap: '16px' }}>
                        <div>
                            <label className="input-label">Provider</label>
                            <select
                                className="input"
                                value={formData.provider}
                                onChange={e => setFormData({ ...formData, provider: e.target.value })}
                            >
                                <option value="">Select Provider...</option>
                                <option value="duckdns">DuckDNS</option>
                                <option value="cloudflare">Cloudflare</option>
                                <option value="webhook">Custom Webhook</option>
                            </select>
                        </div>
                        <div>
                            <label className="input-label">Domain</label>
                            <input
                                className="input"
                                placeholder="e.g. vpn.example.com"
                                value={formData.domain}
                                onChange={e => setFormData({ ...formData, domain: e.target.value })}
                            />
                        </div>
                        <div className="col-span-2">
                            <label className="input-label">API Token / Key</label>
                            <input
                                type="password"
                                className="input"
                                placeholder="Enter API token (leave blank to keep existing)"
                                value={formData.token}
                                onChange={e => setFormData({ ...formData, token: e.target.value })}
                            />
                        </div>
                        <div className="flex items-center gap-3">
                            <input
                                type="checkbox"
                                id="ddns-enabled"
                                checked={formData.enabled}
                                onChange={e => setFormData({ ...formData, enabled: e.target.checked })}
                            />
                            <label htmlFor="ddns-enabled" className="text-sm">Enable DDNS Auto-Update</label>
                        </div>
                    </div>
                    <div className="flex gap-3 mt-6">
                        <button onClick={handleSave} disabled={saving} className="btn btn-primary">
                            {saving ? 'Saving...' : 'Save Configuration'}
                        </button>
                        <button onClick={handleForceUpdate} className="btn btn-secondary">
                            Force Update Now
                        </button>
                    </div>
                </div>
            </div>
        </div>
    )
}

function SettingsView() {
    const [networkSettings, setNetworkSettings] = useState({
        exit_node_enabled: false,
        split_tunnel: false,
        pihole_enabled: false,
        pihole_server: ''
    })
    const [loading, setLoading] = useState(true)
    const [subnet, setSubnet] = useState('10.100.0.0/24')
    const [subnetSaving, setSubnetSaving] = useState(false)

    const subnetPresets = [
        { value: '10.100.0.0/24', label: '10.100.0.0/24 (254 peers)' },
        { value: '10.200.0.0/24', label: '10.200.0.0/24 (254 peers)' },
        { value: '10.50.0.0/24', label: '10.50.0.0/24 (254 peers)' },
        { value: '172.16.0.0/24', label: '172.16.0.0/24 (254 peers)' },
        { value: '10.0.0.0/24', label: '10.0.0.0/24 (254 peers)' },
        { value: '10.100.0.0/23', label: '10.100.0.0/23 (510 peers)' },
        { value: '10.100.0.0/22', label: '10.100.0.0/22 (1022 peers)' }
    ]

    useEffect(() => {
        Promise.all([
            fetch('/api/v1/network/settings').then(r => r.ok ? r.json() : {}),
            fetch('/api/v1/network/subnet').then(r => r.ok ? r.json() : {})
        ]).then(([settings, subnetData]) => {
            setNetworkSettings({
                exit_node_enabled: settings.exit_node_enabled || false,
                split_tunnel: settings.split_tunnel || false,
                pihole_enabled: false,
                pihole_server: ''
            })
            if (subnetData.subnet) setSubnet(subnetData.subnet)
            setLoading(false)
        }).catch(() => setLoading(false))
    }, [])

    const toggleSetting = (key) => {
        const newSettings = { ...networkSettings, [key]: !networkSettings[key] }
        setNetworkSettings(newSettings)
        fetch('/api/v1/network/settings', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify(newSettings)
        }).catch(console.error)
    }

    const handleSubnetChange = (newSubnet) => {
        setSubnet(newSubnet)
        setSubnetSaving(true)
        fetch('/api/v1/network/subnet', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify({ subnet: newSubnet })
        })
            .then(r => { if (!r.ok) throw new Error('Failed') })
            .catch(err => alert('Failed to save: ' + err.message))
            .finally(() => setSubnetSaving(false))
    }

    const [passwordForm, setPasswordForm] = useState({ current: '', newPass: '', confirm: '' })
    const [passwordSaving, setPasswordSaving] = useState(false)

    const handlePasswordChange = (e) => {
        e.preventDefault()
        if (passwordForm.newPass !== passwordForm.confirm) {
            alert('New passwords do not match')
            return
        }
        if (passwordForm.newPass.length < 8) {
            alert('Password must be at least 8 characters')
            return
        }
        setPasswordSaving(true)
        fetch('/api/v1/users/password', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCSRFToken() },
            body: JSON.stringify({ current_password: passwordForm.current, new_password: passwordForm.newPass })
        })
            .then(res => {
                if (!res.ok) throw new Error('Password change failed')
                alert('Password changed successfully!')
                setPasswordForm({ current: '', newPass: '', confirm: '' })
            })
            .catch(err => alert('Failed: ' + err.message))
            .finally(() => setPasswordSaving(false))
    }

    return (
        <div className="animate-fade-in">
            <div className="grid grid-cols-2 mb-6">


                <div className="panel">
                    <div className="panel-header">
                        <span className="panel-title"><Lock size={14} /> ACCOUNT</span>
                    </div>
                    <div className="panel-body">
                        <form onSubmit={handlePasswordChange}>
                            <div className="mb-3">
                                <label className="input-label">Current Password</label>
                                <input
                                    type="password"
                                    className="input"
                                    value={passwordForm.current}
                                    onChange={e => setPasswordForm(p => ({ ...p, current: e.target.value }))}
                                    required
                                />
                            </div>
                            <div className="mb-3">
                                <label className="input-label">New Password</label>
                                <input
                                    type="password"
                                    className="input"
                                    value={passwordForm.newPass}
                                    onChange={e => setPasswordForm(p => ({ ...p, newPass: e.target.value }))}
                                    required
                                />
                            </div>
                            <div className="mb-3">
                                <label className="input-label">Confirm New Password</label>
                                <input
                                    type="password"
                                    className="input"
                                    value={passwordForm.confirm}
                                    onChange={e => setPasswordForm(p => ({ ...p, confirm: e.target.value }))}
                                    required
                                />
                            </div>
                            <button type="submit" className="btn btn-primary btn-sm" disabled={passwordSaving}>
                                {passwordSaving ? 'Saving...' : 'Change Password'}
                            </button>
                        </form>
                    </div>
                </div>
            </div>

            <div className="panel">
                <div className="panel-header">
                    <span className="panel-title"><Download size={14} /> BACKUP & RESTORE</span>
                </div>
                <div className="panel-body">
                    <div className="flex items-center justify-between">
                        <div>
                            <div className="text-sm mb-1">Download Full Backup</div>
                            <div className="text-xs text-muted">Includes database, encryption keys, and WireGuard config</div>
                        </div>
                        <a href="/api/v1/backup?download=true" className="btn btn-primary btn-sm">
                            <Download size={12} />
                            Download Backup
                        </a>
                    </div>
                </div>
            </div>
        </div>
    )
}

function SettingToggle({ label, description, enabled, onToggle }) {
    return (
        <div className="flex items-center justify-between py-3" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
            <div>
                <div className="text-sm">{label}</div>
                <div className="text-xs text-muted">{description}</div>
            </div>
            <button
                onClick={onToggle}
                className={`toggle-btn ${enabled ? 'toggle-btn-active' : ''}`}
                style={{
                    width: '44px',
                    height: '24px',
                    borderRadius: '12px',
                    background: enabled ? 'var(--accent-cyan)' : 'var(--bg-hover)',
                    border: 'none',
                    cursor: 'pointer',
                    position: 'relative',
                    transition: 'background 0.2s'
                }}
            >
                <span style={{
                    position: 'absolute',
                    top: '2px',
                    left: enabled ? '22px' : '2px',
                    width: '20px',
                    height: '20px',
                    borderRadius: '50%',
                    background: '#fff',
                    transition: 'left 0.2s',
                    boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
                }}></span>
            </button>
        </div>
    )
}

export default App

