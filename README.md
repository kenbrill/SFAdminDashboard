# Salesforce Admin Dashboard

A Lightning Web Component (LWC) that provides a real-time activity monitor for Salesforce admins. Displays logins, active editors, record counts, and audit trail data — all pulled live from your org via Apex.

## What It Shows

**KPI Cards (sidebar)**
| Card | Data Source |
|------|-------------|
| Active Users | `User` WHERE IsActive = true |
| Logins Today | `LoginHistory` WHERE LoginTime = TODAY |
| Active Editors | Users who modified any record in the last hour |
| Total Records | Sum of Account + Contact + Lead + Opportunity + Case |
| Admin Changes Today | `SetupAuditTrail` WHERE CreatedDate = TODAY |

**Charts**
- **Logins by Hour** — bar chart of login events bucketed by hour, today only
- **Top Active Users** — horizontal bar of top 8 users by login count (last 7 days)
- **Total Records by Object** — bar chart of total record counts across main objects
- **Records Modified Today** — bar chart of how many records were touched today per object
- **Storage Usage — Last 90 Days** — line chart of Data Storage % and File Storage % of org limits, populated by the daily scheduler

**Audit Trail Table**
- Last 15 `SetupAuditTrail` entries with timestamp, section, action, and changed-by user

## Project Structure

```
SFAdminDashboard/
├── sfdx-project.json
├── .forceignore
└── force-app/main/default/
    ├── classes/
    │   ├── AdminDashboardController.cls              # Apex controller (getDashboardData + getStorageHistory)
    │   ├── AdminDashboardController.cls-meta.xml
    │   ├── AdminDashboardControllerTest.cls          # Apex test class (8 test methods)
    │   ├── AdminDashboardControllerTest.cls-meta.xml
    │   ├── OrgStorageService.cls                     # Limits API callout + upsert + 90-day purge
    │   ├── OrgStorageService.cls-meta.xml
    │   ├── OrgStorageCaptureJob.cls                  # Queueable (implements AllowsCallouts)
    │   ├── OrgStorageCaptureJob.cls-meta.xml
    │   ├── OrgStorageScheduler.cls                   # Schedulable — enqueues OrgStorageCaptureJob
    │   ├── OrgStorageScheduler.cls-meta.xml
    │   ├── OrgStorageServiceTest.cls                 # 6 test methods with HttpCalloutMock
    │   └── OrgStorageServiceTest.cls-meta.xml
    ├── lwc/adminDashboard/
    │   ├── adminDashboard.html                       # Component template
    │   ├── adminDashboard.js                         # Chart.js + Apex wiring
    │   ├── adminDashboard.css                        # Dashboard styles
    │   └── adminDashboard.js-meta.xml                # Target: App Page, Home Page
    ├── objects/OrgStorageSnapshot__c/
    │   ├── OrgStorageSnapshot__c.object-meta.xml     # Custom object
    │   └── fields/                                   # 6 custom fields (Date, Text ExternalID, 4× Number)
    ├── remoteSiteSettings/
    │   └── OrgLimitsAPI.remoteSite-meta.xml          # Allows callout to org's own Limits API
    └── staticresources/
        ├── chartjs.js                                # Chart.js 3.9.1 (self-hosted)
        └── chartjs.resource-meta.xml
```

## Requirements

- Salesforce CLI (`sf`) installed and authenticated
- Admin profile (required for `LoginHistory` and `SetupAuditTrail` access)

## Deploy

```bash
sf project deploy start --target-org <your-org-alias> --source-dir force-app
```

## Storage Tracking

The dashboard records daily storage snapshots in the `OrgStorageSnapshot__c` custom object. A scheduler runs at 2 AM daily, enqueues a Queueable that calls the Salesforce Limits REST API, and upserts the result. Records older than 90 days are automatically purged.

### Architecture

```
OrgStorageScheduler (Schedulable, runs 2 AM daily)
  └─ enqueues OrgStorageCaptureJob (Queueable + AllowsCallouts)
       └─ OrgStorageService.captureSnapshot()
            ├─ GET /services/data/v62.0/limits/
            ├─ upsert OrgStorageSnapshot__c (keyed on SnapshotDateKey__c)
            └─ delete records older than 90 days
```

### Activate the Scheduler

The scheduler was activated on initial deploy with:

```apex
System.schedule(
    'OrgStorage Daily Capture',
    '0 0 2 * * ?',
    new OrgStorageScheduler()
);
```

To re-activate after a full re-deploy (if the scheduled job was removed):
```bash
sf apex run --file activate_scheduler.apex --target-org <your-org-alias>
```

