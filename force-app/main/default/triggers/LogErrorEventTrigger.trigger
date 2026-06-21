/**
 * LogErrorEventTrigger
 * Subscriber for Error_Event__e. Runs in its OWN transaction (platform-event
 * delivery), so the insert here is independent of whatever transaction failed
 * and published the event. This is the half that makes error capture survive a
 * rollback. Status defaults to 'New' so the retry batch can pick it up.
 */
trigger LogErrorEventTrigger on Error_Event__e (after insert) {
    List<Error_Log__c> logs = new List<Error_Log__c>();
    for (Error_Event__e e : Trigger.new) {
        logs.add(new Error_Log__c(
            Record_Id__c      = e.Record_Id__c,
            SObject_Type__c   = e.SObject_Type__c,
            Context__c        = e.Context__c,
            Action_Name__c    = e.Action_Name__c,
            Severity__c       = String.isBlank(e.Severity__c) ? 'Error' : e.Severity__c,
            Message__c        = e.Message__c,
            Stack_Trace__c    = e.Stack_Trace__c,
            Transaction_Id__c = e.Transaction_Id__c,
            Status__c         = 'New',
            Retry_Count__c    = 0
        ));
    }
    if (!logs.isEmpty()) {
        // allOrNone=false: one bad row must not drop the rest of the batch.
        Database.insert(logs, false);
    }
}
