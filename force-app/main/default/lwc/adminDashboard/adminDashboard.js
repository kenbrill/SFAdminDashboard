import { LightningElement, api, track } from 'lwc';
import { loadScript }                   from 'lightning/platformResourceLoader';
import chartjsResource                  from '@salesforce/resourceUrl/chartjs';
import getDashboardData                 from '@salesforce/apex/AdminDashboardController.getDashboardData';

const OBJECT_COLORS = {
    Account:     'rgba(21, 137, 238, 0.8)',
    Contact:     'rgba(76, 187, 124, 0.8)',
    Lead:        'rgba(255, 165, 0, 0.8)',
    Opportunity: 'rgba(148, 93, 214, 0.8)',
    Case:        'rgba(255, 80, 80, 0.8)'
};

export default class AdminDashboard extends LightningElement {

    @api refreshIntervalSeconds = 30;

    @track activeUsersCount   = '—';
    @track loginsToday        = '—';
    @track activeEditorsCount = '—';
    @track totalRecords       = '—';
    @track adminChangesToday  = '—';
    @track recentAuditTrail   = [];
    @track hasAuditTrail      = false;
    @track lastUpdated        = 'never';
    @track isLoading          = false;
    @track errorMessage       = null;

    _chartsInitialized = false;
    _charts            = {};
    _pendingData       = null;
    _refreshTimer      = null;

    connectedCallback() {
        this._scheduleRefresh();
        this._loadData();
    }

    disconnectedCallback() {
        if (this._refreshTimer) {
            clearInterval(this._refreshTimer);
        }
    }

    renderedCallback() {
        if (this._chartsInitialized) return;
        loadScript(this, chartjsResource)
            .then(() => {
                this._chartsInitialized = true;
                if (this._pendingData) {
                    this._renderCharts(this._pendingData);
                    this._pendingData = null;
                }
            })
            .catch(err => {
                this.errorMessage = 'Failed to load Chart.js: ' + err.message;
            });
    }

    handleRefresh() {
        this._loadData();
    }

    _scheduleRefresh() {
        const interval = Math.max(10, parseInt(this.refreshIntervalSeconds, 10) || 30) * 1000;
        this._refreshTimer = setInterval(() => this._loadData(), interval);
    }

    _loadData() {
        this.isLoading    = true;
        this.errorMessage = null;
        getDashboardData()
            .then(data => {
                this._applyKpis(data);
                if (this._chartsInitialized) {
                    this._renderCharts(data);
                } else {
                    this._pendingData = data;
                }
                this.isLoading   = false;
                this.lastUpdated = new Date().toLocaleTimeString();
            })
            .catch(err => {
                this.isLoading    = false;
                this.errorMessage = 'Error loading dashboard data: ' + (err.body ? err.body.message : err.message);
            });
    }

    _applyKpis(data) {
        this.activeUsersCount   = data.activeUsersCount;
        this.loginsToday        = data.loginsToday;
        this.activeEditorsCount = data.activeEditorsCount;
        this.totalRecords       = data.totalRecords;
        this.adminChangesToday  = data.adminChangesToday;
        this.recentAuditTrail   = data.recentAuditTrail || [];
        this.hasAuditTrail      = this.recentAuditTrail.length > 0;
    }

    _renderCharts(data) {
        this._renderLoginTrend(data.loginTrend || []);
        this._renderTopUsers(data.topActiveUsers || []);
        this._renderObjectCounts(data.objectCounts || []);
        this._renderTodayModified(data.todayModified || []);
    }

    _getCanvas(dataId) {
        return this.template.querySelector(`canvas[data-id="${dataId}"]`);
    }

    _destroyChart(key) {
        if (this._charts[key]) {
            this._charts[key].destroy();
            delete this._charts[key];
        }
    }

    _renderLoginTrend(loginTrend) {
        const canvas = this._getCanvas('loginTrend');
        if (!canvas) return;
        this._destroyChart('loginTrend');

        const hours  = Array.from({ length: 24 }, (_, i) => i);
        const counts = hours.map(h => {
            const entry = loginTrend.find(l => l.hour === h);
            return entry ? entry.count : 0;
        });

        this._charts.loginTrend = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: hours.map(h => `${String(h).padStart(2, '0')}:00`),
                datasets: [{
                    label: 'Logins',
                    data: counts,
                    backgroundColor: 'rgba(21, 137, 238, 0.7)',
                    borderColor: 'rgba(21, 137, 238, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { stepSize: 1, color: '#555' },
                        grid: { color: 'rgba(0,0,0,0.05)' }
                    },
                    x: { ticks: { color: '#555', maxRotation: 45 }, grid: { display: false } }
                }
            }
        });
    }

    _renderTopUsers(topUsers) {
        const canvas = this._getCanvas('topUsers');
        if (!canvas) return;
        this._destroyChart('topUsers');

        if (!topUsers.length) {
            this._charts.topUsers = new window.Chart(canvas, this._emptyChart('No login data this week'));
            return;
        }

        this._charts.topUsers = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: topUsers.map(u => u.userName),
                datasets: [{
                    label: 'Logins this week',
                    data: topUsers.map(u => u.loginCount),
                    backgroundColor: topUsers.map((_, i) => `hsla(${200 + i * 25}, 70%, 55%, 0.8)`),
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                indexAxis: 'y',
                plugins: { legend: { display: false } },
                scales: {
                    x: {
                        beginAtZero: true,
                        ticks: { stepSize: 1, color: '#555' },
                        grid: { color: 'rgba(0,0,0,0.05)' }
                    },
                    y: { ticks: { color: '#555' }, grid: { display: false } }
                }
            }
        });
    }

    _renderObjectCounts(objectCounts) {
        const canvas = this._getCanvas('objectCounts');
        if (!canvas) return;
        this._destroyChart('objectCounts');

        this._charts.objectCounts = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: objectCounts.map(o => o.objectName),
                datasets: [{
                    label: 'Total Records',
                    data: objectCounts.map(o => o.count),
                    backgroundColor: objectCounts.map(o => OBJECT_COLORS[o.objectName] || 'rgba(100,100,100,0.7)'),
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { stepSize: 1, color: '#555' },
                        grid: { color: 'rgba(0,0,0,0.05)' }
                    },
                    x: { ticks: { color: '#555' }, grid: { display: false } }
                }
            }
        });
    }

    _renderTodayModified(todayModified) {
        const canvas = this._getCanvas('todayModified');
        if (!canvas) return;
        this._destroyChart('todayModified');

        this._charts.todayModified = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: todayModified.map(o => o.objectName),
                datasets: [{
                    label: 'Modified Today',
                    data: todayModified.map(o => o.count),
                    backgroundColor: todayModified.map(o => OBJECT_COLORS[o.objectName] || 'rgba(100,100,100,0.7)'),
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { stepSize: 1, color: '#555' },
                        grid: { color: 'rgba(0,0,0,0.05)' }
                    },
                    x: { ticks: { color: '#555' }, grid: { display: false } }
                }
            }
        });
    }

    _emptyChart(message) {
        return {
            type: 'bar',
            data: { labels: [message], datasets: [{ data: [0] }] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { display: false }, x: { ticks: { color: '#999' } } }
            }
        };
    }
}
