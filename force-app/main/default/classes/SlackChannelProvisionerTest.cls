@IsTest(IsParallel=false)
private class SlackChannelProvisionerTest {
    @IsTest
    static void buildDealChannelName_sanitizesAndAddsYear() {
        String name = SlackChannelService.buildDealChannelName('Acme Corp!');
        System.assert(name.startsWith('deal-acme-corp-'));
        System.assert(name.length() <= 80);
    }

    @IsTest
    static void createChannel_success() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackChannelApiMock());

        SlackChannelService.ChannelResult result = SlackChannelService.createChannel('deal-test-2026');

        System.assertEquals(true, result.success);
        System.assertEquals('C_RECIPE07', result.channelId);
    }

    @IsTest
    static void invocable_queuesProvisioner() {
        Account account = new Account(Name = 'SSR Channel Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'SSR Channel Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id
        );
        insert opp;

        SlackChannelInvocable.Request req = new SlackChannelInvocable.Request();
        req.opportunityId = opp.Id;

        Test.startTest();
        List<SlackChannelInvocable.Response> responses = SlackChannelInvocable.provisionChannel(
            new List<SlackChannelInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);
        System.assertEquals(true, responses[0].queued);
    }

    @IsTest
    static void queueable_provisionsChannelAndStoresId() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackChannelApiMock());

        Account account = new Account(Name = 'Acme Corp');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Big Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id,
            Amount = 50000
        );
        insert opp;

        Test.startTest();
        System.enqueueJob(new SlackChannelProvisionerQueueable(opp.Id, null));
        Test.stopTest();

        Opportunity updated = [
            SELECT SlackChannelId__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertEquals('C_RECIPE07', updated.SlackChannelId__c);
    }

    @IsTest
    static void queueable_skipsWhenChannelAlreadySet() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackChannelApiMock());

        Account account = new Account(Name = 'Existing Channel Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Existing Channel Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id,
            SlackChannelId__c = 'C_EXISTING'
        );
        insert opp;

        Test.startTest();
        System.enqueueJob(new SlackChannelProvisionerQueueable(opp.Id, null));
        Test.stopTest();

        System.assertEquals('C_EXISTING', [SELECT SlackChannelId__c FROM Opportunity WHERE Id = :opp.Id].SlackChannelId__c);
    }
}
