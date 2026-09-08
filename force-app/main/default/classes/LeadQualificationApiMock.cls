@IsTest
public class LeadQualificationApiMock implements HttpCalloutMock {
    private final Integer score;
    private final Boolean slackOk;

    public LeadQualificationApiMock() {
        this(82, true);
    }

    public LeadQualificationApiMock(Integer score) {
        this(score, true);
    }

    public LeadQualificationApiMock(Integer score, Boolean slackOk) {
        this.score = score;
        this.slackOk = slackOk;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');

        String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';

        if (endpoint.contains('api.openai.com')) {
            String content = JSON.serialize(new Map<String, Object>{
                'score' => score,
                'reasoning' => 'Fit ICP fort : secteur et effectif alignés.',
                'confidence' => 0.83
            });
            response.setBody(JSON.serialize(new Map<String, Object>{
                'choices' => new List<Object>{
                    new Map<String, Object>{
                        'message' => new Map<String, Object>{ 'content' => content }
                    }
                }
            }));
        } else if (endpoint.contains('/chat.postMessage')) {
            response.setBody(
                slackOk
                    ? '{"ok":true,"ts":"1234567890.123456"}'
                    : '{"ok":false,"error":"not_in_channel"}'
            );
        } else {
            response.setBody('{"ok":false,"error":"unknown_endpoint"}');
        }

        return response;
    }
}
