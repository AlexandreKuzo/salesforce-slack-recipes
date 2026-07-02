@IsTest
public class CaseSummaryApiMock implements HttpCalloutMock {
  public HTTPResponse respond(HTTPRequest req) {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(200);
    response.setHeader('Content-Type', 'application/json');

    String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';

    if (endpoint.contains('api.openai.com')) {
      response.setBody(
        '{"choices":[{"message":{"content":"🔍 Problème : Test\\n📋 Historique : Mock IA\\n✅ Actions tentées : n/a\\n🚨 Urgence : Haute\\n💡 Suggestion : Tester"}}]}'
      );
    } else if (endpoint.contains('slack.com')) {
      response.setBody('{"ok":true,"ts":"1234567890.123456"}');
    } else {
      response.setBody('{"ok":false,"error":"unknown_endpoint"}');
    }

    return response;
  }
}
