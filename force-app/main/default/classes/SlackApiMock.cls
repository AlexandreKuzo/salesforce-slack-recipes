@IsTest
public class SlackApiMock implements HttpCalloutMock {
    private final Boolean success;
    private final String errorCode;

    public SlackApiMock(Boolean success) {
        this(success, 'channel_not_found');
    }

    public SlackApiMock(Boolean success, String errorCode) {
        this.success = success;
        this.errorCode = errorCode;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');

        String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';

        if (!success) {
            response.setBody('{"ok":false,"error":"' + errorCode + '"}');
        } else if (endpoint.contains('/users.lookupByEmail')) {
            response.setBody('{"ok":true,"user":{"id":"U_LOOKUP01"}}');
        } else {
            response.setBody('{"ok":true,"ts":"1234567890.123456"}');
        }

        return response;
    }
}
