@IsTest(IsParallel=false)
private class CaseSummaryServiceTest {
    private static Case newCase(String subject, String priority) {
        // Own the Case with the running user so CaseSummaryQueueable.ownerEmail() resolves it.
        Case c = new Case(
            Subject = subject, Priority = priority, Status = 'New', Origin = 'Phone',
            OwnerId = UserInfo.getUserId()
        );
        insert c;
        return [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, IsEscalated, Account.Name, OwnerId
            FROM Case WHERE Id = :c.Id
        ];
    }

    private static List<EmailMessage> emailsFor(Id caseId) {
        insert new List<EmailMessage>{
            new EmailMessage(
                ParentId = caseId, Incoming = true, Subject = 'Premier contact',
                TextBody = 'Bonjour,\n\n   le portail ne répond plus depuis   ce matin.\n\nMerci', Status = '0'
            ),
            new EmailMessage(
                ParentId = caseId, Incoming = false, Subject = 'RE: Premier contact',
                HtmlBody = '<p>Bonjour,</p><p>nous <b>investiguons</b>.</p>', Status = '3'
            )
        };
        return [
            SELECT Id, Subject, TextBody, HtmlBody, MessageDate
            FROM EmailMessage WHERE ParentId = :caseId ORDER BY CreatedDate
        ];
    }

    // ---------------------------------------------------------------- scoring / summary

    @IsTest
    static void summarizeCase_nullCaseReturnsError() {
        CaseSummaryService.SummaryResult r = CaseSummaryService.summarizeCase(null, null);
        System.assertEquals(false, r.success);
        System.assert(r.errorMessage.contains('Case is required'));
    }

    @IsTest
    static void summarizeCase_fallbackWithoutKey() {
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Case c = newCase('Accès portail impossible', 'High');

        CaseSummaryService.SummaryResult r = CaseSummaryService.summarizeCase(c, emailsFor(c.Id));

        System.assertEquals('fallback', r.mode);
        System.assert(r.summaryText.contains('🔍 Problème : Accès portail impossible'));
        System.assert(r.summaryText.contains('Haute'));            // High → Haute
        System.assert(r.summaryText.contains('portail ne répond')); // last e-mail snippet, whitespace-collapsed
    }

    @IsTest
    static void summarizeCase_openAiHttpPath() {
        CaseSummaryService.forceNoOpenAiKeyInTest = false;
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case c = newCase('Test IA', 'Medium');
        List<EmailMessage> emails = emailsFor(c.Id); // all DML before the callout

        Test.startTest();
        CaseSummaryService.SummaryResult r = CaseSummaryService.summarizeCase(c, emails);
        Test.stopTest();

        System.assertEquals('openai', r.mode);
        System.assert(r.summaryText.contains('Mock IA'));
    }

    @IsTest
    static void summarizeCase_openAiErrorFallsBack() {
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        Test.setMock(HttpCalloutMock.class, CaseSummaryApiMock.openAiFailing());

        Case c = newCase('Panne', 'High');

        Test.startTest();
        CaseSummaryService.SummaryResult r = CaseSummaryService.summarizeCase(c, new List<EmailMessage>());
        Test.stopTest();

        System.assertEquals('fallback', r.mode);
        System.assert(r.summaryText.contains('Haute'));
    }

    @IsTest
    static void buildRuleBasedSummary_mapsEveryPriority() {
        // In-memory cases — 'Critical' is not a standard Case.Priority value so it can't be inserted.
        System.assert(CaseSummaryService.buildRuleBasedSummary(new Case(Priority = 'Critical'), null).contains('Haute'));
        System.assert(CaseSummaryService.buildRuleBasedSummary(new Case(Priority = 'Medium'), null).contains('Moyenne'));
        System.assert(CaseSummaryService.buildRuleBasedSummary(new Case(Priority = 'Low'), null).contains('Faible'));
        System.assert(CaseSummaryService.buildRuleBasedSummary(new Case(), null).contains('Faible'));
    }

    @IsTest
    static void summarizeCase_openAiNoChoicesFallsBack() {
        CaseSummaryService.testOpenAiApiKeyOverride = 'sk-test';
        Test.setMock(HttpCalloutMock.class, CaseSummaryApiMock.openAiNoChoices());

        Case c = newCase('Question', 'Low');

        Test.startTest();
        CaseSummaryService.SummaryResult r = CaseSummaryService.summarizeCase(c, new List<EmailMessage>());
        Test.stopTest();

        System.assertEquals('fallback', r.mode);
        System.assert(r.summaryText.contains('Faible')); // Low → Faible
    }

