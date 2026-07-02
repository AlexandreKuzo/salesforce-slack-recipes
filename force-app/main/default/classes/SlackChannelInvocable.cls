/**
 * Flow entry point for SSR Recipe 07 — provision a Slack channel for a won deal.
 */
public with sharing class SlackChannelInvocable {
    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;

        @InvocableVariable(
            label='Welcome Message'
            description='Optional welcome text posted in the new channel.'
        )
        public String welcomeMessage;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(
            label='Queued'
            description='True when channel provisioning was queued (async).'
        )
        public Boolean queued;
    }

    @InvocableMethod(
        label='SSR Create Slack Channel'
        description='Creates a Slack channel for a Closed Won opportunity (async).'
        category='SSR Slack Recipes'
    )
    public static List<Response> provisionChannel(List<Request> requests) {
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

        if (req == null || req.opportunityId == null) {
            res.errorMessage = 'Opportunity Id is required.';
            return res;
        }

        try {
            System.enqueueJob(
                new SlackChannelProvisionerQueueable(req.opportunityId, req.welcomeMessage)
            );
            res.success = true;
            res.queued = true;
        } catch (Exception ex) {
            res.errorMessage = ex.getMessage();
        }

        return res;
    }
}
