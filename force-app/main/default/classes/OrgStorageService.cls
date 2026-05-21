public class OrgStorageService {
    public static void captureSnapshot() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v62.0/limits/');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException('Limits API returned HTTP ' + res.getStatusCode());
        }
        Map<String, Object> limits    = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> dataLimit = (Map<String, Object>) limits.get('DataStorageMB');
        Map<String, Object> fileLimit = (Map<String, Object>) limits.get('FileStorageMB');
        Long dataMax       = (Long) dataLimit.get('Max');
        Long dataRemaining = (Long) dataLimit.get('Remaining');
        Long fileMax       = (Long) fileLimit.get('Max');
        Long fileRemaining = (Long) fileLimit.get('Remaining');
        Date today = Date.today();
        OrgStorageSnapshot__c snap = new OrgStorageSnapshot__c(
            SnapshotDateKey__c = String.valueOf(today),
            SnapshotDate__c    = today,
            DataMBMax__c       = dataMax,
            DataMBUsed__c      = dataMax - dataRemaining,
            FileMBMax__c       = fileMax,
            FileMBUsed__c      = fileMax - fileRemaining
        );
        upsert snap SnapshotDateKey__c;
        Date cutoff = Date.today().addDays(-90);
        List<OrgStorageSnapshot__c> toDelete = [
            SELECT Id FROM OrgStorageSnapshot__c WHERE SnapshotDate__c < :cutoff
        ];
        if (!toDelete.isEmpty()) delete toDelete;
    }
}
