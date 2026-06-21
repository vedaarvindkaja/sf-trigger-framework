/**
 * UnitOfWork
 * Lane 4. Collects DML across all actions in a transaction and commits it in one
 * ordered pass, so partitioned actions don't each run their own insert/update and
 * burn DML statements. Intentionally lightweight (not full fflib) — register,
 * then commitWork() once.
 *
 * NOTE: before-context field changes on Trigger.new do NOT go here — those are
 * saved by the platform automatically. Register here only NEW related records or
 * updates to OTHER records.
 */
public class UnitOfWork {

    private List<SObject> toInsert = new List<SObject>();
    private List<SObject> toUpdate = new List<SObject>();
    private List<SObject> toDelete = new List<SObject>();

    public void registerNew(SObject rec)            { if (rec != null) toInsert.add(rec); }
    public void registerNew(List<SObject> recs)     { if (recs != null) toInsert.addAll(recs); }
    public void registerDirty(SObject rec)          { if (rec != null) toUpdate.add(rec); }
    public void registerDirty(List<SObject> recs)   { if (recs != null) toUpdate.addAll(recs); }
    public void registerDeleted(SObject rec)        { if (rec != null) toDelete.add(rec); }

    public Boolean isEmpty() {
        return toInsert.isEmpty() && toUpdate.isEmpty() && toDelete.isEmpty();
    }

    public void commitWork() {
        if (isEmpty()) return;
        Savepoint sp = Database.setSavepoint();
        try {
            if (!toInsert.isEmpty()) insert toInsert;
            if (!toUpdate.isEmpty()) update toUpdate;
            if (!toDelete.isEmpty()) delete toDelete;
            clear();
        } catch (Exception e) {
            Database.rollback(sp);
            AppLogger.error('UnitOfWork', e);
            throw e;
        }
    }

    private void clear() {
        toInsert = new List<SObject>();
        toUpdate = new List<SObject>();
        toDelete = new List<SObject>();
    }
}
