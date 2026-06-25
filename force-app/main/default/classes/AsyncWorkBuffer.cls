/**
 * @description Transaction-scoped accumulator for deferred async work.
 *
 * Trigger actions register record Ids under a string work key during the
 * synchronous phase. Because the backing store is a Map&lt;String, Set&lt;Id&gt;&gt;,
 * registering the same record many times across recursive or cascading trigger
 * passes collapses to a single entry by Set semantics. Dispatch idempotency is
 * therefore a STRUCTURAL property of the framework, not something each
 * contributor must enforce by hand.
 *
 * The buffer is drained once, at the end of the transaction, by AsyncDispatcher
 * (a TriggerAction.DmlFinalizer). State lives in statics, so it is isolated per
 * transaction and reset automatically between transactions.
 */
public inherited sharing class AsyncWorkBuffer {
    @TestVisible
    private static Map<String, Set<Id>> workByKey = new Map<String, Set<Id>>();

    /**
     * @description Register a set of record Ids under a work key. Duplicate Ids
     *              accumulated across passes are collapsed by Set semantics.
     * @param workKey   Logical key identifying the unit of async work.
     * @param recordIds Records to defer. A null or empty set is a no-op.
     */
    public static void register(String workKey, Set<Id> recordIds) {
        if (String.isBlank(workKey) || recordIds == null || recordIds.isEmpty()) {
            return;
        }
        Set<Id> bucket = workByKey.get(workKey);
        if (bucket == null) {
            bucket = new Set<Id>();
            workByKey.put(workKey, bucket);
        }
        bucket.addAll(recordIds);
    }

    /**
     * @description Convenience overload for registering a single record Id.
     * @param workKey  Logical key identifying the unit of async work.
     * @param recordId Record to defer. Null is a no-op.
     */
    public static void register(String workKey, Id recordId) {
        if (recordId == null) {
            return;
        }
        register(workKey, new Set<Id>{ recordId });
    }

    /**
     * @description The set of work keys that currently have pending records.
     *              Returns a copy so callers may safely drain while iterating.
     * @return A copy of the pending key set.
     */
    public static Set<String> pendingKeys() {
        return workByKey.keySet().clone();
    }

    /**
     * @description Whether any work is pending in the buffer.
     * @return True when the buffer holds no records.
     */
    public static Boolean isEmpty() {
        return workByKey.isEmpty();
    }

    /**
     * @description Remove and return the records registered under a key.
     *              Draining guarantees the same work cannot be dispatched twice.
     * @param workKey The key to drain.
     * @return The records for that key, or an empty set if none were registered.
     */
    public static Set<Id> drain(String workKey) {
        Set<Id> bucket = workByKey.remove(workKey);
        return bucket == null ? new Set<Id>() : bucket;
    }

    /**
     * @description Clear all pending work. Intended for test setup and teardown.
     */
    @TestVisible
    private static void clear() {
        workByKey.clear();
    }
}
