/**
 * Executes Slack HTTP callouts outside the triggering transaction.
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
        String body = SlackService.appendRecordLink(message, recordId);

        if (String.isNotBlank(recipeKey)) {
            SlackService.postMessageForRecipe(recipeKey, body);
        } else if (String.isNotBlank(channelId)) {
            SlackService.postMessage(channelId, body);
        }
    }
}
