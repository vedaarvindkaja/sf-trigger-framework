/**
 * RecursionGuard
 * Cross-cutting. Bypass and recursion control are DIFFERENT problems:
 *   - bypass  = "skip this object's automation entirely" (data loads).
 *   - guard   = "don't reprocess records I already processed in THIS transaction"
 *               (prevents field-update -> trigger re-fire loops, duplicate
 *               notifications, double DML).
 *
 * Two tools:
 *   runOnce(key)        — true the first time a key is seen this transaction,
 *                         false afterwards. Use for "do X at most once".
 *   unprocessed(key,ids)— returns only the Ids not yet handled under key, and
 *                         marks them handled. Use for record-level idempotency.
 *
 * Static state is per-transaction (Apex statics reset between transactions).
 */
public class RecursionGuard {

    @TestVisible private static Set<String> runKeys = new Set<String>();
    @TestVisible private static Map<String, Set<Id>> processed = new Map<String, Set<Id>>();

    public static Boolean runOnce(String key) {
        if (runKeys.contains(key)) return false;
        runKeys.add(key);
        return true;
    }

    public static Set<Id> unprocessed(String key, Set<Id> ids) {
        Set<Id> seen = processed.get(key);
        if (seen == null) { seen = new Set<Id>(); processed.put(key, seen); }
        Set<Id> fresh = new Set<Id>();
        for (Id i : ids) {
            if (!seen.contains(i)) { fresh.add(i); seen.add(i); }
        }
        return fresh;
    }

    @TestVisible
    private static void reset() { runKeys.clear(); processed.clear(); }
}
