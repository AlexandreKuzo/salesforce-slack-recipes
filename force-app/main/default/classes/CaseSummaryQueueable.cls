/**
 * Async LLM + Slack DM for SSR Recipe 08.
 * Resolves Case owner email → Slack user Id → chat.postMessage (DM).
 */
public class CaseSummaryQueueable implements Queueable, Database.AllowsCallouts {
    private final Id caseId;

    public CaseSummaryQueueable(Id caseId) {
        this.caseId = caseId;
    }

    public void execute(QueueableContext context) {
        if (caseId == null) {
            return;
        }

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, IsEscalated,
                   Account.Name, Owner.Name, Owner.Email
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            return;
        }

        Case caseRecord = cases[0];
        List<EmailMessage> emails = [
            SELECT Id, Subject, TextBody, HtmlBody, MessageDate
            FROM EmailMessage
            WHERE ParentId = :caseRecord.Id
            ORDER BY MessageDate DESC
            LIMIT 5
        ];

        CaseSummaryService.SummaryResult summary = CaseSummaryService.summarizeCase(caseRecord, emails);
        if (summary == null || !summary.success || String.isBlank(summary.summaryText)) {
            return;
        }

        String ownerEmail = caseRecord.Owner != null ? caseRecord.Owner.Email : null;
        String slackUserId = SlackChannelService.lookupUserByEmail(ownerEmail);
        if (String.isBlank(slackUserId)) {
            return;
        }

        String message = CaseSummaryService.buildSlackMessage(caseRecord, summary);
        message = SlackService.appendRecordLink(message, caseRecord.Id);
        SlackService.postMessage(slackUserId, message);
    }
}
