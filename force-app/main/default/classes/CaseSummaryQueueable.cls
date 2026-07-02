/**
 * Async case AI summary + Slack post for SSR Recipe 08.
 */
public class CaseSummaryQueueable implements Queueable, Database.AllowsCallouts {
    private final Id caseId;

    public CaseSummaryQueueable(Id caseId) {
        this.caseId = caseId;
    }

    public void execute(QueueableContext context) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status, Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            return;
        }

        Case caseRecord = cases[0];
        List<EmailMessage> emails = [
            SELECT TextBody, Subject, CreatedDate
            FROM EmailMessage
            WHERE ParentId = :caseId
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        CaseSummaryService.SummaryResult result = CaseSummaryService.summarizeCase(caseRecord, emails);
        if (!result.success || String.isBlank(result.summary)) {
            return;
        }

        String header = result.usedAi ? '✦ *Résumé IA*' : '✦ *Résumé case*';
        String accountName = caseRecord.Account != null ? caseRecord.Account.Name : 'N/A';
        String message = header + ' — Case *' + caseRecord.CaseNumber + '* (' + accountName + ')\n\n'
            + result.summary;

        message = SlackService.appendRecordLink(message, caseRecord.Id);
        SlackService.postMessageForRecipe('recipe_08', message);
    }
}
