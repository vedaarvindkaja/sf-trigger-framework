/**
 * CaseSelector
 * Lane 4. The single home for Case SOQL. Bulk-safe, with a per-transaction static
 * cache so two callers in the same transaction never re-query the same Cases.
 * (Previously took a TriggerContext for the cache; with the Trigger Actions
 * Framework the handler passes raw lists, so the cache now lives here as a static
 * — same benefit, no context object required.)
 */
public inherited sharing class CaseSelector {

    private static Map<Id, Case> txCache = new Map<Id, Case>();

    public List<Case> selectByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) return new List<Case>();

        Set<Id> missing = new Set<Id>();
        for (Id i : ids) if (!txCache.containsKey(i)) missing.add(i);

        if (!missing.isEmpty()) {
            for (Case c : [
                SELECT Id, Type, Status, Subject, Resolution__c, ContactId, AccountId
                FROM Case
                WHERE Id IN :missing
            ]) {
                txCache.put(c.Id, c);
            }
        }

        List<Case> result = new List<Case>();
        for (Id i : ids) if (txCache.containsKey(i)) result.add(txCache.get(i));
        return result;
    }

    @TestVisible private static void clearCache() { txCache.clear(); }
}
