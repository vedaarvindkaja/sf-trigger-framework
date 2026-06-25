/**
 * AsyncDispatcherTest
 * Covers the dispatcher in isolation by injecting a registry (registryOverride),
 * so it does not depend on deployed Async_Work__mdt records. Exercises:
 *   - happy path: a registered key drains and enqueues
 *   - loud failure: an unmapped key is logged durably, never silently dropped
 *   - bypass: a bypassed key is drained and skipped
 */
@IsTest
private class AsyncDispatcherTest {

    private static void registerFactory(String key, String cls, Boolean bypass) {
        if (AsyncDispatcher.registryOverride == null) {
            AsyncDispatcher.registryOverride = new Map<String, Async_Work__mdt>();
        }
        AsyncDispatcher.registryOverride.put(key, new Async_Work__mdt(
            Work_Key__c = key,
            Factory_Class_Name__c = cls,
            Order__c = 10,
            Bypass_Execution__c = bypass));
    }

    @IsTest
    static void dispatchesRegisteredWork() {
        AsyncWorkBuffer.clear();
        AsyncDispatcher.registryOverride = null;
        registerFactory('CaseNotify', 'CaseNotificationWorkFactory', false);

        Case c = new Case(Subject = 'x', Type = 'Delay'); // Delay: trigger enqueues nothing
        insert c;
        AsyncWorkBuffer.register('CaseNotify', c.Id);

        Test.startTest();
        new AsyncDispatcher().execute(new FinalizerHandler.Context());
        Test.stopTest(); // the enqueued job runs here

        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'Dispatcher drained the buffer.');
    }

    @IsTest
    static void missingFactoryLogsLoudly() {
        AsyncWorkBuffer.clear();
        AsyncDispatcher.registryOverride = new Map<String, Async_Work__mdt>(); // empty registry
        AsyncWorkBuffer.register('Unmapped', TestIds.next(Case.SObjectType));

        Test.startTest();
        new AsyncDispatcher().execute(new FinalizerHandler.Context());
        Test.stopTest(); // delivers the Error_Event__e -> subscriber inserts the log

        List<Error_Log__c> logs = [
            SELECT Context__c, Action_Name__c
            FROM Error_Log__c
            WHERE Context__c = :AsyncDispatcher.DISPATCH_CONTEXT
        ];
        System.Assert.areEqual(1, logs.size(), 'Missing factory must be logged, never silent.');
        System.Assert.areEqual('Unmapped', logs[0].Action_Name__c);
        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'Unmapped key is still drained.');
    }

    @IsTest
    static void bypassedKeyIsSkipped() {
        AsyncWorkBuffer.clear();
        AsyncDispatcher.registryOverride = null;
        registerFactory('CaseNotify', 'CaseNotificationWorkFactory', true); // bypassed
        AsyncWorkBuffer.register('CaseNotify', TestIds.next(Case.SObjectType));

        Test.startTest();
        new AsyncDispatcher().execute(new FinalizerHandler.Context());
        Test.stopTest();

        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'Bypassed key is drained and discarded.');
    }

    @IsTest
    static void overflowRoutesToDurableLog() {
        AsyncWorkBuffer.clear();
        AsyncDispatcher.registryOverride = null;
        registerFactory('CaseNotify', 'CaseNotificationWorkFactory', false);
        AsyncDispatcher.forceQueueableLimitForTest = true; // force the overflow branch

        Id caseId = TestIds.next(Case.SObjectType);
        AsyncWorkBuffer.register('CaseNotify', caseId);

        Test.startTest();
        new AsyncDispatcher().execute(new FinalizerHandler.Context());
        Test.stopTest(); // delivers the Error_Event__e -> subscriber inserts the log

        List<Error_Log__c> logs = [
            SELECT Context__c, Action_Name__c, Status__c, Record_Id__c
            FROM Error_Log__c
            WHERE Context__c = :AsyncDispatcher.RETRYABLE_CONTEXT
        ];
        System.Assert.areEqual(1, logs.size(),
            'Overflow must land in the durable log, never be dropped.');
        System.Assert.areEqual('CaseNotify', logs[0].Action_Name__c);
        System.Assert.areEqual('New', logs[0].Status__c,
            'Status New so ErrorRetryBatch can recover it.');
        System.Assert.areEqual(String.valueOf(caseId), logs[0].Record_Id__c);
        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'Buffer drained even on overflow.');
    }
}
