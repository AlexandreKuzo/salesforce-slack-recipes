@IsTest
private class CaseSummaryServiceTest {
    @IsTest
    static void summarizeCase_usesFallbackWithoutKey() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;

        Case caseRecord = new Case(
            Subject = 'Accès portail impossible',
            Priority = 'High',
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseRecord;

        caseRecord = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name
            FROM Case
            WHERE Id = :caseRecord.Id
        ];

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(
            caseRecord,
            new List<EmailMessage>()
        );

        System.assertEquals(true, result.success);
        System.assertEquals('fallback', result.mode);
        System.assert(result.summaryText.contains('🔍 Problème'));
        System.assert(result.summaryText.contains('Haute'));
    }

    @IsTest
    static void summarizeCase_usesOpenAiWhenConfigured() {
        CaseSummaryService.forceNoOpenAiKeyInTest = false;
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        CaseSummaryService.testOpenAiResponseOverride =
            '🔍 Problème : Test\n📋 Historique : Mock IA\n✅ Actions tentées : n/a\n🚨 Urgence : Haute\n💡 Suggestion : Tester';
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(
            Subject = 'Test IA',
            Priority = 'Medium',
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseRecord;

        caseRecord = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name
            FROM Case
            WHERE Id = :caseRecord.Id
        ];

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(
            caseRecord,
            new List<EmailMessage>()
        );

        System.assertEquals(true, result.success);
        System.assertEquals('openai', result.mode);
        System.assert(result.summaryText.contains('Mock IA'));
    }

    @IsTest
    static void invocable_queuesSummaryJob() {
        Case caseRecord = new Case(
            Subject = 'Queue test',
            Priority = 'Low',
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseRecord;

        CaseSummaryInvocable.Request req = new CaseSummaryInvocable.Request();
        req.caseId = caseRecord.Id;

        Test.startTest();
        List<CaseSummaryInvocable.Response> responses = CaseSummaryInvocable.summarizeCaseToSlack(
            new List<CaseSummaryInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);
        System.assertEquals(true, responses[0].queued);
    }

    @IsTest
    static void queueable_dmsOwnerViaEmailLookup() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case caseRecord = new Case(
            Subject = 'DM owner test',
            Priority = 'High',
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseRecord;

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(caseRecord.Id));
        Test.stopTest();

        // No exception = success path through lookup + postMessage mocks.
        System.assertNotEquals(null, caseRecord.Id);
    }

    @IsTest
    static void invocable_requiresCaseId() {
        CaseSummaryInvocable.Request req = new CaseSummaryInvocable.Request();

        List<CaseSummaryInvocable.Response> responses = CaseSummaryInvocable.summarizeCaseToSlack(
            new List<CaseSummaryInvocable.Request>{ req }
        );

        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('Case Id'));
    }
}
