@IsTest(IsParallel=false)
private class LeadScoringServiceTest {
    private static Lead newLead(String company, String industry, Integer employees, String title, String email) {
        return new Lead(
            FirstName = 'Marie',
            LastName = 'Dubois',
            Company = company,
            Industry = industry,
            NumberOfEmployees = employees,
            Title = title,
            Email = email,
            // Pre-set so the (possibly active) SSR Recipe 10 flow — entry condition
            // ISBLANK(Score__c) — does not also enqueue a job. Tests drive the Queueable
            // explicitly; the Queueable overwrites this with the real score.
            Score__c = 0
        );
    }

    private static SSR_Lead_Scoring_Config__mdt config(Decimal high, Decimal low, String slackKey, String disqualifiedStatus) {
        return new SSR_Lead_Scoring_Config__mdt(
            High_Threshold__c = high,
            Low_Threshold__c = low,
            Slack_Recipe_Key__c = slackKey,
            Disqualified_Status__c = disqualifiedStatus
        );
    }

    @IsTest
    static void scoreLead_usesFallbackWithoutKey() {
        LeadScoringService.forceNoOpenAiKeyInTest = true;

        Lead lead = newLead('Acme SaaS', 'Technology', 500, 'CTO', 'cto@acme.example');
        insert lead;
        lead = [SELECT Id, Company, Industry, NumberOfEmployees, Title, Email FROM Lead WHERE Id = :lead.Id];

        LeadScoringService.ScoreResult result = LeadScoringService.scoreLead(lead);

        System.assertEquals(true, result.success);
        System.assertEquals('fallback', result.mode);
        // 30 base + 25 (Technology CMDT) + 20 (500 employees) + 10 (title+email) = 85
        System.assertEquals(85, result.score);
        System.assertEquals(0.4, result.confidence);
    }

    @IsTest
    static void scoreLead_fallbackClampsAndHandlesMissingData() {
        LeadScoringService.forceNoOpenAiKeyInTest = true;

        Lead lead = newLead('Tiny Co', null, null, null, null);
        insert lead;
        lead = [SELECT Id, Company, Industry, NumberOfEmployees, Title, Email FROM Lead WHERE Id = :lead.Id];

        LeadScoringService.ScoreResult result = LeadScoringService.scoreLead(lead);

        System.assertEquals('fallback', result.mode);
        System.assertEquals(30, result.score); // base only
    }

    @IsTest
    static void scoreLead_usesOpenAiWhenConfigured() {
        LeadScoringService.forceNoOpenAiKeyInTest = false;
        LeadScoringService.testOpenAiApiKeyOverride = 'sk-test';
        LeadScoringService.testOpenAiResponseOverride =
            '{"score": 91, "reasoning": "Compte stratégique, décideur identifié.", "confidence": 0.88}';

        Lead lead = newLead('BigBank', 'Banking', 5000, 'Head of Data', 'data@bigbank.example');
        insert lead;
        lead = [SELECT Id, Company, Industry, NumberOfEmployees, Title, Email, Country, LeadSource, FirstName, LastName FROM Lead WHERE Id = :lead.Id];

        LeadScoringService.ScoreResult result = LeadScoringService.scoreLead(lead);

        System.assertEquals('openai', result.mode);
        System.assertEquals(91, result.score);
        System.assertEquals(0.88, result.confidence);
        System.assert(result.reasoning.contains('stratégique'));
    }

    @IsTest
    static void scoreLead_invalidAiJsonFallsBack() {
        LeadScoringService.forceNoOpenAiKeyInTest = false;
        LeadScoringService.testOpenAiApiKeyOverride = 'sk-test';
        LeadScoringService.testOpenAiResponseOverride = 'désolé, je ne peux pas répondre en JSON';

        Lead lead = newLead('Acme SaaS', 'Technology', 300, 'VP Eng', 'vp@acme.example');
        insert lead;
        lead = [SELECT Id, Company, Industry, NumberOfEmployees, Title, Email FROM Lead WHERE Id = :lead.Id];

        LeadScoringService.ScoreResult result = LeadScoringService.scoreLead(lead);

        System.assertEquals('fallback', result.mode);
    }

