# CHANGES — Lane 1 swap + error-logging + retry

Read `docs/Trigger_Framework_Architecture.docx` for the full write-up. Quick index:

## Deleted (framework replaces)
- `MetadataTriggerHandler.cls`, `TriggerAction.cls` — your dispatcher + interfaces
- `objects/Trigger_Action__mdt/` — your CMDT object
- 4 old `Trigger_Action.Case_*` customMetadata rows
- `MetadataTriggerHandlerTest.cls` — tested deleted handler
- `TriggerContext.cls` — framework passes raw lists; no longer used
- your bypass logic — framework bypass is a superset

## Edited
- `Case_SetRefundOnCancellation.cls`, `Case_DisruptionNotification.cls` — interface signatures now take raw lists; catch blocks log durably + re-throw
- `CaseSelector.cls` — dropped TriggerContext param; static transaction cache
- `CaseNotificationQueueable.cls` — finalizer logs durably; `failForTest` hook
- `AppLogger.cls` — error path now publishes `Error_Event__e` (rollback-safe)
- `sfdx-project.json` — registers `trigger-actions-framework` package dir

## New
- `objects/Error_Log__c/` — durable, queryable failure log
- `objects/Error_Event__e/` — platform event (PublishImmediately) for rollback-safety
- `triggers/LogErrorEventTrigger.trigger` — subscriber that writes Error_Log__c
- `classes/ErrorRetryBatch.cls` — re-enqueues failed async work, capped
- `classes/FrameworkScenarioTest.cls` — all scenarios (sync/async/recursion/error/retry)
- `customMetadata/` — framework-format records: 1 sObject setting + 2 actions

## Kept unchanged
- `CaseRefundService`, `CaseNotificationService`, `UnitOfWork`, `RecursionGuard`,
  `CaseRefundServiceTest`, `TestIds`, `CaseTrigger` (entry line already matched)

## Why RecursionGuard survived (but bypass didn't)
Source review: the framework's recursion prevention is Flow-only
(`Allow_Flow_Recursion__c`). It has NO Apex record-level dedup, so
`RecursionGuard.unprocessed()` has no equivalent and stays. Bypass, by contrast,
is a strict superset in the framework, so yours was removed.

## Deploy
    sf project deploy start --source-dir trigger-actions-framework --source-dir force-app --dry-run
    sf project deploy start --source-dir trigger-actions-framework --source-dir force-app
    sf apex run test --class-names FrameworkScenarioTest CaseRefundServiceTest --result-format human --wait 10

## Caveats
- Not yet compiled against an org — dry-run is the first real compile.
- Metadata-relationship value format (context field -> "Case") is the most likely
  thing to need a tweak; confirm on dry-run.

## Flow coexistence example (added)
- `flows/Case_AfterUpdate_LogDisruption.flow-meta.xml` — autolaunched Flow,
  registered as an ordered action (order 30, after update). Runs AFTER the Apex
  refund (10) and notification (20) — proves Apex + Flow in one ordered registry.
- `objects/Disruption_Log__c/` — the object the Flow writes to.
- `customMetadata/Trigger_Action.Case_Log_Disruption_Flow.md-meta.xml` — registers
  the Flow via `Flow_Name__c` (not `Apex_Class_Name__c`).
- Flow contract: input variable MUST be named `record`, type Case, input+output.
- Flow error handling: the create's fault path publishes the SAME `Error_Event__e`
  platform event the Apex side uses (because a Flow action runs inside the trigger
  transaction; a direct insert would roll back). LogErrorEventTrigger then writes
  the Error_Log__c. One error pipeline for both Apex and Flow.
- `FrameworkScenarioTest.flowActionRunsAfterApexInOrder` — asserts the Flow created
  a Disruption_Log__c when a Case is updated to Cancellation.

## Before-context Flow example (added)
- `flows/Case_BeforeInsert_SetDefaults.flow-meta.xml` — autolaunched Flow at
  order 5, BEFORE the Apex. Sets Priority=Medium when blank (default assignment),
  no DML — the framework writes the `record` variable back. Runs BEFORE Apex(10).
- `customMetadata/Trigger_Action.Case_Set_Defaults_Flow.md-meta.xml` — registers it.
- Now demonstrates BOTH directions in one registry:
    order 5  Flow  (before insert)  -> runs BEFORE Apex
    order 10 Apex  (before ins/upd)
    order 20 Apex  (after ins/upd)
    order 30 Flow  (after update)   -> runs AFTER Apex
- Why a Flow can run after Apex: normally a record-triggered Flow always runs
  before Apex (platform rule). Registering it as a Trigger Action lets the
  framework invoke it in any order/context you choose — including after Apex.
- `FrameworkScenarioTest.beforeFlowSetsDefaultAheadOfApex` — asserts Priority
  defaulted by the Flow AND the Apex refund still ran.

## Note on Disruption_Log__c
Demo scaffolding only — gives the after-update Flow real work to do and the test
something to assert on. Not part of the framework; delete it and swap in the
Flow's real job (email/Chatter/related-record/approval) if you don't need it.

## Doc update: "one Flow per object" question
- Added section 10 "One Flow per object? — it's one registry per object".
- Explains: one-trigger-per-object is a hard platform constraint (undefined
  multi-trigger order); Flows don't share it because each Flow action has an
  explicit Order__c. The equivalent of "one trigger per object" for visibility is
  ONE REGISTRY per object — the sObject_Trigger_Setting__mdt record lists every
  Apex + Flow action with order/context. Forcing one mega-Flow per object recreates
  the god-class anti-pattern; the "one entry Flow + subflows" convention is a style
  choice with real costs. Recommendation: keep many small ordered actions.
- Sections renumbered: best practices (11), deploy (12), file index (13).

## Added: docs/FRAMEWORK_UPGRADE_GUIDE.md
How to pull new versions of the Trigger Actions Framework safely:
- the vendored-package setup (their folder, unmodified) that makes upgrades a
  clean re-copy; the rule never to edit their folder
- WHEN to upgrade (specific need, calm window) vs wait; pre-1.0 = treat every
  upgrade as potentially breaking, read release notes
- procedure: pin a tag -> read notes -> robocopy /E /PURGE -> git status ->
  dry-run -> tests -> commit
- recovery: interface/metadata fixes; git rollback to the committed baseline
- what an upgrade never touches (your Lanes 2-5) vs what it may (thin adapters)
