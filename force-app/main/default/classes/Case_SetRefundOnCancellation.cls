/**
 * Case_SetRefundOnCancellation
 * THIN ADAPTER (Trigger Actions Framework). Implements the framework's
 * BeforeInsert/BeforeUpdate interfaces — note the signatures take raw lists, not
 * a shared context object (that is the framework's contract). All real logic
 * lives in CaseRefundService, so this class stays trivially testable and is the
 * only thing you write to add the rule. Registered via one Trigger_Action__mdt
 * record; CaseTrigger and MetadataTriggerHandler are never edited (open/closed).
 */
public inherited sharing class Case_SetRefundOnCancellation
        implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    private static final String ACTION = 'Case_SetRefundOnCancellation';
    private final CaseRefundService service = new CaseRefundService();

    public void beforeInsert(List<SObject> triggerNew) {
        try {
            Integer n = service.applyRefundOnCancellation((List<Case>) triggerNew);
            if (n > 0) AppLogger.info(ACTION, 'Set Refund on ' + n + ' new case(s).');
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail('Before_Insert', e.getMessage(),
                e.getStackTraceString()).action(ACTION).sObj('Case'));
            throw e; // re-throw: let the framework roll the transaction back.
        }
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        try {
            Integer n = service.applyRefundOnCancellation((List<Case>) triggerNew);
            if (n > 0) AppLogger.info(ACTION, 'Set Refund on ' + n + ' updated case(s).');
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail('Before_Update', e.getMessage(),
                e.getStackTraceString()).action(ACTION).sObj('Case'));
            throw e;
        }
    }
}
