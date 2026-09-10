/**
 * Executes Slack HTTP callouts outside the triggering transaction.
 * Records the outcome to SSR_Log__c (recipes 01–02 and any ad-hoc SlackInvocable call).
 */
public class SlackCalloutQueueable implements Queueable, Database.AllowsCallouts {
    private final String recipeKey;
    private final String channelId;
    private final String message;
    private final Id recordId;

    public SlackCalloutQueueable(String recipeKey, String channelId, String message, Id recordId) {
        this.recipeKey = recipeKey;
        this.channelId = channelId;
        this.message = message;
        this.recordId = recordId;
    }

    public void execute(QueueableContext context) {
        SSRLogger log = new SSRLogger(
            String.isNotBlank(recipeKey) ? recipeKey : 'slack_adhoc',
            recordId
        ).setJobId(context.getJobId());

        try {
            String body = SlackService.appendRecordLink(message, recordId);
            SlackService.PostMessageResult result;

            if (String.isNotBlank(recipeKey)) {
                result = SlackService.postMessageForRecipe(recipeKey, body);
            } else if (String.isNotBlank(channelId)) {
                result = SlackService.postMessage(channelId, body);
            } else {
                log.error('notify', 'Ni recipeKey ni channelId fournis');
                return;
            }

            if (result != null && result.success) {
                log.success('notify', 'Slack posté (ts ' + result.slackTs + ')');
            } else {
                log.error('notify', 'Slack KO : '
                    + (result != null ? result.errorMessage : 'réponse vide'));
            }
        } catch (Exception ex) {
            log.error('unhandled', ex.getMessage() + ' @ ' + ex.getStackTraceString());
            throw ex;
        } finally {
            log.flush();
        }
    }
}
