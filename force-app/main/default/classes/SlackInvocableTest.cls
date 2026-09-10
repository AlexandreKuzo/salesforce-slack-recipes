@IsTest(IsParallel=false)
private class SlackInvocableTest {
    @IsTest
    static void sendMessage_withChannelId() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        SlackInvocable.Request req = new SlackInvocable.Request();
        req.channelId = 'C0123456789';
        req.message = 'Invocable test';

        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success, 'errorMessage: ' + responses[0].errorMessage);
    }

    @IsTest
    static void sendMessage_withRecipeKey() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        SlackInvocable.Request req = new SlackInvocable.Request();
        req.recipeKey = 'recipe_01';
        req.message = 'Recipe key test';

        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );

        System.assertEquals(true, responses[0].success, 'errorMessage: ' + responses[0].errorMessage);
    }

    @IsTest
    static void sendMessage_requiresTarget() {
        SlackInvocable.Request req = new SlackInvocable.Request();
        req.message = 'No target';

        List<SlackInvocable.Response> responses = SlackInvocable.sendMessage(
            new List<SlackInvocable.Request>{ req }
        );

        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('Recipe Key'));
    }
}
