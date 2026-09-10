/**
 * Async channel provisioning (multiple Slack callouts) for SSR Recipe 07.
 * Every step is recorded to SSR_Log__c via SSRLogger.
 */
public class SlackChannelProvisionerQueueable implements Queueable, Database.AllowsCallouts {
    private static final String RECIPE_KEY = 'recipe_07';
    private final Id opportunityId;
    private final String welcomeMessage;

    public SlackChannelProvisionerQueueable(Id opportunityId, String welcomeMessage) {
        this.opportunityId = opportunityId;
        this.welcomeMessage = welcomeMessage;
    }

    public void execute(QueueableContext context) {
        SSRLogger log = new SSRLogger(RECIPE_KEY, opportunityId).setJobId(context.getJobId());
        try {
            List<Opportunity> opps = [
                SELECT Id, Name, Amount, SlackChannelId__c, Account.Name,
                       Owner.Name, Owner.Email, Owner.Manager.Email
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            if (opps.isEmpty()) {
                log.warning('load', 'Opportunity introuvable');
                return;
            }

            Opportunity opp = opps[0];
            if (String.isNotBlank(opp.SlackChannelId__c)) {
                log.warning('load', 'Channel déjà provisionné (' + opp.SlackChannelId__c + ') — ignoré');
                return;
            }

            String accountName = opp.Account != null ? opp.Account.Name : opp.Name;
            String channelName = SlackChannelService.buildDealChannelName(accountName);
            SlackChannelService.ChannelResult created = SlackChannelService.createChannel(channelName);

            if (!created.success || String.isBlank(created.channelId)) {
                log.error('channel', 'Création du channel « ' + channelName + ' » KO : ' + created.errorMessage);
                return;
            }
            log.success('channel', 'Channel « ' + channelName + ' » créé (' + created.channelId + ')');

            List<String> slackUserIds = new List<String>();
            String ownerSlackId = SlackService.lookupUserByEmail(opp.Owner != null ? opp.Owner.Email : null);
            if (String.isNotBlank(ownerSlackId)) {
                slackUserIds.add(ownerSlackId);
            }

            String managerEmail = opp.Owner != null && opp.Owner.Manager != null ? opp.Owner.Manager.Email : null;
            String managerSlackId = SlackService.lookupUserByEmail(managerEmail);
            if (String.isNotBlank(managerSlackId) && !slackUserIds.contains(managerSlackId)) {
                slackUserIds.add(managerSlackId);
            }

            Boolean invited = SlackChannelService.inviteUsers(created.channelId, slackUserIds);
            if (slackUserIds.isEmpty()) {
                log.warning('invite', 'Aucun utilisateur Slack résolu (owner/manager) — personne invité');
            } else {
                log.success('invite', slackUserIds.size() + ' utilisateur(s) '
                    + (invited ? 'invité(s)' : 'NON invités (Slack a refusé)'));
            }

            String message = String.isNotBlank(welcomeMessage)
                ? welcomeMessage
                : SlackChannelService.buildWelcomeMessage(opp);
            message = SlackService.appendRecordLink(message, opp.Id);
            SlackService.PostMessageResult posted = SlackService.postMessage(created.channelId, message);
            if (posted != null && posted.success) {
                log.success('notify', 'Message de bienvenue posté');
            } else {
                log.warning('notify', 'Message de bienvenue KO : '
                    + (posted != null ? posted.errorMessage : 'réponse vide'));
            }

            update new Opportunity(
                Id = opp.Id,
                SlackChannelId__c = created.channelId
            );
            log.success('persist', 'SlackChannelId__c écrit sur l\'Opportunity');
        } catch (Exception ex) {
            log.error('unhandled', ex.getMessage() + ' @ ' + ex.getStackTraceString());
            throw ex;
        } finally {
            log.flush();
        }
    }
}
