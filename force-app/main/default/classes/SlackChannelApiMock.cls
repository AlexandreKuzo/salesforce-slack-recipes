@IsTest
public class SlackChannelApiMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');

        String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';

        if (endpoint.contains('/conversations.create')) {
            response.setBody(
                '{"ok":true,"channel":{"id":"C_RECIPE07","name":"deal-test-2026"}}'
            );
        } else if (endpoint.contains('/users.lookupByEmail')) {
            response.setBody('{"ok":true,"user":{"id":"U_OWNER01"}}');
        } else if (endpoint.contains('/conversations.invite')) {
            response.setBody('{"ok":true}');
        } else if (endpoint.contains('/chat.postMessage')) {
            response.setBody('{"ok":true,"ts":"1234567890.123456"}');
        } else {
            response.setBody('{"ok":false,"error":"unknown_endpoint"}');
        }

        return response;
    }
}
