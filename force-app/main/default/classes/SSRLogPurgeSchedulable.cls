/**
 * Deletes SSR_Log__c rows older than SSR_Slack_Settings__c.Log_Retention_Days__c (default 30).
 * Schedule once after deploy, e.g. daily:
 *   System.schedule('SSR Log purge', '0 30 2 * * ?', new SSRLogPurgeSchedulable());
 */
public with sharing class SSRLogPurgeSchedulable implements Schedulable {
    private static final Integer DEFAULT_RETENTION_DAYS = 30;
    @TestVisible
    private static final Integer DELETE_LIMIT = 10000;

    public void execute(SchedulableContext context) {
        purge();
    }

    @TestVisible
    private static Integer purge() {
        Integer days = retentionDays();
        Datetime cutoff = System.now().addDays(-days);

        List<SSR_Log__c> stale = [
            SELECT Id
            FROM SSR_Log__c
            WHERE CreatedDate < :cutoff
            ORDER BY CreatedDate ASC
            LIMIT :DELETE_LIMIT
        ];
        if (!stale.isEmpty()) {
            delete stale;
        }
        return stale.size();
    }

    @TestVisible
    private static Integer retentionDays() {
        SSR_Slack_Settings__c settings = SSR_Slack_Settings__c.getOrgDefaults();
        if (settings != null && settings.Log_Retention_Days__c != null && settings.Log_Retention_Days__c > 0) {
            return (Integer) settings.Log_Retention_Days__c;
        }
        return DEFAULT_RETENTION_DAYS;
    }
}
