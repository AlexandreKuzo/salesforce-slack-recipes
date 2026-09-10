/**
 * Async scoring + routing + notification for SSR Recipe 10.
 * Writes Score__c / AI_Reasoning__c / Confidence__c / Scored_At__c, applies the routing
 * decision (owner, status, callback task, nurturing campaign) and notifies Slack or e-mail.
 * Every step is recorded to SSR_Log__c via SSRLogger.
 */
public class LeadQualificationQueueable implements Queueable, Database.AllowsCallouts {
    private static final String RECIPE_KEY = 'recipe_10';
    private final Id leadId;

    public LeadQualificationQueueable(Id leadId) {
        this.leadId = leadId;
    }

    public void execute(QueueableContext context) {
        if (leadId == null) {
            return;
        }

        SSRLogger log = new SSRLogger(RECIPE_KEY, leadId).setJobId(context.getJobId());
        try {
            List<Lead> leads = [
                SELECT Id, FirstName, LastName, Company, Title, Email, Industry, Country,
                       NumberOfEmployees, LeadSource, Status, IsConverted, OwnerId,
                       Owner.Email, Owner.Name, Score__c
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];
            if (leads.isEmpty() || leads[0].IsConverted) {
                log.warning('load', leads.isEmpty() ? 'Lead introuvable' : 'Lead déjà converti — ignoré');
                return;
            }

            Lead lead = leads[0];

            LeadScoringService.ScoreResult scoreRes = LeadScoringService.scoreLead(lead);
            if (scoreRes == null || !scoreRes.success) {
                log.error('scoring', scoreRes != null && String.isNotBlank(scoreRes.errorMessage)
                    ? scoreRes.errorMessage
                    : 'Scoring échoué');
                return;
            }
            log.success('scoring',
                'Score ' + scoreRes.score + ' — confiance ' + scoreRes.confidence, scoreRes.mode);

            LeadScoringService.RoutingResult routing = LeadScoringService.route(lead, scoreRes);
            log.success('routing', 'Tier ' + routing.tier);

            // Notify FIRST: every callout (the LLM call above, the Slack call here) must run
            // before any DML — once a Queueable has pending uncommitted work it can no longer
            // call out ("You have uncommitted work pending"). Same ordering as SSR Recipe 07.
            notify(lead, scoreRes, routing, log);

            Lead leadUpdate = new Lead(
                Id = lead.Id,
                Score__c = scoreRes.score,
                AI_Reasoning__c = scoreRes.reasoning,
                Confidence__c = scoreRes.confidence,
                Scored_At__c = System.now()
            );
            if (routing.newOwnerId != null) {
                leadUpdate.OwnerId = routing.newOwnerId;
            }
            if (String.isNotBlank(routing.newStatus)) {
                leadUpdate.Status = routing.newStatus;
            }
            if (String.isNotBlank(routing.disqualificationReason)) {
                leadUpdate.Disqualification_Reason__c = routing.disqualificationReason;
            }

            try {
                update leadUpdate;
                log.success('persist', 'Scoring écrit'
                    + (routing.newOwnerId != null ? ' + owner réassigné' : '')
                    + (String.isNotBlank(routing.newStatus) ? ' + statut ' + routing.newStatus : ''));
            } catch (DmlException ex) {
                // A bad Disqualified_Status__c value or an invalid owner would land here — retry
                // with only the AI fields so the score is never lost.
                update new Lead(
                    Id = lead.Id,
                    Score__c = scoreRes.score,
                    AI_Reasoning__c = scoreRes.reasoning,
                    Confidence__c = scoreRes.confidence,
                    Scored_At__c = System.now(),
                    Disqualification_Reason__c = routing.disqualificationReason
                );
                log.warning('persist', 'Update complet refusé (' + ex.getMessage()
                    + ') — champs de scoring seuls écrits');
            }

            if (routing.createCallbackTask) {
                insert new Task(
                    WhoId = lead.Id,
                    Subject = 'Rappeler sous 1h',
                    ActivityDate = Date.today(),
                    Priority = 'High',
                    OwnerId = routing.newOwnerId != null ? routing.newOwnerId : lead.OwnerId
                );
                log.success('task', 'Task « Rappeler sous 1h » créée');
            }

            if (routing.nurtureCampaignId != null) {
                try {
                    insert new CampaignMember(
                        LeadId = lead.Id,
                        CampaignId = routing.nurtureCampaignId,
                        Status = 'Sent'
                    );
                    log.success('nurture', 'Ajouté à la campagne ' + routing.nurtureCampaignId);
                } catch (Exception ex) {
                    // Campaign missing, member already exists, or status not in the member-status list.
                    log.warning('nurture', 'CampaignMember non créé : ' + ex.getMessage());
                }
            }
        } catch (Exception ex) {
            log.error('unhandled', ex.getMessage() + ' @ ' + ex.getStackTraceString());
            throw ex;
        } finally {
            log.flush();
        }
    }

    private void notify(
        Lead lead,
        LeadScoringService.ScoreResult scoreRes,
        LeadScoringService.RoutingResult routing,
        SSRLogger log
    ) {
        String message = SlackService.appendRecordLink(
            LeadScoringService.buildSlackMessage(lead, scoreRes, routing),
            lead.Id
        );

        SlackService.PostMessageResult posted;
        try {
            String channelId = SlackService.resolveChannelIdForRecipe(routing.slackRecipeKey);
            posted = SlackService.postMessage(channelId, message);
        } catch (Exception ex) {
            // No Slack channel configured for this recipe key.
            posted = null;
        }

        if (posted != null && posted.success) {
            log.success('notify', 'Slack posté (ts ' + posted.slackTs + ')');
            return;
        }

        // Channel unresolved or Slack rejected the post → native e-mail fallback.
        String reason = posted == null
            ? 'channel non résolu pour la clé ' + routing.slackRecipeKey
            : posted.errorMessage;
        LeadScoringService.sendEmailFallback(lead, message);
        log.warning('notify', 'Slack KO (' + reason + ') → e-mail à l\'owner');
    }
}
