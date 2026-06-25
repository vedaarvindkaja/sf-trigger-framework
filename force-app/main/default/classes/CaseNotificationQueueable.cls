/**
 * CaseNotificationQueueable
 * Lane 5 (async tail). Runs AFTER commit — the home for callouts and post-commit
 * side effects. Implements Finalizer so an unhandled failure is captured (and
 * logged durably) instead of vanishing. `failForTest` lets tests force the
 * failure path to exercise the Error_Log pipeline.
 */
public class CaseNotificationQueueable implements Queueable, Database.AllowsCallouts, Finalizer {

    private final Set<Id> caseIds;
    @TestVisible private static Boolean failForTest    = false;
    @TestVisible private static Boolean finalizerCalled = false;

    public CaseNotificationQueueable(Set<Id> caseIds) { this.caseIds = caseIds; }

    public void execute(QueueableContext qc) {
        System.attachFinalizer(this);

        if (failForTest) throw new CalloutException('Simulated notification failure');

        List<Case> cases = new CaseSelector().selectByIds(caseIds);
        for (Case c : cases) {
            // Placeholder for the real side effect (email / Platform Event / callout).
            AppLogger.info('CaseNotificationQueueable',
                'Notified disruption for Case ' + c.Id + ' (' + c.Subject + ')');
        }
    }

    public void execute(FinalizerContext fc) {
        finalizerCalled = true;
        if (fc.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            // One durable Error_Log per failed Case, tagged Async_Notification so
            // the retry batch (ErrorRetryBatch) can find and re-enqueue them.
            String stack = fc.getException() != null ? fc.getException().getStackTraceString() : null;
            String msg   = fc.getException() != null ? fc.getException().getMessage() : 'Unknown async failure';
            for (Id caseId : caseIds) {
                AppLogger.error(new AppLogger.ErrorDetail('Async_Notification', msg, stack)
                    .action('CaseNotificationQueueable').sObj('Case').record(caseId));
            }
        }
    }
}
