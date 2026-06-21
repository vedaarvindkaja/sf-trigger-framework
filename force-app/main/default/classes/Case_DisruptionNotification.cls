/**
 * Case_DisruptionNotification
 * THIN ADAPTER (Trigger Actions Framework), after-context. Figures out which
 * Cases became cancellations and hands them to the notification service, which
 * pushes the actual work to the async tail. On update it uses the service's diff
 * (newlyCancelled) so it only fires for Cases that NEWLY became cancellations —
 * not ones that already were — which is what prevents duplicate notifications.
 */
public inherited sharing class Case_DisruptionNotification
        implements TriggerAction.AfterInsert, TriggerAction.AfterUpdate {

    private static final String ACTION = 'Case_DisruptionNotification';
    private final CaseRefundService refund = new CaseRefundService();
    private final CaseNotificationService notifier = new CaseNotificationService();

    public void afterInsert(List<SObject> triggerNew) {
        try {
            Set<Id> ids = new Set<Id>();
            for (Case c : (List<Case>) triggerNew) {
                if (c.Type == 'Cancellation') ids.add(c.Id);
            }
            notifier.notifyDisruption(ids);
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail('After_Insert', e.getMessage(),
                e.getStackTraceString()).action(ACTION).sObj('Case'));
            throw e;
        }
    }

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        try {
            Map<Id, Case> oldMap = new Map<Id, Case>((List<Case>) triggerOld);
            Set<Id> ids = refund.newlyCancelled((List<Case>) triggerNew, oldMap);
            notifier.notifyDisruption(ids);
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail('After_Update', e.getMessage(),
                e.getStackTraceString()).action(ACTION).sObj('Case'));
            throw e;
        }
    }
}
