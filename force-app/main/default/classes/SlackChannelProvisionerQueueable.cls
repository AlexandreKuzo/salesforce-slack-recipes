/**
 * Async channel provisioning (multiple Slack callouts) for SSR Recipe 07.
 */
public class SlackChannelProvisionerQueueable implements Queueable, Database.AllowsCallouts {
    private final Id opportunityId;
    private final String welcomeMessage;

    public SlackChannelProvisionerQueueable(Id opportunityId, String welcomeMessage) {
        this.opportunityId = opportunityId;
        this.welcomeMessage = welcomeMessage;
    }

    public void execute(QueueableContext context) {
        List<Opportunity> opps = [
            SELECT Id, Name, Amount, SlackChannelId__c, Account.Name,
                   Owner.Name, Owner.Email, Owner.Manager.Email
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (opps.isEmpty()) {
            return;
        }

        Opportunity opp = opps[0];
        if (String.isNotBlank(opp.SlackChannelId__c)) {
            return;
        }

        String accountName = opp.Account != null ? opp.Account.Name : opp.Name;
        String channelName = SlackChannelService.buildDealChannelName(accountName);
        SlackChannelService.ChannelResult created = SlackChannelService.createChannel(channelName);

        if (!created.success || String.isBlank(created.channelId)) {
            return;
        }

        List<String> slackUserIds = new List<String>();
        String ownerSlackId = SlackChannelService.lookupUserByEmail(opp.Owner != null ? opp.Owner.Email : null);
        if (String.isNotBlank(ownerSlackId)) {
            slackUserIds.add(ownerSlackId);
        }

        String managerEmail = opp.Owner != null && opp.Owner.Manager != null ? opp.Owner.Manager.Email : null;
        String managerSlackId = SlackChannelService.lookupUserByEmail(managerEmail);
        if (String.isNotBlank(managerSlackId) && !slackUserIds.contains(managerSlackId)) {
            slackUserIds.add(managerSlackId);
        }

        SlackChannelService.inviteUsers(created.channelId, slackUserIds);

        String message = String.isNotBlank(welcomeMessage)
            ? welcomeMessage
            : SlackChannelService.buildWelcomeMessage(opp);
        message = SlackService.appendRecordLink(message, opp.Id);
        SlackService.postMessage(created.channelId, message);

        update new Opportunity(
            Id = opp.Id,
            SlackChannelId__c = created.channelId
        );
    }
}
