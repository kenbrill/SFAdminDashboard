public with sharing class AdminDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer activeUsersCount;
        @AuraEnabled public Integer loginsToday;
        @AuraEnabled public Integer activeEditorsCount;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer adminChangesToday;
        @AuraEnabled public List<ObjectStat> objectCounts;
        @AuraEnabled public List<ObjectStat> todayModified;
        @AuraEnabled public List<HourlyLogin> loginTrend;
        @AuraEnabled public List<AuditEntry> recentAuditTrail;
        @AuraEnabled public List<UserActivity> topActiveUsers;
    }

    public class ObjectStat {
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer count;
    }

    public class HourlyLogin {
        @AuraEnabled public Integer hour;
        @AuraEnabled public Integer count;
    }

    public class AuditEntry {
        @AuraEnabled public String action;
        @AuraEnabled public String section;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String createdDate;
    }

    public class UserActivity {
        @AuraEnabled public String userName;
        @AuraEnabled public Integer loginCount;
    }

    @AuraEnabled(cacheable=false)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();

        // ── KPIs ──────────────────────────────────────────────────────
        data.activeUsersCount = Database.countQuery(
            'SELECT COUNT() FROM User WHERE IsActive = true'
        );

        data.loginsToday = Database.countQuery(
            'SELECT COUNT() FROM LoginHistory WHERE LoginTime = TODAY'
        );

        // Users who modified records in the last hour (use bind var — LAST_N_HOURS:n is invalid in inline SOQL)
        DateTime oneHourAgo = DateTime.now().addHours(-1);
        Set<Id> editorIds = new Set<Id>();
        for (AggregateResult ar : [SELECT LastModifiedById FROM Account     WHERE LastModifiedDate >= :oneHourAgo GROUP BY LastModifiedById]) { editorIds.add((Id) ar.get('LastModifiedById')); }
        for (AggregateResult ar : [SELECT LastModifiedById FROM Contact     WHERE LastModifiedDate >= :oneHourAgo GROUP BY LastModifiedById]) { editorIds.add((Id) ar.get('LastModifiedById')); }
        for (AggregateResult ar : [SELECT LastModifiedById FROM Opportunity WHERE LastModifiedDate >= :oneHourAgo GROUP BY LastModifiedById]) { editorIds.add((Id) ar.get('LastModifiedById')); }
        for (AggregateResult ar : [SELECT LastModifiedById FROM Case        WHERE LastModifiedDate >= :oneHourAgo GROUP BY LastModifiedById]) { editorIds.add((Id) ar.get('LastModifiedById')); }
        for (AggregateResult ar : [SELECT LastModifiedById FROM Lead        WHERE LastModifiedDate >= :oneHourAgo GROUP BY LastModifiedById]) { editorIds.add((Id) ar.get('LastModifiedById')); }
        data.activeEditorsCount = editorIds.size();

        // ── Object record counts ──────────────────────────────────────
        Integer accCount  = Database.countQuery('SELECT COUNT() FROM Account');
        Integer conCount  = Database.countQuery('SELECT COUNT() FROM Contact');
        Integer leadCount = Database.countQuery('SELECT COUNT() FROM Lead');
        Integer oppCount  = Database.countQuery('SELECT COUNT() FROM Opportunity');
        Integer caseCount = Database.countQuery('SELECT COUNT() FROM Case');
        data.totalRecords = accCount + conCount + leadCount + oppCount + caseCount;

        data.objectCounts = new List<ObjectStat>{
            makeStat('Account',     accCount),
            makeStat('Contact',     conCount),
            makeStat('Lead',        leadCount),
            makeStat('Opportunity', oppCount),
            makeStat('Case',        caseCount)
        };

        // ── Modified today ────────────────────────────────────────────
        data.todayModified = new List<ObjectStat>{
            makeStat('Account',     Database.countQuery('SELECT COUNT() FROM Account     WHERE LastModifiedDate = TODAY')),
            makeStat('Contact',     Database.countQuery('SELECT COUNT() FROM Contact     WHERE LastModifiedDate = TODAY')),
            makeStat('Lead',        Database.countQuery('SELECT COUNT() FROM Lead        WHERE LastModifiedDate = TODAY')),
            makeStat('Opportunity', Database.countQuery('SELECT COUNT() FROM Opportunity WHERE LastModifiedDate = TODAY')),
            makeStat('Case',        Database.countQuery('SELECT COUNT() FROM Case        WHERE LastModifiedDate = TODAY'))
        };

        // ── Login trend by hour today ─────────────────────────────────
        data.loginTrend = new List<HourlyLogin>();
        for (AggregateResult ar : [
            SELECT HOUR_IN_DAY(LoginTime) hr, COUNT(Id) cnt
            FROM LoginHistory
            WHERE LoginTime = TODAY
            GROUP BY HOUR_IN_DAY(LoginTime)
            ORDER BY HOUR_IN_DAY(LoginTime)
        ]) {
            HourlyLogin hl = new HourlyLogin();
            hl.hour  = (Integer) ar.get('hr');
            hl.count = (Integer) ar.get('cnt');
            data.loginTrend.add(hl);
        }

        // ── Recent audit trail ────────────────────────────────────────
        data.recentAuditTrail = new List<AuditEntry>();
        try {
            for (SetupAuditTrail sat : [
                SELECT Action, Section, CreatedBy.Name, CreatedDate
                FROM SetupAuditTrail
                ORDER BY CreatedDate DESC
                LIMIT 15
            ]) {
                AuditEntry ae = new AuditEntry();
                ae.action        = sat.Action;
                ae.section       = sat.Section != null ? sat.Section : '—';
                ae.createdByName = sat.CreatedBy.Name;
                ae.createdDate   = sat.CreatedDate.format('yyyy-MM-dd HH:mm');
                data.recentAuditTrail.add(ae);
            }
            data.adminChangesToday = Database.countQuery(
                'SELECT COUNT() FROM SetupAuditTrail WHERE CreatedDate = TODAY'
            );
        } catch (Exception e) {
            data.adminChangesToday = 0;
        }

        // ── Top active users this week (two-step: ids+counts then names) ──
        data.topActiveUsers = new List<UserActivity>();
        try {
            DateTime weekStart = DateTime.now().addDays(-7);
            Map<Id, Integer> loginCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT UserId uid, COUNT(Id) cnt
                FROM LoginHistory
                WHERE LoginTime >= :weekStart
                GROUP BY UserId
                ORDER BY COUNT(Id) DESC
                LIMIT 8
            ]) {
                loginCounts.put((Id) ar.get('uid'), (Integer) ar.get('cnt'));
            }
            if (!loginCounts.isEmpty()) {
                Map<Id, String> userNames = new Map<Id, String>();
                for (User u : [SELECT Id, Name FROM User WHERE Id IN :loginCounts.keySet()]) {
                    userNames.put(u.Id, u.Name);
                }
                for (Id uid : loginCounts.keySet()) {
                    UserActivity ua = new UserActivity();
                    ua.userName   = userNames.containsKey(uid) ? userNames.get(uid) : String.valueOf(uid);
                    ua.loginCount = loginCounts.get(uid);
                    data.topActiveUsers.add(ua);
                }
                data.topActiveUsers.sort();
            }
        } catch (Exception e) {
            // LoginHistory may not be accessible
        }

        return data;
    }

    private static ObjectStat makeStat(String name, Integer count) {
        ObjectStat s = new ObjectStat();
        s.objectName = name;
        s.count      = count;
        return s;
    }
}
