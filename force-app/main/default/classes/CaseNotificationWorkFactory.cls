/**
 * CaseNotificationWorkFactory
 * Maps the 'CaseNotify' work key to its async job. Registered via one
 * Async_Work__mdt record (Work_Key__c = 'CaseNotify',
 * Factory_Class_Name__c = 'CaseNotificationWorkFactory'). AsyncDispatcher
 * resolves this class via Type.forName at end of transaction and calls build().
 *
 * build() must be side-effect free: construct and return the job only. Do not
 * enqueue, publish, or perform DML here — the dispatcher owns those.
 */
public inherited sharing class CaseNotificationWorkFactory implements AsyncWorkFactory {
    public System.Queueable build(Set<Id> recordIds) {
        return new CaseNotificationQueueable(recordIds);
    }
}
