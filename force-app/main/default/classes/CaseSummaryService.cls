/**
 * SSR Recipe 08 — Case AI summary (OpenAI gpt-4o-mini) with rule-based fallback.
 */
public with sharing class CaseSummaryService {
    private static final String OPENAI_CHAT_URL = 'https://api.openai.com/v1/chat/completions';
    private static final String OPENAI_MODEL = 'gpt-4o-mini';
    private static final Integer MAX_EMAILS = 5;
    private static final Integer MAX_CHARS_PER_EMAIL = 500;

    public class SummaryResult {
        public Boolean success;
        public String summaryText;
        public String mode;
        public String errorMessage;

        public SummaryResult(Boolean success, String summaryText, String mode, String errorMessage) {
            this.success = success;
            this.summaryText = summaryText;
            this.mode = mode;
            this.errorMessage = errorMessage;
        }
    }

    @TestVisible
    private static String testOpenAiApiKeyOverride;
    @TestVisible
    private static String testOpenAiResponseOverride;
    @TestVisible
    private static Boolean forceNoOpenAiKeyInTest = false;

    public static SummaryResult summarizeCase(Case caseRecord, List<EmailMessage> emails) {
        if (caseRecord == null) {
            return new SummaryResult(false, null, null, 'Case is required.');
        }

        String apiKey = resolveOpenAiApiKey();
        if (String.isNotBlank(apiKey)) {
            try {
                String aiSummary = callOpenAi(apiKey, caseRecord, emails);
                if (String.isNotBlank(aiSummary)) {
                    return new SummaryResult(true, aiSummary, 'openai', null);
                }
            } catch (Exception ex) {
                // Fall through to rule-based summary.
            }
        }

        return new SummaryResult(true, buildRuleBasedSummary(caseRecord, emails), 'fallback', null);
    }

    public static String buildSlackMessage(Case caseRecord, SummaryResult summary) {
        String accountName = caseRecord.Account != null ? caseRecord.Account.Name : 'N/A';
        String header =
            '*✦ Résumé Case*' +
            '\n*Case #' +
            nullSafe(caseRecord.CaseNumber) +
            '* — ' +
            accountName;
        String body = summary != null && String.isNotBlank(summary.summaryText)
            ? summary.summaryText
            : 'Résumé indisponible.';
        String modeLabel = summary != null && summary.mode == 'openai' ? 'OpenAI' : 'Rule-based';
        return header + '\n\n' + body + '\n\n_Mode : ' + modeLabel + '_';
    }

    private static String callOpenAi(String apiKey, Case caseRecord, List<EmailMessage> emails) {
        if (Test.isRunningTest() && String.isNotBlank(testOpenAiResponseOverride)) {
            return testOpenAiResponseOverride;
        }

        Map<String, Object> body = new Map<String, Object>{
            'model' => OPENAI_MODEL,
            'temperature' => 0.2,
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'role' => 'system',
                    'content' => systemPrompt()
                },
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => userPrompt(caseRecord, emails)
                }
            }
        };

        HttpRequest request = new HttpRequest();
        request.setEndpoint(OPENAI_CHAT_URL);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + apiKey);
        request.setBody(JSON.serialize(body));
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response == null || response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            return null;
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> choices = (List<Object>) payload.get('choices');
        if (choices == null || choices.isEmpty()) {
            return null;
        }

        Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
        Map<String, Object> message = (Map<String, Object>) firstChoice.get('message');
        return message != null ? (String) message.get('content') : null;
    }

    private static String systemPrompt() {
        return
            'Tu es un assistant support client expert. ' +
            'Ton rôle est de résumer un case Salesforce de façon concise pour un agent de support. ' +
            'Réponds UNIQUEMENT avec ce format :\n' +
            '🔍 Problème : [1 phrase]\n' +
            '📋 Historique : [2-3 phrases max]\n' +
            '✅ Actions tentées : [liste courte]\n' +
            '🚨 Urgence : [Faible / Moyenne / Haute]\n' +
            '💡 Suggestion : [1 action recommandée]';
    }

    private static String userPrompt(Case caseRecord, List<EmailMessage> emails) {
        String accountName = caseRecord.Account != null ? caseRecord.Account.Name : 'N/A';
        return
            'Voici le case Salesforce à résumer :\n\n' +
            'Sujet : ' + nullSafe(caseRecord.Subject) + '\n' +
            'Priorité : ' + nullSafe(caseRecord.Priority) + '\n' +
            'Statut : ' + nullSafe(caseRecord.Status) + '\n' +
            'Client : ' + accountName + '\n\n' +
            'Historique des échanges :\n' +
            formatEmails(emails);
    }

    @TestVisible
    private static String buildRuleBasedSummary(Case caseRecord, List<EmailMessage> emails) {
        String urgency = mapPriorityToUrgency(caseRecord.Priority);
        String lastEmailSnippet = 'aucun email récent';
        if (emails != null && !emails.isEmpty()) {
            lastEmailSnippet = truncatePlainText(emails[0].TextBody, MAX_CHARS_PER_EMAIL);
            if (String.isBlank(lastEmailSnippet)) {
                lastEmailSnippet = truncatePlainText(emails[0].HtmlBody, MAX_CHARS_PER_EMAIL);
            }
            if (String.isBlank(lastEmailSnippet)) {
                lastEmailSnippet = nullSafe(emails[0].Subject);
            }
        }

        return
            '🔍 Problème : ' + nullSafe(caseRecord.Subject) + '\n' +
            '📋 Historique : Case ' + nullSafe(caseRecord.CaseNumber) +
            ' — statut ' + nullSafe(caseRecord.Status) +
            '. Dernier échange : ' + lastEmailSnippet + '\n' +
            '✅ Actions tentées : non détectées automatiquement (configurez OpenAI pour plus de détails)\n' +
            '🚨 Urgence : ' + urgency + '\n' +
            '💡 Suggestion : Relire le fil email et contacter le demandeur si besoin';
    }

    private static String formatEmails(List<EmailMessage> emails) {
        if (emails == null || emails.isEmpty()) {
            return '(aucun EmailMessage)';
        }

        List<String> lines = new List<String>();
        Integer count = 0;
        for (EmailMessage emailRecord : emails) {
            if (count >= MAX_EMAILS) {
                break;
            }
            String raw = String.isNotBlank(emailRecord.TextBody)
                ? emailRecord.TextBody
                : emailRecord.HtmlBody;
            lines.add(
                '- [' + nullSafe(emailRecord.Subject) + '] ' +
                truncatePlainText(raw, MAX_CHARS_PER_EMAIL)
            );
            count++;
        }
        return String.join(lines, '\n');
    }

    private static String truncatePlainText(String value, Integer maxChars) {
        if (String.isBlank(value)) {
            return '';
        }
        String plain = value.stripHtmlTags().trim().replaceAll('\\s+', ' ');
        if (plain.length() <= maxChars) {
            return plain;
        }
        return plain.substring(0, maxChars) + '…';
    }

    private static String mapPriorityToUrgency(String priority) {
        if (priority == 'Critical' || priority == 'High') {
            return 'Haute';
        }
        if (priority == 'Medium') {
            return 'Moyenne';
        }
        return 'Faible';
    }

    private static String resolveOpenAiApiKey() {
        if (Test.isRunningTest()) {
            if (forceNoOpenAiKeyInTest == true) {
                return null;
            }
            if (String.isNotBlank(testOpenAiApiKeyOverride)) {
                return testOpenAiApiKeyOverride;
            }
        }

        SSR_Slack_Settings__c settings = SSR_Slack_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.OpenAI_Api_Key__c)) {
            return null;
        }
        return settings.OpenAI_Api_Key__c.trim();
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? 'N/A' : value;
    }
}
