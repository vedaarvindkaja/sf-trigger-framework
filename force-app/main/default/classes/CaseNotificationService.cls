/**
 * CaseNotificationService
 * Lane 3. Decides WHAT notification work is needed and REGISTERS it for the
 * end-of-transaction dispatcher. It does not enqueue or perform the callout.
 *
 * Why register instead of enqueue (the change from the original design):
 *   - Enqueuing from an after-trigger action fires per DML pass and forced this
 *     class to re-implement dedup plus async-context and queueable-limit skips —
 *     the latter two were silent warn-and-return branches that dropped work
 *     outside the durable error pipeline.
 *   - Registering into AsyncWorkBuffer (a Map<String, Set<Id>>) makes dispatch
 *     idempotent STRUCTURALLY (duplicate Ids across passes collapse), and hands
 *     the single AsyncDispatcher the once-per-transaction enqueue, the
 *     queueable-limit overflow, and the durable error routing. No silent drops.
 *
 * REQUIRES (config, hand-created in the org):
 *   - DML_Finalizer__mdt record -> Apex_Class_Name__c = 'AsyncDispatcher'
 *     (without it, the buffer never drains and notifications silently stop).
 *   - Async_Work__mdt record -> Work_Key__c = 'CaseNotify',
 *     Factory_Class_Name__c = 'CaseNotificationWorkFactory'
 *     (without it, the dispatcher logs loudly and discards — never silent).
 */
public inherited sharing class CaseNotificationService {

    @TestVisible
    private static final String WORK_KEY = 'CaseNotify';

    /**
     * Register disruption notifications for the given Case Ids. Safe to call from
     * both after-insert and after-update in the same transaction: the buffer's
     * Set collapses duplicates, so the dispatcher enqueues each Case at most once.
     */
    public void notifyDisruption(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return;
        }
        AsyncWorkBuffer.register(WORK_KEY, caseIds);
    }
}
