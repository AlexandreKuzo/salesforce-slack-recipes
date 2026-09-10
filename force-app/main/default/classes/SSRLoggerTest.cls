@IsTest(IsParallel=false)
private class SSRLoggerTest {
    @IsTest
    static void buffersThenFlushesOneDml() {
        Account a = new Account(Name = 'SSR Logger Test');
        insert a;

        SSRLogger log = new SSRLogger('recipe_test', a.Id).setJobId(a.Id);
        log.success('scoring', 'Score 90', 'openai');
        log.warning('notify', 'Slack KO → e-mail');
        log.error('persist', 'DML refusé');

        System.assertEquals(3, log.pending());
        System.assertEquals(0, [SELECT COUNT() FROM SSR_Log__c]);

        Integer dmlBefore = Limits.getDmlStatements();
        log.flush();
        System.assertEquals(1, Limits.getDmlStatements() - dmlBefore, 'flush must be a single DML');

        List<SSR_Log__c> rows = [
            SELECT Recipe_Key__c, Status__c, Step__c, Message__c, Mode__c, Record_Id__c, Job_Id__c, Duration_Ms__c
            FROM SSR_Log__c ORDER BY Step__c
        ];
        System.assertEquals(3, rows.size());
        System.assertEquals(0, log.pending());

        Map<String, SSR_Log__c> byStep = new Map<String, SSR_Log__c>();
        for (SSR_Log__c r : rows) {
            byStep.put(r.Step__c, r);
            System.assertEquals('recipe_test', r.Recipe_Key__c);
            System.assertEquals(String.valueOf(a.Id), r.Record_Id__c);
            System.assertNotEquals(null, r.Duration_Ms__c);
        }
        System.assertEquals('Success', byStep.get('scoring').Status__c);
        System.assertEquals('openai', byStep.get('scoring').Mode__c);
        System.assertEquals('Warning', byStep.get('notify').Status__c);
        System.assertEquals('Error', byStep.get('persist').Status__c);
    }

    @IsTest
    static void flushWithNothingBufferedIsNoop() {
        SSRLogger log = new SSRLogger('recipe_test', null);
        Integer dmlBefore = Limits.getDmlStatements();
        log.flush();
        System.assertEquals(dmlBefore, Limits.getDmlStatements());
        System.assertEquals(0, [SELECT COUNT() FROM SSR_Log__c]);
    }

    @IsTest
    static void clipsOverlongValues() {
        SSRLogger log = new SSRLogger('x'.repeat(200), null);
        log.error('s'.repeat(200), 'm'.repeat(SSRLogger.MESSAGE_MAX + 500));
        log.flush();

        SSR_Log__c row = [SELECT Recipe_Key__c, Step__c, Message__c FROM SSR_Log__c LIMIT 1];
        System.assertEquals(40, row.Recipe_Key__c.length());
        System.assertEquals(80, row.Step__c.length());
        System.assertEquals(SSRLogger.MESSAGE_MAX, row.Message__c.length());
    }

    @IsTest
    static void nullAndBlankFieldsAreDropped() {
        SSRLogger log = new SSRLogger(null, null);
        log.success('step', null);
        log.flush();

        SSR_Log__c row = [SELECT Recipe_Key__c, Message__c, Mode__c FROM SSR_Log__c LIMIT 1];
        System.assertEquals(null, row.Recipe_Key__c);
        System.assertEquals(null, row.Message__c);
        System.assertEquals(null, row.Mode__c);
    }
}
