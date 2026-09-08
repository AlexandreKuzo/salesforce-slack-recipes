/**
 * Async scoring + routing + notification for SSR Recipe 10.
 * Writes Score__c / AI_Reasoning__c / Confidence__c / Scored_At__c, applies the routing
 * decision (owner, status, callback task, nurturing campaign) and notifies Slack or e-mail.
 */
public class LeadQualificationQueueable implements Queueable, Database.AllowsCallouts {
    private final Id leadId;

    public LeadQualificationQueueable(Id leadId) {
        this.leadId = leadId;
    }

    public void execute(QueueableContext context) {
        if (leadId == null) {
            return;
        }

        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Company, Title, Email, Industry, Country,
                   NumberOfEmployees, LeadSource, Status, IsConverted, OwnerId,
                   Owner.Email, Owner.Name, Score__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty() || leads[0].IsConverted) {
            return;
        }

        Lead lead = leads[0];

        LeadScoringService.ScoreResult scoreRes = LeadScoringService.scoreLead(lead);
        if (scoreRes == null || !scoreRes.success) {
            return;
        }

        LeadScoringService.RoutingResult routing = LeadScoringService.route(lead, scoreRes);

        // Notify FIRST: every callout (the LLM call above, the Slack call here) must run
        // before any DML — once a Queueable has pending uncommitted work it can no longer
        // call out ("You have uncommitted work pending"). Same ordering as SSR Recipe 07.
        notify(lead, scoreRes, routing);

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
        }

        if (routing.createCallbackTask) {
            insert new Task(
                WhoId = lead.Id,
                Subject = 'Rappeler sous 1h',
                ActivityDate = Date.today(),
                Priority = 'High',
                OwnerId = routing.newOwnerId != null ? routing.newOwnerId : lead.OwnerId
            );
        }

        if (routing.nurtureCampaignId != null) {
            try {
                insert new CampaignMember(
                    LeadId = lead.Id,
                    CampaignId = routing.nurtureCampaignId,
                    Status = 'Sent'
                );
            } catch (Exception ex) {
                // Campaign missing, member already exists, or status not in the member-status
                // list — nurturing is best-effort.
            }
        }
    }

    private void notify(Lead lead, LeadScoringService.ScoreResult scoreRes, LeadScoringService.RoutingResult routing) {
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

        if (posted == null || !posted.success) {
            // Channel unresolved or Slack rejected the post → native e-mail fallback.
            LeadScoringService.sendEmailFallback(lead, message);
        }
    }
}