    @IsTest
    static void parseAiContent_clampsOutOfRange() {
        LeadScoringService.ScoreResult over = LeadScoringService.parseAiContent(
            '{"score": 250, "reasoning": "x", "confidence": 5}'
        );
        System.assertEquals(100, over.score);
        System.assertEquals(1, over.confidence);

        LeadScoringService.ScoreResult under = LeadScoringService.parseAiContent(
            '{"score": -10, "reasoning": "x", "confidence": -1}'
        );
        System.assertEquals(0, under.score);
        System.assertEquals(0, under.confidence);
    }

    @IsTest
    static void route_hotNurtureDisqualified() {
        LeadScoringService.testConfigOverride = config(70, 40, 'recipe_10', null);
        Lead lead = newLead('Acme', 'Technology', 100, 'CTO', 'c@acme.example');

        LeadScoringService.RoutingResult hot = LeadScoringService.route(
            lead, new LeadScoringService.ScoreResult(true, 85, 'r', 0.9, 'openai', null)
        );
        System.assertEquals('HOT', hot.tier);
        System.assertEquals(true, hot.createCallbackTask);

        LeadScoringService.RoutingResult nurture = LeadScoringService.route(
            lead, new LeadScoringService.ScoreResult(true, 55, 'r', 0.9, 'openai', null)
        );
        System.assertEquals('NURTURE', nurture.tier);
        System.assertEquals(false, nurture.createCallbackTask);

        LeadScoringService.RoutingResult disq = LeadScoringService.route(
            lead, new LeadScoringService.ScoreResult(true, 20, 'r', 0.9, 'openai', null)
        );
        System.assertEquals('DISQUALIFIED', disq.tier);
        System.assert(disq.disqualificationReason.contains('20'));
        System.assertEquals(null, disq.newStatus); // status untouched when config value blank
    }

    @IsTest
    static void buildSlackMessage_includesKeyFacts() {
        Lead lead = newLead('Acme SaaS', 'Technology', 500, 'CTO', 'cto@acme.example');
        LeadScoringService.RoutingResult routing = new LeadScoringService.RoutingResult();
        routing.tier = 'HOT';

        String msg = LeadScoringService.buildSlackMessage(
            lead, new LeadScoringService.ScoreResult(true, 88, 'Bon fit ICP.', 0.8, 'openai', null), routing
        );

        System.assert(msg.contains('Acme SaaS'));
        System.assert(msg.contains('88/100'));
        System.assert(msg.contains('HOT'));
        System.assert(msg.contains('OpenAI'));
    }

    @IsTest
    static void invocable_queuesJob() {
        Lead lead = newLead('Queue Co', 'Technology', 60, 'CTO', 'c@queue.example');
        insert lead;

        LeadQualificationInvocable.Request req = new LeadQualificationInvocable.Request();
        req.leadId = lead.Id;

        Test.startTest();
        List<LeadQualificationInvocable.Response> responses = LeadQualificationInvocable.qualifyLead(
            new List<LeadQualificationInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);
        System.assertEquals(true, responses[0].queued);
    }

