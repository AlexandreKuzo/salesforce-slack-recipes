/**
 * SSR Recipe 10 — Lead qualification scoring (OpenAI gpt-4o-mini) with rule-based fallback,
 * threshold routing (HOT / NURTURE / DISQUALIFIED) and Slack-or-email notification text.
 */
public with sharing class LeadScoringService {
    private static final String OPENAI_CHAT_URL = 'https://api.openai.com/v1/chat/completions';
    private static final String OPENAI_MODEL = 'gpt-4o-mini';
    private static final Decimal FALLBACK_CONFIDENCE = 0.4;
    private static final Decimal DEFAULT_HIGH = 70;
    private static final Decimal DEFAULT_LOW = 40;

    public class ScoreResult {
        public Boolean success;
        public Decimal score;
        public String reasoning;
        public Decimal confidence;
        public String mode; // 'openai' | 'fallback'
        public String errorMessage;

        public ScoreResult(Boolean success, Decimal score, String reasoning, Decimal confidence, String mode, String errorMessage) {
            this.success = success;
            this.score = score;
            this.reasoning = reasoning;
            this.confidence = confidence;
            this.mode = mode;
            this.errorMessage = errorMessage;
        }
    }

    public class RoutingResult {
        public String tier; // 'HOT' | 'NURTURE' | 'DISQUALIFIED'
        public Id newOwnerId;
        public String newStatus;
        public String disqualificationReason;
        public Boolean createCallbackTask = false;
        public Id nurtureCampaignId;
        public String slackRecipeKey;
    }

    @TestVisible
    private static String testOpenAiApiKeyOverride;
    @TestVisible
    private static String testOpenAiResponseOverride;
    @TestVisible
    private static Boolean forceNoOpenAiKeyInTest = false;
    @TestVisible
    private static SSR_Lead_Scoring_Config__mdt testConfigOverride;

    // ---------------------------------------------------------------- scoring

    public static ScoreResult scoreLead(Lead lead) {
        if (lead == null) {
            return new ScoreResult(false, null, null, null, null, 'Lead is required.');
        }

        String apiKey = resolveOpenAiApiKey();
        if (String.isNotBlank(apiKey)) {
            try {
                ScoreResult ai = callOpenAi(apiKey, lead);
                if (ai != null && ai.success) {
                    return ai;
                }
            } catch (Exception ex) {
                // Fall through to rule-based scoring.
            }
        }

        return buildRuleBasedScore(lead);
    }

    private static ScoreResult callOpenAi(String apiKey, Lead lead) {
        String rawContent;
        if (Test.isRunningTest() && String.isNotBlank(testOpenAiResponseOverride)) {
            rawContent = testOpenAiResponseOverride;
        } else {
            Map<String, Object> body = new Map<String, Object>{
                'model' => OPENAI_MODEL,
                'temperature' => 0.2,
                'response_format' => new Map<String, Object>{ 'type' => 'json_object' },
                'messages' => new List<Object>{
                    new Map<String, Object>{ 'role' => 'system', 'content' => systemPrompt() },
                    new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt(lead) }
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
            rawContent = message != null ? (String) message.get('content') : null;
        }

        return parseAiContent(rawContent);
    }

    @TestVisible
    private static ScoreResult parseAiContent(String rawContent) {
        if (String.isBlank(rawContent)) {
            return null;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawContent);
            Decimal score = clampScore(toDecimal(parsed.get('score')));
            String reasoning = parsed.get('reasoning') != null ? String.valueOf(parsed.get('reasoning')) : null;
            Decimal confidence = clampConfidence(toDecimal(parsed.get('confidence')));
            if (score == null || String.isBlank(reasoning)) {
                return null;
            }
            return new ScoreResult(true, score, reasoning, confidence != null ? confidence : 0.5, 'openai', null);
        } catch (Exception ex) {
            return null;
        }
    }

    @TestVisible
    private static ScoreResult buildRuleBasedScore(Lead lead) {
        Decimal score = 30;
        List<String> notes = new List<String>();

        Map<String, Decimal> industryPoints = loadIndustryScores();
        if (String.isNotBlank(lead.Industry)) {
            Decimal pts = industryPoints.get(lead.Industry.toLowerCase());
            if (pts != null) {
                score += pts;
                notes.add('secteur ' + lead.Industry + ' (+' + pts.setScale(0) + ')');
            } else {
                notes.add('secteur ' + lead.Industry + ' hors liste ICP (+0)');
            }
        } else {
            notes.add('secteur non renseigné (+0)');
        }

        Integer employees = lead.NumberOfEmployees != null ? lead.NumberOfEmployees : 0;
        Decimal sizePts = employees >= 1000 ? 30 : employees >= 200 ? 20 : employees >= 50 ? 10 : 0;
        score += sizePts;
        notes.add('effectif ' + employees + ' (+' + sizePts.setScale(0) + ')');

        if (String.isNotBlank(lead.Email) && String.isNotBlank(lead.Title)) {
            score += 10;
            notes.add('contact décideur identifié (+10)');
        }

        score = clampScore(score);
        String reasoning = 'Scoring par règles (LLM indisponible). ' + String.join(notes, ', ') + '. Score = ' + score.setScale(0) + '/100.';
        return new ScoreResult(true, score, reasoning, FALLBACK_CONFIDENCE, 'fallback', null);
    }

    private static Map<String, Decimal> loadIndustryScores() {
        Map<String, Decimal> byIndustry = new Map<String, Decimal>();
        for (SSR_Lead_Industry_Score__mdt row : [
            SELECT Industry__c, Points__c FROM SSR_Lead_Industry_Score__mdt
        ]) {
            if (String.isNotBlank(row.Industry__c) && row.Points__c != null) {
                byIndustry.put(row.Industry__c.toLowerCase(), row.Points__c);
            }
        }
        return byIndustry;
    }

    // ---------------------------------------------------------------- routing

    public static RoutingResult route(Lead lead, ScoreResult scoreRes) {
        SSR_Lead_Scoring_Config__mdt config = loadConfig();
        Decimal high = config.High_Threshold__c != null ? config.High_Threshold__c : DEFAULT_HIGH;
        Decimal low = config.Low_Threshold__c != null ? config.Low_Threshold__c : DEFAULT_LOW;

        RoutingResult r = new RoutingResult();
        r.slackRecipeKey = String.isNotBlank(config.Slack_Recipe_Key__c) ? config.Slack_Recipe_Key__c : 'recipe_10';

        Decimal score = scoreRes != null && scoreRes.score != null ? scoreRes.score : 0;

        if (score >= high) {
            r.tier = 'HOT';
            r.createCallbackTask = true;
            r.newOwnerId = safeId(config.Hot_Lead_Owner_Id__c);
        } else if (score >= low) {
            r.tier = 'NURTURE';
            r.nurtureCampaignId = safeId(config.Nurture_Campaign_Id__c);
        } else {
            r.tier = 'DISQUALIFIED';
            r.disqualificationReason = 'Score IA ' + score.setScale(0) + ' < seuil bas ' + low.setScale(0);
            if (String.isNotBlank(config.Disqualified_Status__c)) {
                r.newStatus = config.Disqualified_Status__c;
            }
        }
        return r;
    }

    @TestVisible
    private static SSR_Lead_Scoring_Config__mdt loadConfig() {
        if (Test.isRunningTest() && testConfigOverride != null) {
            return testConfigOverride;
        }
        SSR_Lead_Scoring_Config__mdt config = SSR_Lead_Scoring_Config__mdt.getInstance('default');
        if (config != null) {
            return config;
        }
        return new SSR_Lead_Scoring_Config__mdt(
            High_Threshold__c = DEFAULT_HIGH,
            Low_Threshold__c = DEFAULT_LOW,
            Slack_Recipe_Key__c = 'recipe_10'
        );
    }

    // ---------------------------------------------------------------- notification

    public static String buildSlackMessage(Lead lead, ScoreResult scoreRes, RoutingResult routing) {
        String tier = routing != null ? routing.tier : 'N/A';
        String emoji = tier == 'HOT' ? '🔥' : tier == 'NURTURE' ? '🌱' : '❄️';
        String contact = (nullSafe(lead.FirstName) + ' ' + nullSafe(lead.LastName)).trim();
        Decimal score = scoreRes != null && scoreRes.score != null ? scoreRes.score : 0;
        Decimal confidencePct = scoreRes != null && scoreRes.confidence != null
            ? (scoreRes.confidence * 100).setScale(0)
            : 0;
        String modeLabel = scoreRes != null && scoreRes.mode == 'openai' ? 'OpenAI' : 'Rule-based';

        return '*' + emoji + ' Lead qualifié — ' + tier + '*\n' +
            '*Société :* ' + nullSafe(lead.Company) + '\n' +
            '*Contact :* ' + contact + (String.isNotBlank(lead.Title) ? ' — ' + lead.Title : '') + '\n' +
            '*Score :* ' + score.setScale(0) + '/100  (confiance ' + confidencePct + '%, ' + modeLabel + ')\n\n' +
            (scoreRes != null && String.isNotBlank(scoreRes.reasoning) ? scoreRes.reasoning : 'Justification indisponible.');
    }

    public static void sendEmailFallback(Lead lead, String message) {
        try {
            if (lead == null || lead.Owner == null || String.isBlank(lead.Owner.Email)) {
                return;
            }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ lead.Owner.Email });
            mail.setSubject('[SSR] Lead qualifié : ' + nullSafe(lead.Company));
            mail.setPlainTextBody(message);
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception ex) {
            // Best-effort fallback — swallow.
        }
    }

    // ---------------------------------------------------------------- prompts

    private static String systemPrompt() {
        return 'Tu es un SDR expert en qualification de leads B2B. ' +
            'Tu notes un lead de 0 à 100 selon son adéquation avec l\'ICP fourni. ' +
            'Réponds UNIQUEMENT avec un objet JSON valide de la forme : ' +
            '{"score": <entier 0-100>, "reasoning": "<2-3 phrases en français>", "confidence": <nombre 0-1>}';
    }

    private static String userPrompt(Lead lead) {
        return 'ICP :\n' + nullSafe(icpDescription()) + '\n\n' +
            'Lead à qualifier :\n' +
            '- Société : ' + nullSafe(lead.Company) + '\n' +
            '- Secteur : ' + nullSafe(lead.Industry) + '\n' +
            '- Effectif : ' + (lead.NumberOfEmployees != null ? String.valueOf(lead.NumberOfEmployees) : 'N/A') + '\n' +
            '- Contact : ' + nullSafe(lead.FirstName) + ' ' + nullSafe(lead.LastName) + '\n' +
            '- Titre : ' + nullSafe(lead.Title) + '\n' +
            '- Email : ' + nullSafe(lead.Email) + '\n' +
            '- Pays : ' + nullSafe(lead.Country) + '\n' +
            '- Source : ' + nullSafe(lead.LeadSource);
    }

    private static String icpDescription() {
        SSR_Lead_Scoring_Config__mdt config = loadConfig();
        return config != null ? config.Icp_Description__c : null;
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

    // ---------------------------------------------------------------- helpers

    private static Id safeId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal clampScore(Decimal score) {
        if (score == null) {
            return null;
        }
        if (score < 0) {
            return 0;
        }
        if (score > 100) {
            return 100;
        }
        return score.setScale(0, System.RoundingMode.HALF_UP);
    }

    private static Decimal clampConfidence(Decimal confidence) {
        if (confidence == null) {
            return null;
        }
        if (confidence < 0) {
            return 0;
        }
        if (confidence > 1) {
            return 1;
        }
        return confidence.setScale(2, System.RoundingMode.HALF_UP);
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? '' : value;
    }
}
