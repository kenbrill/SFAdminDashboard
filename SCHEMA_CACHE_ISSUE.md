# Salesforce Schema Cache Issue — KBRILL Dev Org

## Summary

Custom fields deployed via the Salesforce Metadata API (using `sf project deploy start`) have real metadata records and are visible in the Setup UI, but are **invisible to SOQL and the REST describe API**. The schema cache used by the query engine is not refreshing after field creation.

---

## What Was Deployed

### Object: `OrgStorageSnapshot__c`

Four Number fields deployed today (`2026-05-18`):

| API Name | Label | Type |
|---|---|---|
| `DataMBMax__c` | Data Storage Limit (MB) | Number(10,0) |
| `DataMBUsed__c` | Data Storage Used (MB) | Number(10,0) |
| `FileMBMax__c` | File Storage Limit (MB) | Number(10,0) |
| `FileMBUsed__c` | File Storage Used (MB) | Number(10,0) |

### Object: `StorageProbe__c` (fresh, no prior deploy history)

Two fields deployed as a diagnostic test:

| API Name | Label | Type |
|---|---|---|
| `TestMB__c` | Test MB | Number(10,0) |
| `TestText__c` | Test Text | Text(100) |

---

## What the Tooling API Shows (fields exist with real IDs)

```soql
SELECT Id, DeveloperName, ManageableState
FROM CustomField
WHERE DeveloperName LIKE 'DataMB%' OR DeveloperName LIKE 'FileMB%'
```

**Result:**
```
00Naj00004Jbbq1EAB  DataMBMax   unmanaged
00Naj00004Jbbq2EAB  DataMBUsed  unmanaged
00Naj00004Jbbq3EAB  FileMBMax   unmanaged
00Naj00004Jbbq4EAB  FileMBUsed  unmanaged
```

Same for `StorageProbe__c` fields — both have real Tooling API IDs.

---

## What Fails — SOQL

### OrgStorageSnapshot__c

```soql
SELECT Id, DataMBMax__c, DataMBUsed__c, FileMBMax__c, FileMBUsed__c
FROM OrgStorageSnapshot__c
LIMIT 1
```

**Error:**
```
No such column 'DataMBMax__c' on entity 'OrgStorageSnapshot__c'.
```

### StorageProbe__c (fresh object, no prior history)

```soql
SELECT Id, TestMB__c, TestText__c
FROM StorageProbe__c
LIMIT 1
```

**Error:**
```
No such column 'TestMB__c' on entity 'StorageProbe__c'.
```

---

## What Fails — REST Describe

```
GET /services/data/v62.0/sobjects/OrgStorageSnapshot__c/describe/
```

Returns only system fields + `SnapshotDate__c` + `SnapshotDateKey__c` (the two fields from the original deploy). None of the newly deployed Number fields appear.

```
GET /services/data/v62.0/sobjects/StorageProbe__c/describe/
```

Returns only 9 system fields (Id, OwnerId, IsDeleted, Name, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp). Neither `TestMB__c` nor `TestText__c` appears.

---

## What Fails — Apex Schema.describe

```apex
Map<String,Schema.SObjectField> f =
    Schema.getGlobalDescribe()
          .get('StorageProbe__c')
          .getDescribe()
          .fields.getMap();
System.debug('Fields: ' + f.keySet());
System.debug('Total: ' + f.size());
```

**Debug output:**
```
Fields: {createdbyid, createddate, id, isdeleted, lastmodifiedbyid,
         lastmodifieddate, name, ownerid, systemmodstamp}
Total: 9
```

---

## What Works — Setup UI

Navigating to **Setup > Object Manager > StorageProbe__c > Fields & Relationships** shows both `TestMB__c` and `TestText__c` listed correctly.

Similarly, `OrgStorageSnapshot__c` shows all four Number fields in the UI.

The fields ARE provisioned at the database level. This is confirmed by the Setup UI displaying them.

---

## Pattern

- Fields created in the **initial deploy** (weeks ago): `SnapshotDate__c`, `SnapshotDateKey__c` → **visible in SOQL and describe**
- Fields created in **any subsequent deploy**: all Number fields, Text fields, fields on fresh objects → **invisible in SOQL and describe**

This pattern affects every field type (Number, Text) and every object (both an object with prior zombie metadata history and a brand new `StorageProbe__c` with no prior issues).

---

## Hypothesis

The SOQL query compiler and REST describe API share a schema cache that was populated during the initial org setup. Subsequent Metadata API deployments update the metadata layer (Setup UI, Tooling API) but are **not invalidating this schema cache**.

This may be a known dev org issue or an infrastructure-level cache staleness problem specific to this org instance.

---

## What Has Been Tried

- Waited 30+ minutes after deploy — no change
- Tried with `Cache-Control: no-cache` headers on REST describe — blocked
- Retried from multiple API endpoints (REST, Tooling API SOQL, Apex anonymous)
- Renamed fields entirely (new API names) — same result
- Created a completely fresh object (`StorageProbe__c`) — same result

---

## Failing Apex Deploy (for context)

Because the Apex compiler performs field validation at compile time against the same stale schema cache, deploying `OrgStorageService.cls` (which references `DataMBMax__c` in a SOQL query) will fail with:

```
No such column 'DataMBMax__c' on entity 'OrgStorageSnapshot__c'
```

This blocks the full feature from being deployed until the schema cache refreshes.

---

## Resolution

The schema cache needs to refresh. Options:
1. **Wait** — the cache will eventually expire; unclear how long (has been stale 30+ min so far)
2. **Ask Salesforce support** to invalidate the schema cache for this org instance
3. **Fresh Developer Edition org** — sidesteps the issue entirely
