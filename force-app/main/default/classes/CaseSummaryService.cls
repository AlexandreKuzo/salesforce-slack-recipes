/**
 * Builds case context and requests an AI summary (OpenAI) or rule-based fallback.
 */
public with sharing class CaseSummaryService {
    private static final String SYSTEM_PROMPT =
        'Tu es un assistant support client expert. Résume le case Salesforce de façon concise. ' +
        'Réponds UNIQUEMENT avec ce format :\n' +
        '🔍 Problème : [1 phrase]\n' +
        '📋 Historique : [2-3 phrases max]\n' +
        '✅ Actions tentées : [liste courte]\n' +
        '🚨 Urgence : [Faible / Moyenne / Haute]\n' +
        '💡 Suggestion : [1 action recommandée]';

    @TestVisible
    private static String testOpenAiApiKeyOverride;
    @TestVisible
    private static String testOpenAiResponseOverride;
    @TestVisible
    private static Boolean forceNoOpenAiKeyInTest = false;

    public class SummaryResult {
        public Boolean success;
        public String summary;
        public Boolean usedAi;
        public String errorMessage;

        public SummaryResult(Boolean success, String summary, Boolean usedAi, String errorMessage) {
            this.success = success;
            this.summary = summary;
            this.usedAi = usedAi;
            this.errorMessage = errorMessage;
        }
    }

    public static SummaryResult summarizeCase(Case caseRecord, List<EmailMessage> emails) {
        if (caseRecord == null) {
            return new SummaryResult(false, null, false, 'Case is required.');
        }

        String userPrompt = buildUserPrompt(caseRecord, emails);
        String apiKey = resolveOpenAiApiKey();

        if (String.isNotBlank(apiKey)) {
            SummaryResult aiResult = requestOpenAiSummary(apiKey, userPrompt);
            if (aiResult.success) {
                return aiResult;
            }
            SummaryResult fallback = buildFallbackSummary(caseRecord, emails);
            fallback.errorMessage = aiResult.errorMessage;
            return fallback;
        }

        return buildFallbackSummary(caseRecord, emails);
    }

    @TestVisible
    public static String buildUserPrompt(Case caseRecord, List<EmailMessage> emails) {
        String accountName = caseRecord.Account != null ? caseRecord.Account.Name : 'N/A';
        String description = stripAndTruncate(caseRecord.Description, 500);

        List<String> exchangeLines = new List<String>();
        if (emails != null) {
            for (EmailMessage email : emails) {
                String body = stripAndTruncate(email.TextBody, 500);
                if (String.isNotBlank(body)) {
                    exchangeLines.add('- ' + body);
                }
            }
        }

        String exchanges = exchangeLines.isEmpty()
            ? 'Aucun email enregistré.'
            : String.join(exchangeLines, '\n');

        return 'Voici le case Salesforce à résumer :\n\n'
            + 'Sujet : ' + nullSafe(caseRecord.Subject) + '\n'
            + 'Priorité : ' + nullSafe(caseRecord.Priority) + '\n'
            + 'Statut : ' + nullSafe(caseRecord.Status) + '\n'
            + 'Client : ' + accountName + '\n'
            + 'Description : ' + description + '\n\n'
            + 'Historique des échanges :\n'
            + exchanges;
    }

    @TestVisible
    private static SummaryResult buildFallbackSummary(Case caseRecord, List<EmailMessage> emails) {
        String urgency = mapPriorityToUrgency(caseRecord.Priority);
        String history = emails != null && !emails.isEmpty()
            ? stripAndTruncate(emails[0].TextBody, 200)
            : 'Aucun échange email disponible.';

        String summary =
            '🔍 Problème : ' + nullSafe(caseRecord.Subject) + '\n'
            + '📋 Historique : ' + history + '\n'
            + '✅ Actions tentées : Voir description et emails du case.\n'
            + '🚨 Urgence : ' + urgency + '\n'
            + '💡 Suggestion : Consulter le case dans Salesforce et contacter le client si besoin.';

        return new SummaryResult(true, summary, false, null);
    }

    @TestVisible
    private static SummaryResult requestOpenAiSummary(String apiKey, String userPrompt) {
        if (Test.isRunningTest() && String.isNotBlank(testOpenAiResponseOverride)) {
            return new SummaryResult(true, testOpenAiResponseOverride, true, null);
        }

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://api.openai.com/v1/chat/completions');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Authorization', 'Bearer ' + apiKey);
            request.setTimeout(120000);
            request.setBody(JSON.serialize(new Map<String, Object>{
                'model' => 'gpt-4o-mini',
                'max_tokens' => 400,
                'messages' => new List<Object>{
                    new Map<String, Object>{ 'role' => 'system', 'content' => SYSTEM_PROMPT },
                    new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt }
                }
            }));

            HttpResponse response = new Http().send(request);
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Boolean ok = response.getStatusCode() >= 200
                && response.getStatusCode() < 300
                && payload != null
                && payload.containsKey('choices');

            if (!ok) {
                String error = payload != null ? (String) payload.get('error') : response.getBody();
                return new SummaryResult(false, null, true, 'OpenAI error: ' + error);
            }

            List<Object> choices = (List<Object>) payload.get('choices');
            if (choices == null || choices.isEmpty()) {
                return new SummaryResult(false, null, true, 'OpenAI returned no choices.');
            }

            Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
            Map<String, Object> message = (Map<String, Object>) firstChoice.get('message');
            String content = message != null ? (String) message.get('content') : null;

            if (String.isBlank(content)) {
                return new SummaryResult(false, null, true, 'OpenAI returned empty content.');
            }

            return new SummaryResult(true, content.trim(), true, null);
        } catch (Exception ex) {
            return new SummaryResult(false, null, true, ex.getMessage());
        }
    }

    private static String resolveOpenAiApiKey() {
        if (Test.isRunningTest()) {
            if (forceNoOpenAiKeyInTest) {
                return null;
            }
            if (testOpenAiApiKeyOverride != null) {
                return String.isBlank(testOpenAiApiKeyOverride) ? null : testOpenAiApiKeyOverride;
            }
        }

        SSR_Slack_Settings__c settings = SSR_Slack_Settings__c.getOrgDefaults();
        return settings != null ? settings.OpenAI_Api_Key__c : null;
    }

    private static String mapPriorityToUrgency(String priority) {
        if (priority == 'High') {
            return 'Haute';
        }
        if (priority == 'Medium') {
            return 'Moyenne';
        }
        return 'Faible';
    }

    private static String stripAndTruncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return 'Non renseigné';
        }
        String cleaned = value.stripHtmlTags().replaceAll('\\s+', ' ').trim();
        if (cleaned.length() > maxLength) {
            return cleaned.substring(0, maxLength) + '…';
        }
        return cleaned;
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? 'Non renseigné' : value;
    }
}
