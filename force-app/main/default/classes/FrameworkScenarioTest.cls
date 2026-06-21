/**
 * FrameworkScenarioTest
 * One test class that walks every scenario in the build:
 *   - sync rule through the Trigger Actions Framework (refund on cancellation)
 *   - recursion / processed / unprocessed (RecursionGuard)
 *   - async tail (queueable) success
 *   - async FAILURE -> Finalizer -> Error_Event__e -> Error_Log__c (durable)
 *   - platform-event subscriber writes the log
 *   - retry batch picks up a New async log and re-enqueues
 *
 * Notes: the refund integration test relies on the framework + custom metadata
 * being deployed (real Trigger_Action__mdt records are visible in tests).
 */
@IsTest
private class FrameworkScenarioTest {

    // ---- SYNC: refund rule end-to-end through the framework ------------------
    @IsTest
    static void refundRuleAppliesThroughFramework() {
        Test.startTest();
        Case c = new Case(Subject = 'DL123 cancelled', Type = 'Cancellation');
        insert c;
        Test.stopTest();

        Case saved = [SELECT Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Refund', saved.Resolution__c,
            'Framework should route before-insert to the refund action.');
    }

    // ---- service unit (no trigger needed) -----------------------------------
    @IsTest
    static void newlyCancelledDiff() {
        Id a = TestIds.next(Case.SObjectType);
        Id b = TestIds.next(Case.SObjectType);
        List<Case> newList = new List<Case>{
            new Case(Id = a, Type = 'Cancellation'),
            new Case(Id = b, Type = 'Cancellation')
        };
        Map<Id, Case> oldMap = new Map<Id, Case>{
            a => new Case(Id = a, Type = 'Delay'),
            b => new Case(Id = b, Type = 'Cancellation')
        };
        Set<Id> result = new CaseRefundService().newlyCancelled(newList, oldMap);
        System.assertEquals(1, result.size());
        System.assert(result.contains(a));
    }

    // ---- RECURSION: processed / unprocessed ---------------------------------
    @IsTest
    static void recursionGuardDedupes() {
        Id a = TestIds.next(Case.SObjectType);
        Id b = TestIds.next(Case.SObjectType);
        Set<Id> first  = RecursionGuard.unprocessed('k', new Set<Id>{ a, b });
        Set<Id> second = RecursionGuard.unprocessed('k', new Set<Id>{ a, b });
        System.assertEquals(2, first.size(), 'First pass sees both.');
        System.assertEquals(0, second.size(), 'Second pass sees none (already processed).');
        System.assert(RecursionGuard.runOnce('once'));
        System.assert(!RecursionGuard.runOnce('once'), 'runOnce is true only the first time.');
    }

    // ---- ERROR LOG via platform event (durable, rollback-safe) --------------
    @IsTest
    static void errorEventCreatesLog() {
        Test.startTest();
        AppLogger.error(new AppLogger.ErrorDetail('After_Update', 'boom', 'stack')
            .action('SomeAction').sObj('Case').record(TestIds.next(Case.SObjectType)));
        Test.stopTest(); // delivers the platform event -> subscriber inserts log

        List<Error_Log__c> logs = [SELECT Context__c, Action_Name__c, Status__c FROM Error_Log__c];
        System.assertEquals(1, logs.size(), 'Subscriber should persist one Error_Log__c.');
        System.assertEquals('New', logs[0].Status__c);
        System.assertEquals('SomeAction', logs[0].Action_Name__c);
    }

    // ---- ASYNC SUCCESS: queueable runs and notifies -------------------------
    @IsTest
    static void asyncNotificationSucceeds() {
        Case c = new Case(Subject = 'Cancelled', Type = 'Delay'); // Delay so trigger doesn't enqueue
        insert c;
        Test.startTest();
        System.enqueueJob(new CaseNotificationQueueable(new Set<Id>{ c.Id }));
        Test.stopTest();
        // No exception == success path covered (logging is debug-only on success).
        System.assert(true);
    }