    @IsTest
    static void buildRuleBasedSummary_priorityAndEmailVariants() {
        Case medium = newCase('Sujet Medium', 'Medium');
        System.assert(CaseSummaryService.buildRuleBasedSummary(medium, null).contains('Moyenne'));

        // HTML-only body → stripped; long body → truncated with an ellipsis.
        Case withHtml = newCase('HTML only', 'Low');
        EmailMessage html = new EmailMessage(
            ParentId = withHtml.Id, Subject = 'x',
            HtmlBody = '<div>' + 'a'.repeat(900) + '</div>', Status = '0'
        );
        insert html;
        String summary = CaseSummaryService.buildRuleBasedSummary(
            withHtml,
            [SELECT Id, Subject, TextBody, HtmlBody FROM EmailMessage WHERE Id = :html.Id]
        );
        System.assert(summary.contains('…'), 'long body should be truncated');
        System.assert(!summary.contains('<div>'), 'HTML tags should be stripped');
    }

    @IsTest
    static void buildSlackMessage_modeVariants() {
        Case c = newCase('Sujet', 'High');

        String openai = CaseSummaryService.buildSlackMessage(
            c, new CaseSummaryService.SummaryResult(true, 'corps', 'openai', null)
        );
        System.assert(openai.contains('OpenAI'));
        System.assert(openai.contains('corps'));

        String fallback = CaseSummaryService.buildSlackMessage(
            c, new CaseSummaryService.SummaryResult(true, 'corps', 'fallback', null)
        );
        System.assert(fallback.contains('Rule-based'));

        String missing = CaseSummaryService.buildSlackMessage(c, null);
        System.assert(missing.contains('Résumé indisponible'));
    }

    // ---------------------------------------------------------------- invocable

    @IsTest
    static void invocable_queuesSummaryJob() {
        Case c = newCase('Queue test', 'Low');

        CaseSummaryInvocable.Request req = new CaseSummaryInvocable.Request();
        req.caseId = c.Id;

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
    static void invocable_requiresCaseId() {
        List<CaseSummaryInvocable.Response> responses = CaseSummaryInvocable.summarizeCaseToSlack(
            new List<CaseSummaryInvocable.Request>{ new CaseSummaryInvocable.Request() }
        );
        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('Case Id'));
    }

    // ---------------------------------------------------------------- queueable

    @IsTest
    static void queueable_dmsOwnerAndLogs() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new CaseSummaryApiMock());

        Case c = newCase('DM owner test', 'High');

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(c.Id));
        Test.stopTest();

        Map<String, String> byStep = new Map<String, String>();
        List<String> dump = new List<String>();
        for (SSR_Log__c l : [SELECT Step__c, Status__c, Message__c FROM SSR_Log__c WHERE Recipe_Key__c = 'recipe_08']) {
            byStep.put(l.Step__c, l.Status__c);
            dump.add(l.Step__c + '=' + l.Status__c + ':' + l.Message__c);
        }
        System.assertEquals('Success', byStep.get('summary'), String.join(dump, ' | '));
        System.assertEquals('Success', byStep.get('notify'), String.join(dump, ' | '));
    }

    @IsTest
    static void queueable_logsWhenOwnerNotOnSlack() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        CaseSummaryApiMock mock = new CaseSummaryApiMock();
        mock.lookupFound = false;
        Test.setMock(HttpCalloutMock.class, mock);

        Case c = newCase('No Slack owner', 'Medium');

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(c.Id));
        Test.stopTest();

        SSR_Log__c lookup = [
            SELECT Status__c FROM SSR_Log__c
            WHERE Recipe_Key__c = 'recipe_08' AND Step__c = 'lookup' LIMIT 1
        ];
        System.assertEquals('Warning', lookup.Status__c);
    }

    @IsTest
    static void queueable_logsWhenDmRejected() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        CaseSummaryService.forceNoOpenAiKeyInTest = true;
        CaseSummaryApiMock mock = new CaseSummaryApiMock();
        mock.slackOk = false;
        Test.setMock(HttpCalloutMock.class, mock);

        Case c = newCase('DM rejected', 'High');

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(c.Id));
        Test.stopTest();

        SSR_Log__c notify = [
            SELECT Status__c, Message__c FROM SSR_Log__c
            WHERE Recipe_Key__c = 'recipe_08' AND Step__c = 'notify' LIMIT 1
        ];
        System.assertEquals('Error', notify.Status__c);
        System.assert(notify.Message__c.contains('cannot_dm_bot'));
    }

    @IsTest
    static void queueable_ignoresMissingCase() {
        Case c = newCase('temp', 'Low');
        Id ghost = c.Id;
        delete c;

        Test.startTest();
        System.enqueueJob(new CaseSummaryQueueable(ghost));
        Test.stopTest();

        System.assertEquals('Warning',
            [SELECT Status__c FROM SSR_Log__c WHERE Step__c = 'load' LIMIT 1].Status__c);
    }
}
