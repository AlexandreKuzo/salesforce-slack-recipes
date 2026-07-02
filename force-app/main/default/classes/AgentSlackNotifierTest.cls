@IsTest(IsParallel=false)
private class AgentSlackNotifierTest {
    @IsTest
    static void notify_queuesSlackMessage() {
        SlackService.testBotTokenOverride = 'xoxb-test-token';
        Test.setMock(HttpCalloutMock.class, new SlackApiMock(true));

        AgentSlackNotifier.Request req = new AgentSlackNotifier.Request();
        req.message = '🤖 *Alerte pipeline*\nDeal à risque détecté.';
        req.recipeKey = 'recipe_09';

        Test.startTest();
        List<AgentSlackNotifier.Response> responses = AgentSlackNotifier.notify(
            new List<AgentSlackNotifier.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, responses[0].success);
        System.assertEquals(true, responses[0].queued);
    }

    @IsTest
    static void notify_defaultsRecipeKeyToRecipe09() {
        AgentSlackNotifier.Request req = new AgentSlackNotifier.Request();
        req.message = 'Test alert';

        Test.startTest();
        List<AgentSlackNotifier.Response> responses = AgentSlackNotifier.notify(
            new List<AgentSlackNotifier.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, responses[0].success);
    }

    @IsTest
    static void notify_requiresMessage() {
        List<AgentSlackNotifier.Response> responses = AgentSlackNotifier.notify(
            new List<AgentSlackNotifier.Request>{ new AgentSlackNotifier.Request() }
        );

        System.assertEquals(false, responses[0].success);
        System.assert(responses[0].errorMessage.contains('required'));
    }

    @IsTest
    static void kickoff_buildsPrompt() {
        List<PipelineMonitorKickoffInvocable.Response> responses =
            PipelineMonitorKickoffInvocable.buildKickoffPrompt(
                new List<PipelineMonitorKickoffInvocable.Request>{ new PipelineMonitorKickoffInvocable.Request() }
            );

        System.assertEquals(1, responses.size());
        System.assert(responses[0].agentPrompt.contains('SSR Send Slack Notification'));
        System.assert(responses[0].agentPrompt.contains('30 jours'));
    }
}
