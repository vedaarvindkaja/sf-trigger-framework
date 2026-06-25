/**
 * Case_PreventDeleteIfClosed
 * Demo BEFORE-DELETE action (Trigger Actions Framework). Blocks deletion of
 * closed Cases. Registered via one Trigger_Action__mdt record
 * (Before_Delete -> 'Case'). Demonstrates the delete context running through the
 * same ordered registry as insert and update. Uses the standard IsClosed field,
 * so it needs no custom configuration.
 */
public inherited sharing class Case_PreventDeleteIfClosed implements TriggerAction.BeforeDelete {

    private static final String ACTION = 'Case_PreventDeleteIfClosed';

    public void beforeDelete(List<SObject> triggerOld) {
        Integer blocked = 0;
        for (Case c : (List<Case>) triggerOld) {
            if (c.IsClosed) {
                c.addError('Closed cases cannot be deleted.');
                blocked++;
            }
        }
        if (blocked > 0) {
            AppLogger.info(ACTION, 'Blocked deletion of ' + blocked + ' closed case(s).');
        }
    }
}