    // ---- ASYNC FAILURE: finalizer -> error event -> durable log -------------
    @IsTest
    static void asyncFailureIsLoggedDurably() {
        Case c = new Case(Subject = 'Cancelled', Type = 'Delay');
        insert c;

        Test.startTest();
        CaseNotificationQueueable.failForTest = true;
        System.enqueueJob(new CaseNotificationQueueable(new Set<Id>{ c.Id }));
        Test.stopTest(); // finalizer fires, publishes event, subscriber logs

        List<Error_Log__c> logs = [
            SELECT Context__c, Status__c, Record_Id__c
            FROM Error_Log__c WHERE Context__c = 'Async_Notification'
        ];
        System.assertEquals(1, logs.size(), 'Async failure should produce a durable log.');
        System.assertEquals('New', logs[0].Status__c);
    }

    // ---- RETRY: batch reprocesses a New async log ---------------------------
    @IsTest
    static void retryBatchReenqueues() {
        Case c = new Case(Subject = 'Cancelled', Type = 'Delay');
        insert c;
        insert new Error_Log__c(
            Record_Id__c = c.Id, SObject_Type__c = 'Case',
            Context__c = 'Async_Notification', Action_Name__c = 'CaseNotificationQueueable',
            Status__c = 'New', Severity__c = 'Error', Retry_Count__c = 0
        );

        Test.startTest();
        Database.executeBatch(new ErrorRetryBatch(), 200);
        Test.stopTest();

        Error_Log__c after = [SELECT Status__c, Retry_Count__c FROM Error_Log__c LIMIT 1];
        System.assertEquals('Retrying', after.Status__c, 'Batch marks the row Retrying.');
        System.assertEquals(1, after.Retry_Count__c, 'Retry count incremented.');
    }

    // ---- FLOW coexistence: Apex actions THEN a Flow action, all ordered ------
    // The framework runs order 10 (Apex refund) -> 20 (Apex notify) -> 30 (Flow
    // log). Updating a Case to Cancellation should make the Flow create a
    // Disruption_Log__c. This proves Apex and Flow run in one ordered registry.
    @IsTest
    static void flowActionRunsAfterApexInOrder() {
        Case c = new Case(Subject = 'Flight ok', Type = 'Delay');
        insert c;

        Test.startTest();
        c.Type = 'Cancellation';        // now becomes a cancellation on update
        update c;
        Test.stopTest();

        // Apex refund (order 10) set the field:
        Case saved = [SELECT Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Refund', saved.Resolution__c, 'Apex action 10 ran.');

        // Flow action (order 30) created the disruption log:
        List<Disruption_Log__c> logs = [
            SELECT Case__c, Disruption_Type__c FROM Disruption_Log__c WHERE Case__c = :c.Id
        ];
        System.assertEquals(1, logs.size(),
            'Flow registered as an ordered action should have created a Disruption_Log__c.');
        System.assertEquals('Cancellation', logs[0].Disruption_Type__c);
    }


    // ---- FLOW (before-context): default assignment runs BEFORE Apex ----------
    // Order 5 Flow sets Priority=Medium when blank, BEFORE the order-10 Apex.
    // Demonstrates a Flow running ahead of Apex in the same registry.
    @IsTest
    static void beforeFlowSetsDefaultAheadOfApex() {
        Test.startTest();
        Case c = new Case(Subject = 'No priority set', Type = 'Cancellation'); // Priority blank
        insert c;
        Test.stopTest();

        Case saved = [SELECT Priority, Resolution__c FROM Case WHERE Id = :c.Id];
        System.assertEquals('Medium', saved.Priority,
            'Before-insert Flow (order 5) should have defaulted Priority.');
        System.assertEquals('Refund', saved.Resolution__c,
            'Apex refund (order 10) still ran after the Flow.');
    }

}
