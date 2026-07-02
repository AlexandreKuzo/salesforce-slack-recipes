/**
 * Flow entry point for SSR Recipe 08 — AI case summary to Slack.
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

        @InvocableVariable(label='Queued')
        public Boolean queued;
    }

    @InvocableMethod(
        label='SSR Summarize Case to Slack'
        description='Generates a case summary (OpenAI or fallback) and posts it to Slack asynchronously.'
        category='SSR Slack Recipes'
    )
    public static List<Response> summarizeToSlack(List<Request> requests) {
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
