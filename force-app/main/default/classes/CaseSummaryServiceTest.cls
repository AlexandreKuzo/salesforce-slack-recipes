@IsTest(IsParallel=false)
private class CaseSummaryServiceTest {
    @IsTest
    static void summarizeCase_usesFallbackWithoutApiKey() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Account account = new Account(Name = 'SSR Case Account');
        insert account;

        Case caseRecord = new Case(
            Subject = 'Portail inaccessible',
            Description = 'Le client ne peut plus se connecter.',
            Priority = 'High',
            Status = 'Open',
            AccountId = account.Id
        );
        insert caseRecord;

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(
            [SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name FROM Case WHERE Id = :caseRecord.Id],
            new List<EmailMessage>()
        );

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.usedAi);
        System.assert(result.summary.contains('Portail inaccessible'));
        System.assert(result.summary.contains('Haute'));
    }

    @IsTest
    static void summarizeCase_usesOpenAiWhenConfigured() {
        CaseSummaryService.forceNoOpenAiKeyInTest = false;
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        CaseSummaryService.testOpenAiResponseOverride =
            '🔍 Problème : Test\n📋 Historique : Mock IA\n✅ Actions tentées : n/a\n🚨 Urgence : Haute\n💡 Suggestion : Tester';
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(Subject = 'Test IA', Priority = 'Medium', Status = 'Open');
        insert caseRecord;

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(
            [SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name FROM Case WHERE Id = :caseRecord.Id],
            new List<EmailMessage>()
        );

        System.assertEquals(true, result.success);
        System.assertEquals(true, result.usedAi);
        System.assert(result.summary.contains('Mock IA'));
    }

    @IsTest
    static void summarizeCase_requiresCase() {
        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(null, new List<EmailMessage>());
        System.assertEquals(false, result.success);
    }

    @IsTest
    static void summarizeCase_fallsBackWhenOpenAiFails() {
        CaseSummaryService.forceNoOpenAiKeyInTest = false;
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        CaseSummaryService.testOpenAiResponseOverride = null;
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(false, 'invalid_api_key'));

        Case caseRecord = new Case(Subject = 'Fallback path', Priority = 'Low', Status = 'Open');
        insert caseRecord;

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(
            [SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name FROM Case WHERE Id = :caseRecord.Id],
            new List<EmailMessage>()
        );

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.usedAi);
        System.assert(result.summary.contains('Fallback path'));
    }

    @IsTest
    static void invocable_queuesSummaryJob() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(Subject = 'Queue test', Priority = 'Low', Status = 'Open');
        insert caseRecord;

        CaseSummaryInvocable.Request req = new CaseSummaryInvocable.Request();
        req.caseId = caseRecord.Id;

        Test.startTest();
        List<CaseSummaryInvocable.Response> responses = CaseSummaryInvocable.summarizeToSlack(
            new List<CaseSummaryInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, responses[0].success);
        System.assertEquals(true, responses[0].queued);
    }

    @IsTest
    static void queueable_postsSummaryToSlack() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(
            Subject = 'Slack summary test',
            Description = 'Description test',
            Priority = 'High',
            Status = 'Open'
        );
        insert caseRecord;

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(caseRecord.Id));
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void buildUserPrompt_includesCaseFields() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(
            Subject = 'Sujet test',
            Priority = 'High',
            Status = 'Open',
            Description = 'Description test'
        );
        insert caseRecord;

        String prompt = CaseSummaryService.buildUserPrompt(
            [SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name FROM Case WHERE Id = :caseRecord.Id],
            new List<EmailMessage>()
        );

        System.assert(prompt.contains('Sujet test'));
        System.assert(prompt.contains('High'));
    }
}
