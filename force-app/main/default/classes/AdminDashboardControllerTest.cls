@IsTest
private class AdminDashboardControllerTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc.Id);
        insert con;

        Lead lead = new Lead(LastName = 'Test Lead', Company = 'Test Co');
        insert lead;

        Opportunity opp = new Opportunity(
            Name        = 'Test Opp',
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30),
            AccountId   = acc.Id
        );
        insert opp;

        Case cas = new Case(Subject = 'Test Case', AccountId = acc.Id);
        insert cas;
    }

    @IsTest
    static void testGetDashboardData_returnsData() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, data, 'getDashboardData() should not return null');
        System.assert(data.activeUsersCount   >= 0, 'activeUsersCount should be >= 0');
        System.assert(data.loginsToday        >= 0, 'loginsToday should be >= 0');
        System.assert(data.activeEditorsCount >= 0, 'activeEditorsCount should be >= 0');
        System.assert(data.totalRecords       >= 0, 'totalRecords should be >= 0');
        System.assert(data.adminChangesToday  >= 0, 'adminChangesToday should be >= 0');
    }

    @IsTest
    static void testGetDashboardData_objectCounts() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(5, data.objectCounts.size(), 'objectCounts should have 5 entries');
        Set<String> names = new Set<String>();
        for (AdminDashboardController.ObjectStat s : data.objectCounts) {
            System.assertNotEquals(null, s.objectName);
            System.assert(s.count >= 0);
            names.add(s.objectName);
        }
        System.assert(names.contains('Account'));
        System.assert(names.contains('Contact'));
        System.assert(names.contains('Lead'));
        System.assert(names.contains('Opportunity'));
        System.assert(names.contains('Case'));
    }

    @IsTest
    static void testGetDashboardData_todayModified() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(5, data.todayModified.size());
        Integer totalModified = 0;
        for (AdminDashboardController.ObjectStat s : data.todayModified) {
            totalModified += s.count;
        }
        System.assert(totalModified > 0, 'At least some records should be modified today');
    }

    @IsTest
    static void testGetDashboardData_totalRecordsMatchesSumOfCounts() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        Integer sum = 0;
        for (AdminDashboardController.ObjectStat s : data.objectCounts) {
            sum += s.count;
        }
        System.assertEquals(sum, data.totalRecords);
    }

    @IsTest
    static void testGetDashboardData_listsNonNull() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, data.objectCounts);
        System.assertNotEquals(null, data.todayModified);
        System.assertNotEquals(null, data.loginTrend);
        System.assertNotEquals(null, data.recentAuditTrail);
        System.assertNotEquals(null, data.topActiveUsers);
    }

    @IsTest
    static void testInnerClasses() {
        AdminDashboardController.ObjectStat os = new AdminDashboardController.ObjectStat();
        os.objectName = 'Account';
        os.count      = 5;
        System.assertEquals('Account', os.objectName);
        System.assertEquals(5,         os.count);

        AdminDashboardController.HourlyLogin hl = new AdminDashboardController.HourlyLogin();
        hl.hour  = 14;
        hl.count = 3;
        System.assertEquals(14, hl.hour);
        System.assertEquals(3,  hl.count);

        AdminDashboardController.AuditEntry ae = new AdminDashboardController.AuditEntry();
        ae.action        = 'changedApexClass';
        ae.section       = 'Apex Class';
        ae.createdByName = 'Test User';
        ae.createdDate   = '2026-05-17 10:00';
        System.assertEquals('changedApexClass', ae.action);

        AdminDashboardController.UserActivity ua = new AdminDashboardController.UserActivity();
        ua.userName   = 'Test User';
        ua.loginCount = 7;
        System.assertEquals(7, ua.loginCount);
    }

    @IsTest
    static void testGetStorageHistory_empty() {
        Test.startTest();
        List<AdminDashboardController.StorageSnapshot> result = AdminDashboardController.getStorageHistory();
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testGetStorageHistory_withData() {
        insert new OrgStorageSnapshot__c(
            SnapshotDateKey__c = '2026-01-15',
            SnapshotDate__c    = Date.newInstance(2026, 1, 15),
            DataMBMax__c       = 5,
            DataMBUsed__c      = 1,
            FileMBMax__c       = 20,
            FileMBUsed__c      = 4
        );
        Test.startTest();
        List<AdminDashboardController.StorageSnapshot> result = AdminDashboardController.getStorageHistory();
        Test.stopTest();
        System.assertEquals(1, result.size());
        System.assertEquals('2026-01-15', result[0].snapshotDate);
        System.assertEquals(20.0, result[0].dataPct);
        System.assertEquals(20.0, result[0].filePct);
    }
}
