@IsTest
private class OrgStorageServiceTest {

    private class LimitsApiMock implements HttpCalloutMock {
        private final Integer statusCode;
        LimitsApiMock(Integer code) { this.statusCode = code; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            if (statusCode == 200) {
                res.setBody('{"DataStorageMB":{"Max":5,"Remaining":4},"FileStorageMB":{"Max":20,"Remaining":16}}');
            }
            return res;
        }
    }

    @IsTest
    static void testCaptureSnapshot_success() {
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(200));
        Test.startTest();
        OrgStorageService.captureSnapshot();
        Test.stopTest();
        List<OrgStorageSnapshot__c> snaps = [
            SELECT DataMBMax__c, DataMBUsed__c, FileMBMax__c, FileMBUsed__c, SnapshotDate__c
            FROM OrgStorageSnapshot__c
        ];
        System.assertEquals(1, snaps.size());
        System.assertEquals(5,  snaps[0].DataMBMax__c);
        System.assertEquals(1,  snaps[0].DataMBUsed__c);
        System.assertEquals(20, snaps[0].FileMBMax__c);
        System.assertEquals(4,  snaps[0].FileMBUsed__c);
        System.assertEquals(Date.today(), snaps[0].SnapshotDate__c);
    }

    @IsTest
    static void testCaptureSnapshot_idempotent() {
        insert new OrgStorageSnapshot__c(
            SnapshotDateKey__c = String.valueOf(Date.today()),
            SnapshotDate__c    = Date.today(),
            DataMBMax__c       = 5,
            DataMBUsed__c      = 1,
            FileMBMax__c       = 20,
            FileMBUsed__c      = 4
        );
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(200));
        Test.startTest();
        OrgStorageService.captureSnapshot();
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM OrgStorageSnapshot__c]);
    }

    @IsTest
    static void testCaptureSnapshot_purgesOldRecords() {
        OrgStorageSnapshot__c old = new OrgStorageSnapshot__c(
            SnapshotDateKey__c = '2000-01-01',
            SnapshotDate__c    = Date.newInstance(2000, 1, 1)
        );
        insert old;
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(200));
        Test.startTest();
        OrgStorageService.captureSnapshot();
        Test.stopTest();
        List<OrgStorageSnapshot__c> remaining = [SELECT SnapshotDate__c FROM OrgStorageSnapshot__c ORDER BY SnapshotDate__c];
        System.assertEquals(1, remaining.size());
        System.assertEquals(Date.today(), remaining[0].SnapshotDate__c);
    }

    @IsTest
    static void testCaptureSnapshot_httpError() {
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(401));
        Test.startTest();
        try {
            OrgStorageService.captureSnapshot();
            System.assert(false, 'Expected CalloutException');
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('401'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testCaptureJob() {
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(200));
        Test.startTest();
        System.enqueueJob(new OrgStorageCaptureJob());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM OrgStorageSnapshot__c]);
    }

    @IsTest
    static void testScheduler() {
        Test.setMock(HttpCalloutMock.class, new LimitsApiMock(200));
        Test.startTest();
        new OrgStorageScheduler().execute(null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM OrgStorageSnapshot__c]);
    }
}
