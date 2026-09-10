/**
 * Async LLM + Slack DM for SSR Recipe 08.
 * Resolves Case owner email → Slack user Id → chat.postMessage (DM).
 * Every step is recorded to SSR_Log__c via SSRLogger.
 */
public class CaseSummaryQueueable implements Queueable, Database.AllowsCallouts {
    private static final String RECIPE_KEY = 'recipe_08';
    private final Id caseId;

    public CaseSummaryQueueable(Id caseId) {
        this.caseId = caseId;
    }

    public void execute(QueueableContext context) {
        if (caseId == null) {
            return;
        }

        SSRLogger log = new SSRLogger(RECIPE_KEY, caseId).setJobId(context.getJobId());
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Description, Priority, Status, IsEscalated,
                       Account.Name, OwnerId
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                log.warning('load', 'Case introuvable');
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
                log.error('summary', 'Résumé indisponible');
                return;
            }
            log.success('summary', 'Résumé généré (' + emails.size() + ' e-mails)', summary.mode);

            String ownerEmail = ownerEmail(caseRecord.OwnerId);
            String slackUserId = SlackService.lookupUserByEmail(ownerEmail);
            if (String.isBlank(slackUserId)) {
                log.warning('lookup',
                    'Owner Slack introuvable pour ' + (ownerEmail != null ? ownerEmail : '(owner sans e-mail)')
                    + ' — DM non envoyé');
                return;
            }

            String message = CaseSummaryService.buildSlackMessage(caseRecord, summary);
            message = SlackService.appendRecordLink(message, caseRecord.Id);
            SlackService.PostMessageResult result = SlackService.postMessage(slackUserId, message);

            if (result != null && result.success) {
                log.success('notify', 'DM Slack envoyé à l\'owner (ts ' + result.slackTs + ')');
            } else {
                log.error('notify', 'DM Slack KO : '
                    + (result != null ? result.errorMessage : 'réponse vide'));
            }
        } catch (Exception ex) {
            log.error('unhandled', ex.getMessage() + ' @ ' + ex.getStackTraceString());
            throw ex;
        } finally {
            log.flush();
        }
    }

    /**
     * The Case owner is polymorphic (User or Queue) and its User fields do not resolve
     * through the Owner relationship in test context — so read the e-mail from User directly,
     * and treat a queue-owned Case as "no e-mail".
     */
    private static String ownerEmail(Id ownerId) {
        if (ownerId == null || ownerId.getSObjectType() != Schema.User.SObjectType) {
            return null;
        }
        List<User> owners = [SELECT Email FROM User WHERE Id = :ownerId LIMIT 1];
        return owners.isEmpty() ? null : owners[0].Email;
    }
}
