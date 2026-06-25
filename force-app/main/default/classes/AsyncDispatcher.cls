/**
 * AsyncDispatcher
 * Single, object-agnostic async-work dispatcher (Lane 5 entry). Registered ONCE
 * as a DML_Finalizer__mdt record (Apex_Class_Name__c = 'AsyncDispatcher'), it
 * runs exactly once at the end of the transaction, after the whole trigger
 * cascade has unwound. It drains AsyncWorkBuffer and, for each pending work key,
 * resolves the factory registered in Async_Work__mdt (key -> factory, option A),
 * builds the Queueable, and enqueues it.
 *
 * Durability (the reason this exists, replacing scattered enqueueJob calls):
 *  - A pending key with NO Async_Work__mdt mapping is logged loudly via
 *    AppLogger.error (Context 'Async_Dispatch') and surfaced in Error_Log__c.
 *    It is NOT auto-retried, because a missing mapping is a config error that a
 *    blind retry cannot fix; a human must add the record.
 *  - When the queueable limit is already reached, the work is routed to the
 *    durable error pipeline (Context 'Async_Notification') so ErrorRetryBatch
 *    recovers it, rather than being discarded with a warn.
 *  - Neither path is ever a silent drop.
 *
 * No DML is performed here: getAll(), Type.forName, System.enqueueJob, and
 * EventBus.publish (inside AppLogger) all leave Limits.getDmlStatements()
 * untouched, so the FinalizerHandler no-DML guard is satisfied.
 */
public inherited sharing class AsyncDispatcher implements TriggerAction.DmlFinalizer {

    @TestVisible
    private static final String DISPATCH_CONTEXT = 'Async_Dispatch';
    @TestVisible
    private static final String RETRYABLE_CONTEXT = 'Async_Notification';

    /** Test seam: lets unit tests inject a registry without deployed CMDT. */
    @TestVisible
    private static Map<String, Async_Work__mdt> registryOverride;

    /** Test seam: forces the queueable-limit overflow branch (test context only). */
    @TestVisible
    private static Boolean forceQueueableLimitForTest = false;

    public void execute(FinalizerHandler.Context context) {
        if (AsyncWorkBuffer.isEmpty()) {
            return;
        }
        Map<String, Async_Work__mdt> registry = loadRegistry();

        for (String workKey : orderedKeys(registry)) {
            Set<Id> recordIds = AsyncWorkBuffer.drain(workKey);
            if (recordIds.isEmpty()) {
                continue;
            }
            Async_Work__mdt config = registry.get(workKey);

            if (config == null) {
                // Loud, never silent: a key was registered with no factory mapping.
                AppLogger.error(new AppLogger.ErrorDetail(
                    DISPATCH_CONTEXT,
                    'No Async_Work__mdt factory registered for work key "' + workKey +
                    '". ' + recordIds.size() + ' record(s) were not dispatched.',
                    null).action(workKey));
                continue;
            }
            if (config.Bypass_Execution__c == true) {
                AppLogger.info(DISPATCH_CONTEXT, 'Work key "' + workKey +
                    '" is bypassed; skipped ' + recordIds.size() + ' record(s).');
                continue;
            }
            dispatch(workKey, config.Factory_Class_Name__c, recordIds);
        }
    }

    private void dispatch(String workKey, String factoryClassName, Set<Id> recordIds) {
        AsyncWorkFactory factory = resolveFactory(workKey, factoryClassName);
        if (factory == null) {
            // Config error already logged loudly; a retry would only re-fail.
            return;
        }
        if (queueableLimitReached()) {
            // Transient: route to the durable pipeline so ErrorRetryBatch recovers it.
            overflowToDurableLog(workKey, recordIds);
            return;
        }
        try {
            System.Queueable job = factory.build(recordIds);
            if (job == null) {
                AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT,
                    'Factory "' + factoryClassName + '" returned null for key "' +
                    workKey + '".', null).action(workKey));
                return;
            }
            System.enqueueJob(job);
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT, e.getMessage(),
                e.getStackTraceString()).action(workKey));
        }
    }

    private AsyncWorkFactory resolveFactory(String workKey, String factoryClassName) {
        if (String.isBlank(factoryClassName)) {
            AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT,
                'Async_Work__mdt for key "' + workKey +
                '" has a blank Factory_Class_Name__c.', null).action(workKey));
            return null;
        }
        Type t = Type.forName(factoryClassName);
        if (t == null) {
            AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT,
                'Factory class "' + factoryClassName + '" for key "' + workKey +
                '" could not be resolved (Type.forName returned null).',
                null).action(workKey));
            return null;
        }
        Object instance;
        try {
            instance = t.newInstance();
        } catch (Exception e) {
            AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT,
                'Could not instantiate factory "' + factoryClassName + '" for key "' +
                workKey + '": ' + e.getMessage(),
                e.getStackTraceString()).action(workKey));
            return null;
        }
        if (!(instance instanceof AsyncWorkFactory)) {
            AppLogger.error(new AppLogger.ErrorDetail(DISPATCH_CONTEXT,
                'Class "' + factoryClassName +
                '" does not implement AsyncWorkFactory.', null).action(workKey));
            return null;
        }
        return (AsyncWorkFactory) instance;
    }

    private void overflowToDurableLog(String workKey, Set<Id> recordIds) {
        for (Id recordId : recordIds) {
            AppLogger.error(new AppLogger.ErrorDetail(
                RETRYABLE_CONTEXT,
                'Async work for key "' + workKey +
                '" could not be enqueued (queueable limit). Queued for retry.',
                null).action(workKey).record(recordId));
        }
    }

    private Boolean queueableLimitReached() {
        // Production: real governor check. Tests: the seam forces the branch,
        // since Limits.getQueueableJobs() cannot be driven to the cap directly.
        if (Test.isRunningTest() && forceQueueableLimitForTest) {
            return true;
        }
        return Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs();
    }

    private Map<String, Async_Work__mdt> loadRegistry() {
        if (registryOverride != null) {
            return registryOverride;
        }
        Map<String, Async_Work__mdt> byKey = new Map<String, Async_Work__mdt>();
        for (Async_Work__mdt w : Async_Work__mdt.getAll().values()) {
            byKey.put(w.Work_Key__c, w);
        }
        return byKey;
    }

    private List<String> orderedKeys(Map<String, Async_Work__mdt> registry) {
        List<String> keys = new List<String>(AsyncWorkBuffer.pendingKeys());
        keys.sort(new KeyOrderComparator(registry));
        return keys;
    }

    private class KeyOrderComparator implements System.Comparator<String> {
        private final Map<String, Async_Work__mdt> registry;
        private KeyOrderComparator(Map<String, Async_Work__mdt> registry) {
            this.registry = registry;
        }
        public Integer compare(String a, String b) {
            Decimal oa = orderOf(a);
            Decimal ob = orderOf(b);
            if (oa == ob) {
                return a.compareTo(b);
            }
            return oa > ob ? 1 : -1;
        }
        private Decimal orderOf(String key) {
            Async_Work__mdt w = registry.get(key);
            return (w != null && w.Order__c != null) ? w.Order__c : 999999;
        }
    }
}
