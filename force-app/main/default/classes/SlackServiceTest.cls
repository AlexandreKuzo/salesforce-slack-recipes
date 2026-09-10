@IsTest(IsParallel=false)
private class SlackServiceTest {
    /** Feed resolveChannelIdForRecipe() from memory instead of the deployed CMDT. */
    private static void stubRecipes() {
        SlackService.testRecipesOverride = new Map<String, SSR_Slack_Recipe__mdt>{
            'recipe_01' => new SSR_Slack_Recipe__mdt(
                Recipe_Key__c = 'recipe_01', Channel_Id__c = 'C0123456789', Is_Active__c = true
            ),
            'recipe_02' => new SSR_Slack_Recipe__mdt(
                Recipe_Key__c = 'recipe_02', Channel_Id__c = 'C0123456789', Is_Active__c = true
            )
        };
    }

    @IsTest
    static void postMessage_success() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        SlackService.PostMessageResult result = SlackService.postMessage('C0123456789', 'Hello SSR');

        System.assertEquals(true, result.success);
        System.assertEquals('1234567890.123456', result.slackTs);
    }

    @IsTest
    static void postMessage_slackError() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(false, 'not_in_channel'));

        SlackService.PostMessageResult result = SlackService.postMessage('C0123456789', 'Hello SSR');

        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('not_in_channel'), result.errorMessage);
    }

    @IsTest
    static void postMessage_validatesInput() {
        SlackService.PostMessageResult missingChannel = SlackService.postMessage('', 'Hello');
        System.assertEquals(false, missingChannel.success);

        SlackService.PostMessageResult missingText = SlackService.postMessage('C123', '');
        System.assertEquals(false, missingText.success);
    }

    @IsTest
    static void postMessageForRecipe_usesCustomMetadata() {
        stubRecipes();
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        String channelId = SlackService.resolveChannelIdForRecipe('recipe_01');
        System.assertEquals('C0123456789', channelId);

        SlackService.PostMessageResult result = SlackService.postMessage(channelId, 'From recipe');

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void resolveChannelIdForRecipe_recipe02() {
        stubRecipes();
        System.assertEquals('C0123456789', SlackService.resolveChannelIdForRecipe('recipe_02'));
    }

    @IsTest
    static void resolveChannelIdForRecipe_unknownKey() {
        stubRecipes();
        Boolean thrown = false;
        try {
            SlackService.resolveChannelIdForRecipe('recipe_does_not_exist');
        } catch (SlackService.SlackException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('recipe_does_not_exist'));
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void lookupUserByEmail_resolvesAndDegrades() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';

        System.assertEquals(null, SlackService.lookupUserByEmail(null));
        System.assertEquals(null, SlackService.lookupUserByEmail('  '));

        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));
        System.assertEquals('U_LOOKUP01', SlackService.lookupUserByEmail('owner@example.com'));

        Test.setMock(HttpCalloutMock.class, new SlackApiMock(false, 'users_not_found'));
        System.assertEquals(null, SlackService.lookupUserByEmail('nobody@example.com'));
    }

    @IsTest
    static void parsePostMessageResponse_invalidJson() {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(500);
        response.setBody('not-json');

        SlackService.PostMessageResult result = SlackService.parsePostMessageResponse(response);

        System.assertEquals(false, result.success);
    }

    @IsTest
    static void appendRecordLink_addsSlackLink() {
        Account account = new Account(Name = 'SSR Test Account');
        insert account;

        String message = SlackService.appendRecordLink('Hello', account.Id);

        System.assert(message.contains('SSR Test Account') == false);
        System.assert(message.contains('Voir dans Salesforce'));
        System.assert(message.contains(account.Id));
    }

    @IsTest
    static void invocable_sendMessage_withChannelId() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        SlackInvocable.Request req = new SlackInvocable.Request();
        req.channelId = 'C0123456789';
        req.message = 'Invocable test';

        Test.startTest();
        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);
    }

    @IsTest
    static void invocable_sendMessage_withRecipeKey() {
        stubRecipes();
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        SlackInvocable.Request req = new SlackInvocable.Request();
        req.recipeKey = 'recipe_01';
        req.message = 'Recipe key test';

        Test.startTest();
        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, responses[0].success);
    }

    @IsTest
    static void calloutQueueable_logsSuccessAndFailure() {
        stubRecipes();
        SlackService.testBotTokenOverride = 'xoxb-test-token';

        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));
        Test.startTest();
        System.enqueueJob(new SlackCalloutQueueable('recipe_01', null, 'ok path', null));
        Test.stopTest();

        System.assertEquals('Success',
            [SELECT Status__c FROM SSR_Log__c WHERE Recipe_Key__c = 'recipe_01' AND Step__c = 'notify' LIMIT 1].Status__c);
    }

    @IsTest
    static void calloutQueueable_logsErrorOnSlackFailure() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(false, 'not_in_channel'));

        Test.startTest();
        System.enqueueJob(new SlackCalloutQueueable(null, 'C0123456789', 'error path', null));
        Test.stopTest();

        SSR_Log__c row = [SELECT Status__c, Message__c FROM SSR_Log__c WHERE Recipe_Key__c = 'slack_adhoc' LIMIT 1];
        System.assertEquals('Error', row.Status__c);
        System.assert(row.Message__c.contains('not_in_channel'));
    }

    @IsTest
    static void calloutQueueable_logsWhenNoTarget() {
        Test.startTest();
        System.enqueueJob(new SlackCalloutQueueable(null, null, 'no target', null));
        Test.stopTest();

        System.assertEquals('Error',
            [SELECT Status__c FROM SSR_Log__c WHERE Step__c = 'notify' LIMIT 1].Status__c);
    }

    @IsTest
    static void invocable_sendMessage_requiresTarget() {
        SlackInvocable.Request req = new SlackInvocable.Request();
        req.message = 'No target';

        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );

        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('Recipe Key'));
    }

    @IsTest
    static void resolveBotToken_requiresConfiguration() {
        SlackService.testBotTokenOverride = '';

        SlackService.PostMessageResult result = SlackService.postMessage('C123', 'hello');

        System.assertEquals(false, result.success);
        System.assert(result.errorMessage.contains('Bot Token'), result.errorMessage);
    }
}
