# Design decisions

This document records *why* the framework is shaped the way it is. The `README`
covers what it is and how to use it; this covers the forks that were considered
and the reasoning behind each choice, so the design can be extended without
re-litigating settled questions.

Each entry is **Context → Decision → Why → Tradeoff**.

---

## 1. TAF as the dispatcher, a layered architecture on top

**Context.** Trigger logic needs ordering, bypass, and recursion control. These
are solved problems; reinventing them is waste.

**Decision.** Use Mitch Spano's Trigger Actions Framework (TAF) for Lane 1 —
the single entry point, the ordered `Trigger_Action__mdt` registry, and the
`sObject_Trigger_Setting__mdt` binding — unmodified. Everything else (adapters,
services, data access, async tail, error pipeline) is layered above it.

**Why.** TAF decides *what runs and in what order*. It has no opinion on how
logic is structured, what happens after commit, or what happens on failure —
which is exactly the space this framework fills. Keeping TAF unmodified means
upstream fixes can be pulled in cleanly.

**Tradeoff.** A consumer must understand two metadata models (TAF's action
registry plus this framework's `Async_Work__mdt`). Accepted: the alternative is
maintaining a fork of a dispatcher.

---

## 2. Register work, don't enqueue from the action

**Context.** The original notification design enqueued a Queueable directly from
an after-trigger action. That action carried two `warn`-and-return branches: one
when running in an async context, one when the queueable limit was reached. Both
**silently dropped** the notification outside the durable error pipeline.

**Decision.** Services no longer enqueue. They **register** record Ids under a
work key in `AsyncWorkBuffer`. A single end-of-transaction dispatcher drains the
buffer and enqueues.

**Why.** Enqueuing from an after-action fires once per DML pass and forces every
caller to re-implement dedup, limit handling, and overflow routing — and the
silent branches were the proof that this gets done wrong. Centralising dispatch
puts the once-per-transaction enqueue, the overflow handling, and the durable
error routing in exactly one place.

**Tradeoff.** Dispatch now depends on a finalizer being registered (see
decision 6's silent-failure note). Accepted: the failure is a one-time config
check, not a recurring per-service risk.

---

## 3. Dispatch idempotency is structural, not a guard call

**Context.** The same Case can be registered for notification multiple times in
one transaction (after-insert plus a cascading after-update). Something must
ensure it's only notified once.

**Decision.** Back the buffer with `Map<String, Set<Id>>`. Registering the same
Id repeatedly collapses to one entry by `Set` semantics. `RecursionGuard` stays
in the toolkit but its job is narrowed to skipping *expensive recomputation* in a
service — it is **not** the dispatch-dedup mechanism.

**Why.** A framework's guarantees must not depend on every contributor
remembering to call a guard with the right key. A `Set` makes idempotency a
property of the data structure — impossible to get wrong.

**Tradeoff.** This covers *within-transaction* dedup only. Idempotency across
*retries* is a separate, still-open problem (see Limitations).

---

## 4. Key → factory registry (option A), not self-describing work items

**Context.** The dispatcher needs to turn a drained `Set<Id>` into a Queueable.
Two shapes were considered:
- **(A) Key → factory registry:** services register Ids under a string key; an
  `Async_Work__mdt` record maps the key to a factory class.
- **(B) Self-describing work items:** services register an object that knows how
  to build its own job; no registry.

**Decision.** Option A.

**Why.** A is consistent with the framework's metadata-driven grain (it already
uses `Trigger_Action__mdt`, `DML_Finalizer__mdt`), and it lets an admin swap an
implementation without a code deploy.

**Tradeoff — stated plainly.** A introduces a second silent-failure surface: a
key registered in the buffer with no matching `Async_Work__mdt` record. Option B
would not have this. The tradeoff is mitigated — *not eliminated* — by making the
dispatcher log loudly (`AppLogger.error`, Context `Async_Dispatch`) when a key
has no factory, rather than no-op. B remains a reasonable alternative for a
code-first team; the switch would be localized to the dispatcher.

---

## 5. The DML Finalizer is the flush hook — and can't do DML

**Context.** Something must run *once*, after the entire trigger cascade has
unwound, to drain the buffer and enqueue. Reinventing "end of transaction"
detection is wasteful — TAF's `TriggerBase` already tracks it.

**Decision.** Implement `AsyncDispatcher` as a `TriggerAction.DmlFinalizer`,
registered via one `DML_Finalizer__mdt` record. TAF fires it from
`finalizeDmlOperation()` when `contextStack` is empty and `rowsLeftToProcess`
is zero.

**Why.** It reuses TAF's already-correct cascade-end detection. The finalizer's
no-DML rule (enforced by `FinalizerHandler` measuring `Limits.getDmlStatements()`
before and after) is a *feature*: it structurally prevents starting a new trigger
cascade after the framework declared the old one finished.

**Key enabling fact (verified in-org).** `EventBus.publish()` consumes **zero**
DML statements. This was confirmed with anonymous Apex before relying on it. It
means the dispatcher can publish an `Error_Event__e` from inside the finalizer
(for the overflow path) without tripping the no-DML guard — so the
"couldn't enqueue → durable log" path can fire synchronously at flush time.

**Tradeoff.** The finalizer can enqueue and publish but cannot write records, so
it is a dispatch hook only — never a place for business DML.

---

## 6. Errors go through a platform event, not a direct insert

**Context.** A failure caught in a `catch` block that does `insert Error_Log__c`
rolls back *with* the failed transaction. The error vanishes.

**Decision.** `AppLogger.error` publishes `Error_Event__e` (a `PublishImmediately`
platform event). `LogErrorEventTrigger` subscribes and writes the durable
`Error_Log__c` in its **own** transaction. `ErrorRetryBatch` re-runs `New` work,
capped at 3.

**Why.** Platform events survive rollback. The indirection is the entire point —
it's what makes the log durable when the originating transaction fails.

**The one silent-failure mode.** This framework's promise is "nothing is silently
dropped," with exactly one exception, and it is a **config dependency, not a code
path**: if the `DML_Finalizer__mdt` → `AsyncDispatcher` record does not exist, the
buffer is never drained and deferred work silently vanishes — nothing runs the
finalizer, so nothing can log. By contrast, the `Async_Work__mdt` factory record
fails *loudly* if missing. Deploys must verify the finalizer record exists; the
integration test asserts it as a precondition.

---

## 7. One generic dispatcher, not an object-specific one

**Context.** For a single object, an object-specific finalizer is simpler. For a
publishable, multi-object framework, it isn't.

**Decision.** One generic `AsyncDispatcher` and one generic `Async_Work__mdt`
registry serve every object. Object-specific knowledge (which Queueable to build)
lives in small per-key factory classes.

**Why.** The dispatcher *is* the framework's contribution; a dispatcher that only
works for Case isn't a framework. A generic one needs a "unit of deferred work"
abstraction (`AsyncWorkFactory`), which is worth the upfront design for reuse.

**Tradeoff.** More indirection than a one-object solution would need. Justified
only because reuse is the goal — for a single object it would be over-engineering.

---

## 8. The lane split exists for the testability boundary

**Context.** Logic could live directly in trigger handlers.

**Decision.** Thin adapters (Lane 2) unpack the trigger payload and call services
(Lane 3); services hold the rules.

**Why.** The value isn't the lanes themselves — it's that business logic is
unit-testable *without constructing a trigger context*. A service test builds
lists by hand and asserts on the result; no DML, no metadata, no trigger.

**Tradeoff.** One extra hop (adapter → service) per action. Cheap, and it pays
for itself the first time a rule is tested in isolation.

---

## Known limitations (open, tracked)

1. **`ErrorRetryBatch` is queueable-specific.** It re-enqueues the Case queueable
   by name. Correct for the only registered key today; before a second work key
   is added it must be generalized to re-resolve the factory from
   `Async_Work__mdt` by `Work_Key__c` (carried in `Action_Name__c` on the log).
2. **Cross-transaction retry idempotency.** The within-transaction `Set`/recursion
   dedup resets between transactions. A half-succeeded job that retries could
   double-fire its side effect. The work item itself must be made idempotent;
   this is a design item, not a mechanical fix.
