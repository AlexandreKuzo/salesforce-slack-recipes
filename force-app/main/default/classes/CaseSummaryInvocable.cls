/**
 * Flow entry point for SSR Recipe 08 — summarize a Case and DM the owner on Slack.
 */
public with sharing class CaseSummaryInvocable {
    public class Request {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(
            label='Queued'
            description='True when summarize + Slack DM was queued (async).'
        )
        public Boolean queued;
    }

    @InvocableMethod(
        label='SSR Summarize Case to Slack'
        description='Builds an AI (or fallback) Case summary and DMs the Case owner on Slack (async).'
        category='SSR Slack Recipes'
    )
    public static List<Response> summarizeCaseToSlack(List<Request> requests) {
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

        if (req == null || req.caseId == null) {
            res.errorMessage = 'Case Id is required.';
            return res;
        }

        try {
            System.enqueueJob(new CaseSummaryQueueable(req.caseId));
            res.success = true;
            res.queued = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }

        return res;
    }
}
