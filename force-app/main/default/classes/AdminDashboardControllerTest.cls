@IsTest
private class AdminDashboardControllerTest {

    @TestSetup
    static void makeData() {
        // Create test records across the main objects so counts/modified queries return data
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

        // Returned object is non-null
        System.assertNotEquals(null, data, 'getDashboardData() should not return null');

        // Scalar KPIs are non-negative integers
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

        // objectCounts list has exactly 5 entries (Account/Contact/Lead/Opportunity/Case)
        System.assertEquals(5, data.objectCounts.size(), 'objectCounts should have 5 entries');

        Set<String> names = new Set<String>();
        for (AdminDashboardController.ObjectStat s : data.objectCounts) {
            System.assertNotEquals(null, s.objectName, 'objectName should not be null');
            System.assert(s.count >= 0, 'count should be >= 0 for ' + s.objectName);
            names.add(s.objectName);
        }
        System.assert(names.contains('Account'),     'objectCounts should include Account');
        System.assert(names.contains('Contact'),     'objectCounts should include Contact');
        System.assert(names.contains('Lead'),        'objectCounts should include Lead');
        System.assert(names.contains('Opportunity'), 'objectCounts should include Opportunity');
        System.assert(names.contains('Case'),        'objectCounts should include Case');
    }

    @IsTest
    static void testGetDashboardData_todayModified() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(5, data.todayModified.size(), 'todayModified should have 5 entries');

        // The records we just inserted were modified today, so totals should be > 0
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
        System.assertEquals(sum, data.totalRecords, 'totalRecords should equal sum of objectCounts');
    }

    @IsTest
    static void testGetDashboardData_listsNonNull() {
        Test.startTest();
        AdminDashboardController.DashboardData data = AdminDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, data.objectCounts,    'objectCounts should not be null');
        System.assertNotEquals(null, data.todayModified,   'todayModified should not be null');
        System.assertNotEquals(null, data.loginTrend,      'loginTrend should not be null');
        System.assertNotEquals(null, data.recentAuditTrail,'recentAuditTrail should not be null');
        System.assertNotEquals(null, data.topActiveUsers,  'topActiveUsers should not be null');
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
}
