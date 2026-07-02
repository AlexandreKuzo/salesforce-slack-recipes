/**
 * Flow entry point for Salesforce Slack Recipes.
 */
public with sharing class SlackInvocable {
    public class Request {
        @InvocableVariable(label='Message' required=true)
        public String message;

        @InvocableVariable(
            label='Recipe Key'
            description='SSR recipe key (ex. recipe_01). Resolves the channel from Custom Metadata.'
        )
        public String recipeKey;

        @InvocableVariable(
            label='Channel Id'
            description='Slack channel ID (C...). Used when Recipe Key is empty.'
        )
        public String channelId;

        @InvocableVariable(
            label='Record Id'
            description='Optional Salesforce record Id — adds a clickable link to the Slack message.'
        )
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Slack Message Timestamp')
        public String slackTs;
    }

    @InvocableMethod(
        label='SSR Send Slack Message'
        description='Queues a Slack message via the SSR Bot API (sent asynchronously).'
        category='SSR Slack Recipes'
    )
    public static List<Response> sendMessage(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            responses.add(handleRequest(req));
        }

        return responses;
    }

    private static Response handleRequest(Request req) {
        Response res = new Response();
        res.success = false;

        if (req == null || String.isBlank(req.message)) {
            res.errorMessage = 'Message is required.';
            return res;
        }

        if (String.isBlank(req.recipeKey) && String.isBlank(req.channelId)) {
            res.errorMessage = 'Provide either Recipe Key or Channel Id.';
            return res;
        }

        try {
            Id recordId = String.isNotBlank(req.recordId) ? Id.valueOf(req.recordId) : null;
            System.enqueueJob(new SlackCalloutQueueable(req.recipeKey, req.channelId, req.message, recordId));
            res.success = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }

        return res;
    }
}
