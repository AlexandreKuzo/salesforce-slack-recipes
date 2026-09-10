@IsTest(IsParallel=false)
private class SSRLogPurgeSchedulableTest {
    @IsTest
    static void purgesRowsOlderThanRetention() {
        insert new SSR_Slack_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Log_Retention_Days__c = 30);

        List<SSR_Log__c> logs = new List<SSR_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            logs.add(new SSR_Log__c(Recipe_Key__c = 'recipe_test', Status__c = 'Success', Step__c = 'old'));
        }
        for (Integer i = 0; i < 3; i++) {
            logs.add(new SSR_Log__c(Recipe_Key__c = 'recipe_test', Status__c = 'Success', Step__c = 'recent'));
        }
        insert logs;

        // Backdate the "old" rows past the retention window.
        for (SSR_Log__c l : [SELECT Id FROM SSR_Log__c WHERE Step__c = 'old']) {
            Test.setCreatedDate(l.Id, System.now().addDays(-45));
        }

        Test.startTest();
        new SSRLogPurgeSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM SSR_Log__c WHERE Step__c = 'old']);
        System.assertEquals(3, [SELECT COUNT() FROM SSR_Log__c WHERE Step__c = 'recent']);
    }

    @IsTest
    static void defaultRetentionWhenSettingBlank() {
        System.assertEquals(30, SSRLogPurgeSchedulable.retentionDays());

        SSR_Log__c fresh = new SSR_Log__c(Recipe_Key__c = 'recipe_test', Status__c = 'Success', Step__c = 's');
        insert fresh;
        Test.setCreatedDate(fresh.Id, System.now().addDays(-31));

        System.assertEquals(1, SSRLogPurgeSchedulable.purge());
        System.assertEquals(0, [SELECT COUNT() FROM SSR_Log__c]);
    }

    @IsTest
    static void schedulable_canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'SSR Log purge test', '0 0 3 * * ?', new SSRLogPurgeSchedulable()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