To capture an immediate snapshot (useful for seeding the first data point):
```bash
cat > /tmp/first_snap.apex << 'EOF'
System.enqueueJob(new OrgStorageCaptureJob());
EOF
sf apex run --file /tmp/first_snap.apex --target-org <your-org-alias>
```

### OrgStorageSnapshot__c Fields

| Field | Type | Notes |
|-------|------|-------|
| `Name` | AutoNumber | SNAP-{0000} |
| `SnapshotDateKey__c` | Text(10), External ID, Unique | YYYY-MM-DD — used for upsert de-dup |
| `SnapshotDate__c` | Date | Date of the snapshot |
| `DataMBMax__c` | Number | Org data storage limit in MB |
| `DataMBUsed__c` | Number | Data storage used in MB |
| `FileMBMax__c` | Number | Org file storage limit in MB |
| `FileMBUsed__c` | Number | File storage used in MB |

## Tests

Two test classes cover the project — 14 test methods total.

### AdminDashboardControllerTest (8 methods)

| Test Method | What It Covers |
|-------------|----------------|
| `testGetDashboardData_returnsData` | Method returns a non-null object; all scalar KPIs are non-negative |
| `testGetDashboardData_objectCounts` | `objectCounts` has exactly 5 entries, one per object, all with valid names and counts |
| `testGetDashboardData_todayModified` | `todayModified` has 5 entries and reflects records inserted in `@TestSetup` |
| `testGetDashboardData_totalRecordsMatchesSumOfCounts` | `totalRecords` equals the sum of all `objectCounts` entries |
| `testGetDashboardData_listsNonNull` | All list fields (`loginTrend`, `recentAuditTrail`, `topActiveUsers`, etc.) are non-null |
| `testInnerClasses` | Direct instantiation and field assignment of all four inner classes |
| `testGetStorageHistory_empty` | Returns empty list when no snapshots exist |
| `testGetStorageHistory_withData` | Returns correct percentage calculations for a seeded snapshot |

### OrgStorageServiceTest (6 methods)

| Test Method | What It Covers |
|-------------|----------------|
| `testCaptureSnapshot_success` | Callout returns 200; snapshot is created with correct MB values |
| `testCaptureSnapshot_idempotent` | Re-running same day upserts instead of inserting a duplicate |
| `testCaptureSnapshot_purgesOldRecords` | Records > 90 days old are deleted after capture |
| `testCaptureSnapshot_httpError` | `CalloutException` is thrown on non-200 HTTP response |
| `testCaptureJob` | `OrgStorageCaptureJob` Queueable creates a snapshot when enqueued |
| `testScheduler` | `OrgStorageScheduler.execute()` enqueues the job successfully |

Run both test classes (avoids unrelated org test failures):

```bash
sf project deploy start --target-org <your-org-alias> --source-dir force-app \
  --test-level RunSpecifiedTests \
  --tests AdminDashboardControllerTest \
  --tests OrgStorageServiceTest
```

## Add to a Page

1. In Salesforce, go to **Setup → App Builder**
2. Create a **New App Page** (or open an existing one)
3. Search for **"Admin Dashboard"** in the component list
4. Drag it onto the canvas
5. **Save → Activate**

The refresh interval (default: 30s) can be changed in the App Builder component properties panel.

## Known Limitations

- **No true "currently logged in" feed** — Salesforce does not expose active sessions without the Event Monitoring add-on (paid). "Active Editors" uses `LastModifiedDate` within the last hour as a proxy.
- **Admin access required** — `LoginHistory` and `SetupAuditTrail` are only queryable by users with admin privileges. The component handles this gracefully; those sections will show empty if accessed by a non-admin.
- **Data is polled, not streamed** — each refresh runs ~20 SOQL queries. The default 30-second interval keeps well within governor limits.

## Apex SOQL Notes (for future changes)

- `LoginHistory.Status` **cannot be used in a WHERE clause** — Salesforce marks it as non-filterable despite it being selectable.
- `LAST_N_HOURS:n` date literals **cannot be used in inline Apex SOQL** — the colon conflicts with Apex's bind variable syntax. Use a DateTime bind variable instead:
  ```apex
  DateTime cutoff = DateTime.now().addHours(-1);
  [SELECT Id FROM Account WHERE LastModifiedDate >= :cutoff]
  ```
- `User.Name` **cannot be traversed in GROUP BY queries on `LoginHistory`** — resolve user names in a separate query after collecting IDs.
