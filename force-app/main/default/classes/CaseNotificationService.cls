/**
 * CaseNotificationService
 * Lane 3. Decides WHAT notification work is needed; it does not perform the
 * callout itself. Cross-object/callout/post-commit work is handed to the async
 * tail (Lane 5) so it never runs inside the synchronous trigger transaction.
 */
public inherited sharing class CaseNotificationService {

    /**
     * Enqueue disruption notifications for the given Case Ids. Guards against
     * re-entry so a re-fired update can't double-notify. No-op when there is
     * nothing to send or when async isn't allowed in the current context.
     */
    public void notifyDisruption(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        Set<Id> fresh = RecursionGuard.unprocessed('CaseNotify', caseIds);
        if (fresh.isEmpty()) return;

        if (System.isBatch() || System.isFuture() || System.isQueueable()) {
            // Already async — avoid chaining depth issues; log and skip enqueue.
            AppLogger.warn('CaseNotificationService', 'Skipping enqueue in async context.');
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            AppLogger.warn('CaseNotificationService', 'Queueable limit reached.');
            return;
        }
        System.enqueueJob(new CaseNotificationQueueable(fresh));
    }
}
