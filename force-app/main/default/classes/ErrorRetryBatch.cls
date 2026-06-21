/**
 * ErrorRetryBatch
 * Lane 5 recovery. Reprocesses durable failures. Only async-notification logs
 * are auto-retriable (the Case saved; only the side-effect failed). Synchronous
 * rollback failures are NOT retried here — the record never persisted, so there
 * is nothing to act on; those logs stay 'New' for a human.
 *
 * Safety: Retry_Count__c < MAX stops infinite loops; status moves to 'Retrying'
 * so the same row isn't picked up twice. Idempotency is the caller's job — the
 * re-enqueued queueable re-checks state before acting.
 *
 * Schedule: System.scheduleBatch(new ErrorRetryBatch(), 'Error retry', 15);
 */
public with sharing class ErrorRetryBatch implements Database.Batchable<SObject> {

    private static final Integer MAX_RETRIES = 3;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Record_Id__c, Action_Name__c, Retry_Count__c
            FROM Error_Log__c
            WHERE Status__c = 'New'
              AND Context__c = 'Async_Notification'
              AND Retry_Count__c < :MAX_RETRIES
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Error_Log__c> logs = (List<Error_Log__c>) scope;
        Set<Id> caseIds = new Set<Id>();
        for (Error_Log__c log : logs) {
            if (String.isNotBlank(log.Record_Id__c)) caseIds.add((Id) log.Record_Id__c);
            log.Retry_Count__c = (log.Retry_Count__c == null ? 0 : log.Retry_Count__c) + 1;
            log.Status__c = 'Retrying';
        }
        Database.update(logs, false);

        if (!caseIds.isEmpty()
            && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new CaseNotificationQueueable(caseIds));
        }
    }

    public void finish(Database.BatchableContext bc) {
        AppLogger.info('ErrorRetryBatch', 'Retry sweep complete.');
    }
}
