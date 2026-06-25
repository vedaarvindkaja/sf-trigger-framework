# Async Dispatch Delta — `sf-architect-prep`

Replaces the scattered `enqueueJob` design with a single, generic,
end-of-transaction async dispatcher (option A: **key → factory registry**).

> **Status: deployed and tested.** 17/17 Apex tests pass. The three dry-run
> watch-points (`System.Comparator<String>`, `new FinalizerHandler.Context()`,
> CMDT relationship value format) all compiled and ran clean.

---

## What it does

During the synchronous phase, services **register** record Ids under a string
work key in `AsyncWorkBuffer` (a `Map<String, Set<Id>>`) instead of enqueuing.
At end of transaction, the single `AsyncDispatcher` (`TriggerAction.DmlFinalizer`)
drains the buffer, resolves each key's factory from `Async_Work__mdt`, and
enqueues the job once.

Dispatch idempotency is **structural** (the buffer's `Set` collapses duplicates
across cascade passes). Nothing is silently dropped:
- A pending key with **no factory mapping** → `AppLogger.error` (Context
  `Async_Dispatch`), surfaced in `Error_Log__c`. Not auto-retried (config error;
  a human must add the record).
- **Queueable limit reached** → routed to the durable pipeline (Context
  `Async_Notification`) so `ErrorRetryBatch` recovers it.

No DML occurs in the finalizer: `getAll()`, `Type.forName`, `System.enqueueJob`,
and `EventBus.publish` (inside `AppLogger`) all leave `Limits.getDmlStatements()`
untouched, satisfying the `FinalizerHandler` no-DML guard.

---

## What changed

**New (framework, generic):**
- `AsyncWorkBuffer` — transaction-scoped `Map<String, Set<Id>>` accumulator.
- `AsyncWorkFactory` — the key→factory contract: `Queueable build(Set<Id>)`.
- `AsyncDispatcher` — the single `DmlFinalizer`; drain → resolve → enqueue, with
  loud-on-missing-factory and overflow-to-durable-log.
- `Async_Work__mdt` — registry type (`Work_Key__c` unique, `Factory_Class_Name__c`,
  `Order__c`, `Bypass_Execution__c`).

**New (Case demo):**
- `CaseNotificationWorkFactory` — maps `CaseNotify` → `CaseNotificationQueueable`.
- `Case_PreventDeleteIfClosed` — before-delete demo (blocks deleting closed Cases).
- `Case_AfterDelete_Audit` — after-delete demo (audit log per delete).

**Modified:**
- `CaseNotificationService.notifyDisruption()` — now **registers** into the buffer.
  The two silent `warn`-and-return branches (async-context skip, queueable-limit
  skip) are gone; overflow is the dispatcher's job and routes to the durable log.
- `CaseNotificationQueueable` — added `@TestVisible finalizerCalled` flag, set
  inside the finalizer body (see Testing notes).

**Tests:** `AsyncWorkBufferTest`, `AsyncDispatcherTest`, `AsyncDispatchIntegrationTest`.

**Not touched (already in the repo):** `AppLogger`, `Error_Event__e`, `Error_Log__c`,
`LogErrorEventTrigger`, `ErrorRetryBatch`, `RecursionGuard`, `CaseRefundService`,
`CaseSelector`, `UnitOfWork`, the adapters, `CaseTrigger`, and TAF. The adapters
still call `notifier.notifyDisruption(ids)` — only the service body changed.

---

## Deploy order

1. **Deploy source:** `SFDX: Deploy Source to Org` on `force-app` (pushes classes
   + the `Async_Work__mdt` type; does **not** create CMDT records).
