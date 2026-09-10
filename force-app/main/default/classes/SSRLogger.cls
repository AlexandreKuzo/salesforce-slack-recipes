/**
 * Buffered execution logger for SSR recipes. Collect entries during a Queueable run, then
 * flush() once (a single DML) — typically from a finally block. Logging never throws:
 * a failed flush is swallowed so it can't break the recipe it is observing.
 *
 *   SSRLogger log = new SSRLogger('recipe_10', leadId).setJobId(context.getJobId());
 *   ...
 *   log.success('scoring', 'score 95', 'openai');
 *   log.error('notify', 'Slack: not_in_channel');
 *   ...
 *   log.flush();   // finally
 */
public without sharing class SSRLogger {
    @TestVisible
    private static final Integer MESSAGE_MAX = 32000;

    private final String recipeKey;
    private final String recordId;
    private final Long startMs;
    private String jobId;
    private final List<SSR_Log__c> buffer = new List<SSR_Log__c>();

    public SSRLogger(String recipeKey, Id recordId) {
        this.recipeKey = recipeKey;
        this.recordId = recordId != null ? String.valueOf(recordId) : null;
        this.startMs = System.currentTimeMillis();
    }

    public SSRLogger setJobId(Id jobId) {
        this.jobId = jobId != null ? String.valueOf(jobId) : null;
        return this;
    }

    public void success(String step, String message) {
        add('Success', step, message, null);
    }

    public void success(String step, String message, String mode) {
        add('Success', step, message, mode);
    }

    public void warning(String step, String message) {
        add('Warning', step, message, null);
    }

    public void warning(String step, String message, String mode) {
        add('Warning', step, message, mode);
    }

    public void error(String step, String message) {
        add('Error', step, message, null);
    }

    /** Number of buffered (not yet flushed) entries — for assertions and callers that branch on it. */
    @TestVisible
    public Integer pending() {
        return buffer.size();
    }

    public void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        try {
            insert buffer;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'SSRLogger: flush failed — ' + ex.getMessage());
        }
        buffer.clear();
    }

    private void add(String status, String step, String message, String mode) {
        buffer.add(
            new SSR_Log__c(
                Recipe_Key__c = clip(recipeKey, 40),
                Status__c = status,
                Step__c = clip(step, 80),
                Message__c = clip(message, MESSAGE_MAX),
                Mode__c = clip(mode, 20),
                Record_Id__c = recordId,
                Job_Id__c = jobId,
                Duration_Ms__c = System.currentTimeMillis() - startMs
            )
        );
    }

    private static String clip(String value, Integer max) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.length() <= max ? value : value.substring(0, max);
    }
}
