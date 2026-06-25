# Salesforce Trigger Framework

A production trigger framework built on **Mitch Spano's [Trigger Actions
Framework](https://github.com/mitchspano/apex-trigger-actions-framework) (TAF)**
as the dispatcher, with a layered architecture, a transaction-scoped async
dispatcher, and a rollback-safe error pipeline on top.

TAF decides *what runs and in what order*. This framework decides *how logic is
structured, what happens after commit, and what happens when it fails.*

---

## Why this exists

A trigger handler that does logic inline, enqueues async work mid-transaction,
and swallows failures in a `catch` block is the default — and it loses work in
three ways: order is implicit, async enqueues fire per DML pass, and an `insert`
in a `catch` block rolls back with the failed transaction. This framework closes
all three:

- **Order and bypass are configuration** (TAF's metadata registry), not code.
- **Async work is registered, not enqueued** — collected in a buffer and
  dispatched **once** at end of transaction.
- **Failures survive rollback** — published as a platform event that lands in a
  durable, retryable log in its own transaction.

---

## The five lanes

| Lane | Pieces | Role |
|---|---|---|
| **1 — Dispatch** | `*Trigger`, `MetadataTriggerHandler` (+`TriggerBase`) — TAF | Single entry. Reads `Trigger_Action__mdt` joined to `sObject_Trigger_Setting__mdt`, orders by `Order__c`, routes. |
| **2 — Adapters** | thin `TriggerAction.*` classes | Unpack the raw `List<SObject>`, compute who's in scope, call a service. No business logic. |
| **3 — Services** | `*Service` classes | The actual rules. Unit-testable without a trigger. |
| **4 — Data access** | `*Selector`, `UnitOfWork` | Centralized SOQL and batched DML. |
| **5 — Async tail** | `AsyncWorkBuffer`, `AsyncWorkFactory`, `AsyncDispatcher`, `*Queueable`, `ErrorRetryBatch` | Register → drain → enqueue post-commit; retry failed work. |
| **x-cut** | `RecursionGuard`, `AppLogger`, `Error_Event__e`, `Error_Log__c`, `LogErrorEventTrigger` | Recursion control, logging, and the rollback-safe error pipeline. |

Lane 1 is TAF. Lanes 2–5 and the cross-cutting row are this framework.

---

## Project structure

```
sfdx-project.json                     # two package dirs, API 61.0
force-app/                            # this framework + Case demo
  main/default/
    classes/                         # adapters, services, async, x-cut, tests
    objects/Async_Work__mdt/         # the key→factory registry type
    customMetadata/                  # the wiring records (source-controlled)
    triggers/CaseTrigger.trigger     # one-line Lane 1 entry
trigger-actions-framework/           # TAF (Apache 2.0), unmodified
```

The `Case*` classes are a **worked example**, not part of the framework — they
demonstrate every feature (ordering, Flow coexistence, entry criteria, recursion,
async dispatch, the error pipeline) end to end.

---

## Quickstart

1. Deploy: `sf project deploy start -d force-app -d trigger-actions-framework`.
2. The custom-metadata **records** are source-controlled under
   `force-app/main/default/customMetadata/`. If your org has the CMDT-record
   deploy quirk, create them by hand from those files (Setup → Custom Metadata
   Types → Manage Records).
3. Verify the async dispatcher is registered (see *Gotcha* below).
4. Run the tests.

---

## How to: add the framework to a new object

1. Create a one-line trigger — the only per-object code:
   ```apex
   trigger AccountTrigger on Account (
       before insert, before update, before delete,
       after insert, after update, after delete, after undelete
   ) {
       new MetadataTriggerHandler().run();
   }
   ```
2. Create one `sObject_Trigger_Setting__mdt` record: `Object_API_Name__c = Account`
   (this is the binding the action registry joins to). Without it, **no actions
   fire and no error is thrown** — the join simply returns nothing.

## How to: add a synchronous action

1. Write a class implementing the context interface, e.g.:
   ```apex
   public inherited sharing class Account_SetRegion
       implements TriggerAction.BeforeInsert {
       public void beforeInsert(List<SObject> triggerNew) {
           for (Account a : (List<Account>) triggerNew) { /* ... */ }
       }
   }
   ```
   Keep it thin — delegate real logic to a `*Service` so it's testable without a
   trigger.
2. Create one `Trigger_Action__mdt` record: the context field (e.g.
   `Before_Insert__c`) = the object setting's name, `Apex_Class_Name__c` = your
   class, `Order__c` = its position. One record **per context** (the
   `Only_One_Context` rule enforces this — register the same class twice if it
   runs in two contexts).

Optional per-action controls: `Entry_Criteria__c` (a formula gate),
`Required_Permission__c` / `Bypass_Permission__c`, and `Bypass_Execution__c`.

## How to: defer async work (the distinctive part)

Never call `System.enqueueJob` from an action. Instead:

1. **Register** in your service — the buffer's `Set` makes this idempotent across
   cascade passes:
   ```apex
   AsyncWorkBuffer.register('AccountSync', accountIds);
   ```
2. **Write a factory** that builds the job:
   ```apex
   public inherited sharing class AccountSyncWorkFactory
       implements AsyncWorkFactory {
       public System.Queueable build(Set<Id> recordIds) {
           return new AccountSyncQueueable(recordIds);
       }
   }
   ```
3. **Register the key → factory** with one `Async_Work__mdt` record:
   `Work_Key__c = AccountSync`, `Factory_Class_Name__c = AccountSyncWorkFactory`.

At end of transaction, `AsyncDispatcher` drains the buffer, resolves each key's
factory, and enqueues **one** job per key. A key with no factory record is logged
loudly (never silently dropped); a queueable-limit overflow is routed to the
durable pipeline for retry.

> **Before adding a second work key**, generalize `ErrorRetryBatch` (see
> Limitations) — it currently re-enqueues the Case queueable by name.

---

## Error pipeline

Any failure should go through `AppLogger.error(...)`, which **publishes
`Error_Event__e`** (a platform event) rather than inserting a log directly.
Platform events survive rollback, so the failure is not lost with the
transaction. `LogErrorEventTrigger` subscribes and writes a durable `Error_Log__c`
in its own transaction (`Status__c = New`). `ErrorRetryBatch` re-runs `New`
async work, capped at 3 attempts.

`AppLogger` API: `info(area, msg)`, `warn(area, msg)`, `error(area, msg)`,
`error(area, Exception)`, and `error(ErrorDetail)` for full context
(`.action()`, `.record()`, `.sObj()`).

---

## ⚠️ The one silent failure mode

The framework's promise is "nothing is silently dropped." There is exactly one
exception, and it is a **config dependency, not a code path**:

> If the `DML_Finalizer__mdt` record pointing to `AsyncDispatcher` does not exist,
> the buffer is never drained and all deferred work silently vanishes — nothing
> runs the finalizer, so nothing can log.

Verify after every deploy:
```apex
System.debug([SELECT Apex_Class_Name__c FROM DML_Finalizer__mdt
              WHERE Apex_Class_Name__c = 'AsyncDispatcher']); // must return 1 row
```

---

## Testing notes

Platform events published from inside a `System.Finalizer` are **not delivered
within the same `Test.stopTest()` window** (events from direct test code are).
This is a harness limitation, not a defect — in production the chain is unbroken.
Because of it, the failure path is proven in two pieces: a `@TestVisible`
`finalizerCalled` flag (the finalizer ran) plus a separate test that publishes
`Error_Event__e` directly and asserts the log (event → `Error_Log__c`). See
`DELTA_README.md` for the full rationale.

---

## Known limitations

1. **`ErrorRetryBatch` is queueable-specific** — re-enqueues the Case queueable by
   name. Generalize it to re-resolve the factory from `Async_Work__mdt` by
   `Work_Key__c` before registering a second work key.
2. **Cross-transaction retry idempotency** — the in-transaction buffer/recursion
   dedup resets between transactions, so a half-succeeded job that retries could
   double-fire its side effect. Open design item; the work item must be made
   idempotent.

---

## Credits

Dispatch layer: **Trigger Actions Framework** by Mitch Spano, Apache License 2.0,
included unmodified under `trigger-actions-framework/`.
