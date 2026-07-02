/**
 * Agentforce action — posts pipeline alerts to Slack via the SSR Stack.
 * Rich labels/descriptions help the agent choose when to invoke this action.
 */
public with sharing class AgentSlackNotifier {
    public class Request {
        @InvocableVariable(
            label='Alert Message'
            description='Full Slack alert text in French: situation, business risk, and recommended action. Use mrkdwn (*bold*).'
            required=true
        )
        public String message;

        @InvocableVariable(
            label='Recipe Key'
            description='SSR recipe key for the Slack channel. Always use recipe_09 for pipeline alerts unless instructed otherwise.'
        )
        public String recipeKey;

        @InvocableVariable(
            label='Record Id'
            description='Optional Salesforce record Id (Opportunity, Account, or Case) to append a clickable link.'
        )
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Queued')
        public Boolean queued;
    }

    @InvocableMethod(
        label='SSR Send Slack Notification'
        description='Posts a proactive alert to the team Slack channel when you detect a pipeline risk: stale opportunity (30+ days without activity), overdue deal in Negotiation, or account with 3+ open cases. Include business risk and a concrete recommended action in the message.'
        category='SSR Slack Recipes'
    )
    public static List<Response> notify(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            responses.add(handleRequest(req));
        }

        return responses;
    }

    private static Response handleRequest(Request req) {
        Response res = new Response();
        res.success = false;
        res.queued = false;

        if (req == null || String.isBlank(req.message)) {
            res.errorMessage = 'Alert Message is required.';
            return res;
        }

        String recipeKey = String.isNotBlank(req.recipeKey) ? req.recipeKey.trim() : 'recipe_09';
        Id recordId;

        try {
            recordId = String.isNotBlank(req.recordId) ? Id.valueOf(req.recordId.trim()) : null;
        } catch (Exception ex) {
            res.errorMessage = 'Invalid Record Id: ' + req.recordId;
            return res;
        }

        try {
            System.enqueueJob(new SlackCalloutQueueable(recipeKey, null, req.message, recordId));
            res.success = true;
            res.queued = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }

        return res;
    }
}
