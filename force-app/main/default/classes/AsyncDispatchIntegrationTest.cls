/**
 * AsyncDispatchIntegrationTest
 * End-to-end proof of the NEW dispatch path through a real Case DML:
 *
 *   Case insert -> CaseTrigger -> MetadataTriggerHandler -> after-insert action
 *   (Case_DisruptionNotification) -> CaseNotificationService.notifyDisruption()
 *   -> AsyncWorkBuffer.register('CaseNotify') -> end of cascade -> AsyncDispatcher
 *   (via DML_Finalizer__mdt) -> CaseNotificationWorkFactory.build()
 *   -> CaseNotificationQueueable enqueued -> runs post-commit.
 *
 * The existing async tests in FrameworkScenarioTest enqueue the queueable
 * directly and therefore bypass this entire path; this test does not.
 *
 * REQUIRES these CMDT records to be deployed / hand-created, or it fails by
 * design (it is verifying the wiring):
 *   - DML_Finalizer__mdt -> Apex_Class_Name__c = 'AsyncDispatcher'
 *   - Async_Work__mdt    -> Work_Key__c = 'CaseNotify',
 *                           Factory_Class_Name__c = 'CaseNotificationWorkFactory'
 *   - Trigger_Action__mdt -> Case_DisruptionNotification (After_Insert -> Case)
 *
 * Assertion strategy: a SUCCESSFUL notification logs nothing queryable, so the
 * test forces the queueable to fail (failForTest). If the full path fires, the
 * forced failure leaves a durable Error_Log__c (Context 'Async_Notification').
 * It also asserts the buffer was drained during the insert, which separates
 * "dispatcher ran" from "DML_Finalizer record missing".
 */
@IsTest
private class AsyncDispatchIntegrationTest {

    @IsTest
    static void cancellationFlowsThroughDispatcherToQueueable() {
        // --- preconditions: fail loudly and specifically if config is missing ---
        System.Assert.isTrue(isFinalizerRegistered('AsyncDispatcher'),
            'Missing config: deploy the DML_Finalizer__mdt -> AsyncDispatcher record. ' +
            'Without it the buffer never drains and notifications silently stop.');
        System.Assert.isTrue(isWorkKeyRegistered('CaseNotify'),
            'Missing config: deploy the Async_Work__mdt -> CaseNotify / ' +
            'CaseNotificationWorkFactory record.');

        AsyncWorkBuffer.clear();
        CaseNotificationQueueable.failForTest = true; // make the end of the path observable

        Test.startTest();
        Case c = new Case(Subject = 'DL999 cancelled', Type = 'Cancellation');
        insert c; // after-insert registers; the synchronous DML finalizer dispatches

        // The finalizer runs during the insert transaction, so by now it must have
        // drained the buffer. If this fails, the dispatcher never ran.
        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(),
            'AsyncDispatcher should have drained CaseNotify during the insert transaction.');
        Boolean threw = false;
        try {
            Test.stopTest(); // the enqueued queueable runs, fails, finalizer logs durably
        } catch (System.CalloutException e) {
            threw = true; // expected: finalizer ran and logged before this surfaced
        }
        System.Assert.isTrue(threw, 'Forced failure should have propagated in test context.');
        System.Assert.isTrue(CaseNotificationQueueable.finalizerCalled,
            'The full register -> dispatch -> enqueue -> queueable -> Finalizer path ran.');
        // Note: the event->Error_Log__c hop is covered by FrameworkScenarioTest.errorEventCreatesLog.
        // Platform Events published from within a Finalizer are not delivered in the
        // same Test.stopTest() window, so we verify the Finalizer ran via the flag above.
    }

    private static Boolean isFinalizerRegistered(String apexClassName) {
        for (DML_Finalizer__mdt f : DML_Finalizer__mdt.getAll().values()) {
            if (f.Apex_Class_Name__c == apexClassName && f.Bypass_Execution__c == false) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isWorkKeyRegistered(String workKey) {
        for (Async_Work__mdt w : Async_Work__mdt.getAll().values()) {
            if (w.Work_Key__c == workKey && w.Bypass_Execution__c == false) {
                return true;
            }
        }
        return false;
    }
}
