/**
 * Case_AfterDelete_Audit
 * Demo AFTER-DELETE action (Trigger Actions Framework). Emits one audit log line
 * per deleted Case. Registered via one Trigger_Action__mdt record
 * (After_Delete -> 'Case'). Kept synchronous (registers no async work) to show
 * that not every action feeds the dispatcher — the buffer/finalizer leg only
 * lights up when an action actually defers work.
 */
public inherited sharing class Case_AfterDelete_Audit implements TriggerAction.AfterDelete {

    private static final String ACTION = 'Case_AfterDelete_Audit';

    public void afterDelete(List<SObject> triggerOld) {
        for (Case c : (List<Case>) triggerOld) {
            AppLogger.info(ACTION, 'Case deleted: ' + c.Id + ' (' + c.Subject + ')');
        }
    }
}
