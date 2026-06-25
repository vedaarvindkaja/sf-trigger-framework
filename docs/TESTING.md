# Testing

How the framework is tested, the seams that make it testable, and the Apex
test-harness quirks a contributor will otherwise trip on. Read the last section
before writing any test that involves the async tail.

---

## Test layers

**Primitive unit tests** — `AsyncWorkBufferTest`, and the existing
`RecursionGuard` coverage. Pure in-memory, no DML. They prove the `Set`-dedup and
drain semantics in isolation.

**Dispatcher unit tests** — `AsyncDispatcherTest`. Exercises the dispatcher with
an *injected* registry (no deployed metadata required): happy path, loud-on-
missing-factory, bypass, and the queueable-limit overflow. This is where the
durability guarantees are asserted directly.

**Integration test** — `AsyncDispatchIntegrationTest`. Drives a real Case DML
through the whole path (trigger → after-action → register → finalizer →
dispatcher → queueable) and proves the wiring end to end. Depends on deployed
CMDT records (see below).

**Scenario tests** — `FrameworkScenarioTest` walks the user-visible behaviours:
the refund rule through the framework, Flow/Apex ordering coexistence, the diff,
recursion dedup, and the error pipeline.

---

## Test seams

The framework exposes four `@TestVisible` seams. Each exists because the thing it
controls cannot be driven from a test any other way.

| Seam | Class | Purpose |
|---|---|---|
| `registryOverride` | `AsyncDispatcher` | Inject an `Async_Work__mdt` map so dispatcher tests don't need deployed records. |
| `forceQueueableLimitForTest` | `AsyncDispatcher` | Force the queueable-limit overflow branch — `Limits.getQueueableJobs()` cannot be driven to the cap. Gated by `Test.isRunningTest()`, so it is inert in production. |
| `failForTest` | `CaseNotificationQueueable` | Force the job to throw, so the failure path is observable. |
| `finalizerCalled` | `CaseNotificationQueueable` | Records that the job's `System.Finalizer` ran. Asserted in place of an `Error_Log__c` count where the harness can't deliver the event in time (see below). |

CMDT instances can be **constructed** in memory in a test
(`new Async_Work__mdt(Work_Key__c = ...)`) even though they can't be *inserted* —
that is what makes `registryOverride` work.

Use `TestIds.next(SObjectType)` to generate fake Ids without DML.

---

## The harness quirk you must know

**Platform events published from inside a `System.Finalizer` are not delivered
within the same `Test.stopTest()` window.** Events published from *direct test
code* are delivered (that is why the error-event-to-log test passes). This is a
limitation of the Apex test harness, not a defect — in production the event
delivers on its own transaction and the chain is unbroken.

The consequence: a single test **cannot** assert the literal end-to-end
"Finalizer publishes → subscriber writes `Error_Log__c`" hop. The failure path is
therefore proven in **two observable pieces**:

1. **The Finalizer ran** — assert `CaseNotificationQueueable.finalizerCalled`.
   The flag is set *inside the finalizer's `execute()`*, after the failure path —
   so it proves the finalizer ran, not merely that the job started.
2. **Event → `Error_Log__c`** — a separate test publishes `Error_Event__e`
   directly and asserts the durable log.

Production is one continuous chain; only the test coverage is segmented.

### Writing a new async-failure test

Two accommodations are required, and both are deliberate:

- Wrap `Test.stopTest()` in `try/catch` and assert a `threw` flag. The forced
  `CalloutException` (`failForTest = true`) propagates out of `stopTest()` in test
  context only; without the catch it aborts the method before your assertions.
- Assert `finalizerCalled` (and, for integration, `AsyncWorkBuffer.isEmpty()` —
  that proves the *dispatcher* drained the buffer), **not** an `Error_Log__c`
  count, for any log that originates from a finalizer.

```apex
Boolean threw = false;
try {
    Test.stopTest();
} catch (System.CalloutException e) {
    threw = true; // finalizer ran and logged before this surfaced
}
System.Assert.isTrue(threw, 'Forced failure should propagate in test context.');
System.Assert.isTrue(CaseNotificationQueueable.finalizerCalled, 'Finalizer must run.');
```

---

## CMDT-dependent tests fail by design

`AsyncDispatchIntegrationTest` asserts the `DML_Finalizer__mdt` → `AsyncDispatcher`
and `Async_Work__mdt` → `CaseNotify` records exist as **preconditions**. If they
are not deployed, it fails with a specific, actionable message rather than a
confusing downstream failure. This is intentional — it is an integration test of
the wiring, and missing wiring should be a red test, not a false green. It is
consistent with `FrameworkScenarioTest`'s refund test, which already depends on
deployed `Trigger_Action__mdt` records.

If your CI runs before the CMDT records are hand-created, expect this test to be
red until they exist.

---

## What cannot be tested

`Limits.getQueueableJobs()` cannot be driven to the cap, so no test exercises the
*real* governor boundary — the overflow tests force the branch via the seam
instead. They prove the dispatcher publishes correctly *when it believes* the
limit is hit; they do not prove the limit trips at exactly the right count. That
last mile is only ever exercised by real load. This is an inherent Apex testing
limit, not a coverage gap that can be closed in code.