2. **Hand-create the CMDT records** (Setup → Custom Metadata Types → Manage
   Records), per the org's CMDT deploy quirk:

   | Type | Record | Field values |
   |---|---|---|
   | `DML_Finalizer__mdt` | Async Dispatcher | `Apex_Class_Name__c=AsyncDispatcher`, `Order__c=10`, `Bypass_Execution__c=false` |
   | `Async_Work__mdt` | Case Notify | `Work_Key__c=CaseNotify`, `Factory_Class_Name__c=CaseNotificationWorkFactory`, `Order__c=10`, `Bypass_Execution__c=false` |
   | `Trigger_Action__mdt` | Case Prevent Delete If Closed (BD) | `Before_Delete__c=Case`, `Apex_Class_Name__c=Case_PreventDeleteIfClosed`, `Order__c=10` |
   | `Trigger_Action__mdt` | Case After Delete Audit (AD) | `After_Delete__c=Case`, `Apex_Class_Name__c=Case_AfterDelete_Audit`, `Order__c=20` |

3. **Verify the wiring** (anonymous Apex; both must return one row):
   ```apex
   System.debug([SELECT Apex_Class_Name__c FROM DML_Finalizer__mdt WHERE Apex_Class_Name__c = 'AsyncDispatcher']);
   System.debug([SELECT Work_Key__c, Factory_Class_Name__c FROM Async_Work__mdt WHERE Work_Key__c = 'CaseNotify']);
   ```
4. **Run tests:** `AsyncWorkBufferTest`, `AsyncDispatcherTest`,
   `AsyncDispatchIntegrationTest`, `FrameworkScenarioTest`.

---

## The one silent failure mode

The framework's promise is "nothing is silently dropped." There is exactly one
exception, and it is a **config dependency, not a code path**, so code cannot
self-report it:

> If the `DML_Finalizer__mdt` → `AsyncDispatcher` record does not exist, the buffer
> is never drained and every notification silently vanishes. Nothing runs the
> finalizer, so nothing can log.

The `Async_Work__mdt` → `CaseNotify` record, by contrast, fails **loudly** if
missing (an `Async_Dispatch` error per record). Always run the step-3 verification
after deploy. `AsyncDispatchIntegrationTest` also asserts the `DML_Finalizer`
record exists as a precondition.

---

## Testing notes — read before changing the failure-path tests

**Platform events published from inside a `System.Finalizer` are NOT delivered
within the same `Test.stopTest()` window.** (Events published from direct test
code *are* — that's why `errorEventCreatesLog` works.) This is a test-harness
limitation, not a defect: in production the event delivers on its own transaction
and the chain is unbroken.

Because of this, no **single** test asserts the literal end-to-end
"Finalizer publishes → subscriber writes `Error_Log__c`" hop. The failure-path
tests prove it in **two observable pieces**:

1. **Finalizer ran** — `CaseNotificationQueueable.finalizerCalled` (`@TestVisible`),
   set inside the finalizer's `execute()`, asserted by
   `FrameworkScenarioTest.asyncFailureIsLoggedDurably` and
   `AsyncDispatchIntegrationTest.cancellationFlowsThroughDispatcherToQueueable`.
2. **Event → `Error_Log__c`** — `errorEventCreatesLog` publishes `Error_Event__e`
   directly and asserts the durable log.

Two further harness accommodations in those tests:
- `Test.stopTest()` is wrapped in `try/catch` asserting a `threw` flag, because
  the forced `CalloutException` (`failForTest = true`) propagates out of
  `stopTest()` in test context only.
- `AsyncDispatchIntegrationTest` keeps the `AsyncWorkBuffer.isEmpty()` assertion
  after the insert — that is the proof the **dispatcher** drained the buffer (i.e.
  the `DML_Finalizer` fired), which is the point of that test.

Production behaves as one continuous chain; only the **test coverage** is
segmented, due to the harness.

---

## Known follow-ups (not in this delta)

1. **Generalize `ErrorRetryBatch`.** It re-enqueues `CaseNotificationQueueable` by
   name. Correct for `CaseNotify` today; before a **second** work key is added,
   make it re-resolve the factory from `Async_Work__mdt` by `Work_Key__c` (carried
   in `Action_Name__c` on the log). Until then, overflow-retry is correct only for
   `CaseNotify`.
2. **Cross-transaction retry idempotency.** `ErrorRetryBatch` re-runs failed work,
   but the in-transaction buffer/`RecursionGuard` dedup resets between
   transactions. If a notification half-succeeds then retries, nothing yet
   guarantees the side effect won't double-fire. Open design item.
