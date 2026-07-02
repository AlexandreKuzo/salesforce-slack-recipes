/**
 * Core HTTP client for Slack Web API (chat.postMessage).
 * Uses Named Credential SSR_Slack_API — Bot Token configured in Setup.
 */
public with sharing class SlackService {
    private static final String SLACK_API_BASE = 'https://slack.com/api';
    private static final String POST_MESSAGE_PATH = '/chat.postMessage';

    public class PostMessageResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String slackTs;

        public PostMessageResult(Boolean success, String errorMessage, String slackTs) {
            this.success = success;
            this.errorMessage = errorMessage;
            this.slackTs = slackTs;
        }
    }

    public class SlackException extends Exception {}

    @TestVisible
    private static String testBotTokenOverride;

    public static PostMessageResult postMessage(String channelId, String text) {
        if (String.isBlank(channelId)) {
            return new PostMessageResult(false, 'Channel Id is required.', null);
        }
        if (String.isBlank(text)) {
            return new PostMessageResult(false, 'Message text is required.', null);
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SLACK_API_BASE + POST_MESSAGE_PATH);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json; charset=utf-8');
        request.setBody(JSON.serialize(new Map<String, Object>{
            'channel' => channelId.trim(),
            'text' => text
        }));
        request.setTimeout(120000);

        try {
            request.setHeader('Authorization', 'Bearer ' + resolveBotToken());
            HttpResponse response = new Http().send(request);
            return parsePostMessageResponse(response);
        } catch (Exception ex) {
            return new PostMessageResult(false, ex.getMessage(), null);
        }
    }

    public static PostMessageResult postMessageForRecipe(String recipeKey, String text) {
        return postMessage(resolveChannelIdForRecipe(recipeKey), text);
    }

    public static String resolveChannelIdForRecipe(String recipeKey) {
        if (String.isBlank(recipeKey)) {
            throw new SlackException('Recipe Key is required.');
        }

        List<SSR_Slack_Recipe__mdt> recipes = [
            SELECT Channel_Id__c, Is_Active__c
            FROM SSR_Slack_Recipe__mdt
            WHERE Recipe_Key__c = :recipeKey.trim()
            LIMIT 1
        ];

        if (recipes.isEmpty()) {
            throw new SlackException('No SSR Slack Recipe found for key: ' + recipeKey);
        }
        if (!recipes[0].Is_Active__c) {
            throw new SlackException('SSR Slack Recipe is inactive: ' + recipeKey);
        }
        if (String.isBlank(recipes[0].Channel_Id__c)) {
            throw new SlackException('Channel Id is not configured for recipe: ' + recipeKey);
        }

        return recipes[0].Channel_Id__c;
    }

    public static String appendRecordLink(String message, Id recordId) {
        if (String.isBlank(message) || recordId == null) {
            return message;
        }

        String url = URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
        return message + '\n<' + url + '|Voir dans Salesforce>';
    }

    @TestVisible
    private static String resolveBotToken() {
        if (Test.isRunningTest() && String.isNotBlank(testBotTokenOverride)) {
            return testBotTokenOverride;
        }

        SSR_Slack_Settings__c settings = SSR_Slack_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.Bot_Token__c)) {
            throw new SlackException(
                'SSR Slack Bot Token not configured. Setup → Custom Settings → SSR Slack Settings → Manage.'
            );
        }
        return settings.Bot_Token__c.trim();
    }

    @TestVisible
    public static HttpResponse sendSlackPost(String path, Map<String, Object> body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(SLACK_API_BASE + path);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json; charset=utf-8');
        request.setHeader('Authorization', 'Bearer ' + resolveBotToken());
        request.setBody(JSON.serialize(body != null ? body : new Map<String, Object>()));
        request.setTimeout(120000);
        return new Http().send(request);
    }

    @TestVisible
    public static HttpResponse sendSlackGet(String path) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(SLACK_API_BASE + path);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + resolveBotToken());
        request.setTimeout(120000);
        return new Http().send(request);
    }

    @TestVisible
    public static Map<String, Object> parseSlackJson(HttpResponse response) {
        if (response == null || String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }

    @TestVisible
    private static PostMessageResult parsePostMessageResponse(HttpResponse response) {
        if (response == null) {
            return new PostMessageResult(false, 'Empty HTTP response from Slack.', null);
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } catch (Exception ex) {
            return new PostMessageResult(
                false,
                'Invalid Slack response (HTTP ' + response.getStatusCode() + ').',
                null
            );
        }

        Boolean ok = payload != null && payload.containsKey('ok') && (Boolean) payload.get('ok');
        if (ok) {
            return new PostMessageResult(true, null, (String) payload.get('ts'));
        }

        String slackError = payload != null ? (String) payload.get('error') : null;
        String message = String.isNotBlank(slackError)
            ? 'Slack API error: ' + slackError
            : 'Slack API error (HTTP ' + response.getStatusCode() + ').';
        return new PostMessageResult(false, message, null);
    }
}
