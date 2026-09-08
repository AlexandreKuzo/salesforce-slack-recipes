/**
 * Flow entry point for SSR Recipe 10 — score a Lead, route it, and notify (async).
 */
public with sharing class LeadQualificationInvocable {
    public class Request {
        @InvocableVariable(label='Lead Id' required=true)
        public Id leadId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(
            label='Queued'
            description='True when scoring + routing + notification was queued (async).'
        )
        public Boolean queued;
    }

    @InvocableMethod(
        label='SSR Qualify Lead'
        description='Scores a Lead (OpenAI or fallback), routes it by threshold, and notifies Slack/email (async).'
        category='SSR Slack Recipes'
    )
    public static List<Response> qualifyLead(List<Request> requests) {
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

        if (req == null || req.leadId == null) {
            res.errorMessage = 'Lead Id is required.';
            return res;
        }

        try {
            System.enqueueJob(new LeadQualificationQueueable(req.leadId));
            res.success = true;
            res.queued = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }

        return res;
    }
}
