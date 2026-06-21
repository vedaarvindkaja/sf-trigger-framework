/**
 * CaseRefundService
 * Lane 3. The actual business rule lives here, NOT in the trigger action. It is
 * stateless, bulkified, and callable from anywhere (a trigger action, a batch, an
 * LWC controller) — and unit-testable with plain in-memory Cases, no DML and no
 * trigger context required. That testability is the whole point of the layer.
 *
 * Rule (airline scenario): a Flight Disruption Case created/updated with
 * Type = 'Cancellation' gets Resolution__c = 'Refund'.
 */
public inherited sharing class CaseRefundService {

    private static final String TYPE_CANCELLATION = 'Cancellation';
    private static final String RESOLUTION_REFUND  = 'Refund';

    /**
     * Mutates the supplied Cases in memory. Caller runs in BEFORE context so the
     * platform persists the change — no DML here. Returns count changed (useful
     * for logging / assertions).
     */
    public Integer applyRefundOnCancellation(List<Case> cases) {
        Integer changed = 0;
        if (cases == null) return changed;
        for (Case c : cases) {
            if (c.Type == TYPE_CANCELLATION && c.Resolution__c != RESOLUTION_REFUND) {
                c.Resolution__c = RESOLUTION_REFUND;
                changed++;
            }
        }
        return changed;
    }

    /**
     * Returns the Ids of Cases that newly became cancellations on update — used by
     * the notification action to decide who to alert. Pure function over the maps.
     */
    public Set<Id> newlyCancelled(List<Case> newList, Map<Id, Case> oldMap) {
        Set<Id> result = new Set<Id>();
        if (newList == null) return result;
        for (Case c : newList) {
            Case prior = (oldMap != null) ? oldMap.get(c.Id) : null;
            Boolean wasCancellation = prior != null && prior.Type == TYPE_CANCELLATION;
            if (c.Type == TYPE_CANCELLATION && !wasCancellation) result.add(c.Id);
        }
        return result;
    }
}