    @IsTest
    static void invocable_requiresLeadId() {
        List<LeadQualificationInvocable.Response> responses = LeadQualificationInvocable.qualifyLead(
            new List<LeadQualificationInvocable.Request>{ new LeadQualificationInvocable.Request() }
        );
        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('Lead Id'));
    }

    @IsTest
    static void queueable_scoresRoutesAndNotifiesSlack() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = config(70, 40, 'recipe_10', null);
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Lead lead = newLead('Acme SaaS', 'Technology', 500, 'CTO', 'cto@acme.example');
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        Lead scored = [SELECT Score__c, AI_Reasoning__c, Confidence__c, Scored_At__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(85, scored.Score__c);
        System.assertNotEquals(null, scored.Scored_At__c);
        System.assertNotEquals(null, scored.AI_Reasoning__c);

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :lead.Id AND Subject = 'Rappeler sous 1h']);
    }

    @IsTest
    static void queueable_disqualifiesLowScoreAndWritesReason() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = config(70, 40, 'recipe_10', null);
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Lead lead = newLead('Nobody Ltd', null, null, null, null);
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        Lead scored = [SELECT Score__c, Disqualification_Reason__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(30, scored.Score__c);
        System.assertNotEquals(null, scored.Disqualification_Reason__c);
    }

    @IsTest
    static void queueable_emailFallbackWhenNoSlackChannel() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = config(70, 40, 'recipe_absent', null);
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Lead lead = newLead('Fallback Co', 'Technology', 300, 'CTO', 'c@fallback.example');
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        // No exception through the e-mail fallback path = pass.
        System.assertNotEquals(null, [SELECT Score__c FROM Lead WHERE Id = :lead.Id].Score__c);
    }

    @IsTest
    static void scoreLead_openAiHttpPath() {
        LeadScoringService.forceNoOpenAiKeyInTest = false;
        LeadScoringService.testOpenAiApiKeyOverride = 'sk-test';
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock(76));

        Lead lead = newLead('HTTP Co', 'Technology', 900, 'CIO', 'cio@http.example');
        insert lead;
        lead = [
            SELECT Id, Company, Industry, NumberOfEmployees, Title, Email, Country, LeadSource, FirstName, LastName
            FROM Lead WHERE Id = :lead.Id
        ];

        Test.startTest();
        LeadScoringService.ScoreResult result = LeadScoringService.scoreLead(lead);
        Test.stopTest();

        System.assertEquals('openai', result.mode);
        System.assertEquals(76, result.score);
        System.assertEquals(0.83, result.confidence);
    }

    @IsTest
    static void parseAiContent_missingReasoningReturnsNull() {
        System.assertEquals(null, LeadScoringService.parseAiContent('{"score": 50}'));
        System.assertEquals(null, LeadScoringService.parseAiContent(''));
        System.assertEquals(null, LeadScoringService.parseAiContent('not json at all'));
    }

    @IsTest
    static void route_usesDeployedDefaultConfig() {
        LeadScoringService.testConfigOverride = null;
        Lead lead = newLead('Acme', 'Technology', 100, 'CTO', 'c@acme.example');

        LeadScoringService.RoutingResult hot = LeadScoringService.route(
            lead, new LeadScoringService.ScoreResult(true, 95, 'r', 0.9, 'openai', null)
        );
        System.assertEquals('HOT', hot.tier);
        System.assertEquals('recipe_10', hot.slackRecipeKey);
    }

    @IsTest
    static void buildSlackMessage_nurtureAndDisqualifiedVariants() {
        Lead lead = newLead('Acme SaaS', 'Technology', 60, null, null);

        LeadScoringService.RoutingResult nurture = new LeadScoringService.RoutingResult();
        nurture.tier = 'NURTURE';
        String nurtureMsg = LeadScoringService.buildSlackMessage(
            lead, new LeadScoringService.ScoreResult(true, 55, 'Mid fit.', 0.4, 'fallback', null), nurture
        );
        System.assert(nurtureMsg.contains('NURTURE'));
        System.assert(nurtureMsg.contains('Rule-based'));

        LeadScoringService.RoutingResult disq = new LeadScoringService.RoutingResult();
        disq.tier = 'DISQUALIFIED';
        String disqMsg = LeadScoringService.buildSlackMessage(
            lead, new LeadScoringService.ScoreResult(true, 12, 'Hors ICP.', 0.4, 'fallback', null), disq
        );
        System.assert(disqMsg.contains('DISQUALIFIED'));
    }

    @IsTest
    static void sendEmailFallback_handlesMissingOwnerEmail() {
        Lead lead = newLead('No Owner Email', 'Technology', 10, null, null);
        // lead.Owner is null on an in-memory record → method must no-op without error.
        LeadScoringService.sendEmailFallback(lead, 'message');
        LeadScoringService.sendEmailFallback(null, 'message');
    }

    @IsTest
    static void queueable_hotReassignsOwnerAndCreatesTask() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = new SSR_Lead_Scoring_Config__mdt(
            High_Threshold__c = 70,
            Low_Threshold__c = 40,
            Slack_Recipe_Key__c = 'recipe_10',
            Hot_Lead_Owner_Id__c = UserInfo.getUserId()
        );
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Lead lead = newLead('Acme SaaS', 'Technology', 500, 'CTO', 'cto@acme.example');
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        List<Task> tasks = [SELECT OwnerId FROM Task WHERE WhoId = :lead.Id];
        System.assertEquals(1, tasks.size());
        System.assertEquals(UserInfo.getUserId(), tasks[0].OwnerId);
    }

    @IsTest
    static void queueable_nurtureAddsCampaignMember() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Campaign campaign = new Campaign(Name = 'SSR Nurture', IsActive = true);
        insert campaign;

        LeadScoringService.testConfigOverride = new SSR_Lead_Scoring_Config__mdt(
            High_Threshold__c = 70,
            Low_Threshold__c = 40,
            Slack_Recipe_Key__c = 'recipe_10',
            Nurture_Campaign_Id__c = campaign.Id
        );

        // Finance (+20) + 60 employees (+10) + base 30 = 60 → NURTURE
        Lead lead = newLead('Midco', 'Finance', 60, null, null);
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :lead.Id AND CampaignId = :campaign.Id]);
    }

    @IsTest
    static void queueable_recoversFromBadDisqualifiedStatus() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = new SSR_Lead_Scoring_Config__mdt(
            High_Threshold__c = 70,
            Low_Threshold__c = 40,
            Slack_Recipe_Key__c = 'recipe_10',
            Disqualified_Status__c = 'This Status Does Not Exist 123'
        );
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock());

        Lead lead = newLead('Nobody Ltd', null, null, null, null);
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        Lead scored = [SELECT Score__c, Disqualification_Reason__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(30, scored.Score__c);
        System.assertNotEquals(null, scored.Disqualification_Reason__c);
    }

    @IsTest
    static void queueable_emailFallbackWhenSlackRejectsPost() {
        // Channel resolves but Slack rejects the post (bot not in channel) → e-mail fallback.
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        LeadScoringService.forceNoOpenAiKeyInTest = true;
        LeadScoringService.testConfigOverride = config(70, 40, 'recipe_10', null);
        Test.setMock(HttpCalloutMock.class, new LeadQualificationApiMock(82, false));

        Lead lead = newLead('Rejected Co', 'Technology', 300, 'CTO', 'c@rejected.example');
        insert lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(lead.Id));
        Test.stopTest();

        // Job completes, Lead still scored — the fallback path did not throw.
        System.assertEquals(85, [SELECT Score__c FROM Lead WHERE Id = :lead.Id].Score__c);
    }

    // NOTE: mocked callouts do NOT enforce the "uncommitted work pending" rule, so no unit
    // test can reproduce a callout-after-DML failure in LeadQualificationQueueable. The
    // callout-before-DML ordering there is verified against a real org.

    @IsTest
    static void queueable_ignoresMissingLead() {
        Lead lead = newLead('Temp', 'Technology', 10, null, null);
        insert lead;
        Id ghostId = lead.Id;
        delete lead;

        Test.startTest();
        System.enqueueJob(new LeadQualificationQueueable(ghostId));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Id = :ghostId]);
    }
}
