@IsTest
public class CaseSummaryApiMock implements HttpCalloutMock {
    public Integer openAiStatus = 200;
    public String openAiBody =
        '{"choices":[{"message":{"content":"🔍 Problème : Test\\n📋 Historique : Mock IA\\n✅ Actions tentées : n/a\\n🚨 Urgence : Haute\\n💡 Suggestion : Tester"}}]}';
    public Boolean lookupFound = true;
    public Boolean slackOk = true;

    public CaseSummaryApiMock() {
    }

    /** Convenience: OpenAI returns an error status (→ rule-based fallback). */
    public static CaseSummaryApiMock openAiFailing() {
        CaseSummaryApiMock m = new CaseSummaryApiMock();
        m.openAiStatus = 500;
        m.openAiBody = '{"error":"server_error"}';
        return m;
    }

    /** Convenience: OpenAI returns 200 but no choices (→ rule-based fallback). */
    public static CaseSummaryApiMock openAiNoChoices() {
        CaseSummaryApiMock m = new CaseSummaryApiMock();
        m.openAiBody = '{"choices":[]}';
        return m;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse response = new HttpResponse();
        response.setHeader('Content-Type', 'application/json');
        String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';

        if (endpoint.contains('api.openai.com')) {
            response.setStatusCode(openAiStatus);
            response.setBody(openAiBody);
        } else if (endpoint.contains('/users.lookupByEmail')) {
            response.setStatusCode(200);
            response.setBody(
                lookupFound
                    ? '{"ok":true,"user":{"id":"U_CASE_OWNER"}}'
                    : '{"ok":false,"error":"users_not_found"}'
            );
        } else if (endpoint.contains('/chat.postMessage')) {
            response.setStatusCode(200);
            response.setBody(
                slackOk
                    ? '{"ok":true,"ts":"1234567890.123456"}'
                    : '{"ok":false,"error":"cannot_dm_bot"}'
            );
        } else {
            response.setStatusCode(200);
            response.setBody('{"ok":false,"error":"unknown_endpoint"}');
        }

        return response;
    }
}
