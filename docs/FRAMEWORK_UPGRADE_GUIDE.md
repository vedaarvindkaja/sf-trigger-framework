# Upgrading the Trigger Actions Framework

How to pull new versions of the adopted framework safely, when to do it, and how
to recover if an upgrade breaks something. This is a deliberate, tested step —
**never an automatic one**.

---

## The setup you have (why upgrades are easy)

The framework lives in your repo as its **own package directory**, copied
unmodified from the upstream source:

```
sf-architect-prep/
├─ force-app/                    # YOUR code (Lanes 2–5) — you own this
└─ trigger-actions-framework/    # THEIR code — copied as-is, never edited
```

Both are registered in `sfdx-project.json`. Because you have **never edited**
anything inside `trigger-actions-framework/`, an upgrade is just "replace that
folder with the newer version." Nothing of yours is touched.

> **The one rule that makes this work:** never edit files inside
> `trigger-actions-framework/`. If you need different behaviour, do it in your own
> `force-app` code (a wrapper, a subclass, a different action), not by patching
> their source. The moment you edit their folder, upgrades stop being a clean
> copy and become a manual merge.

Current pinned version at time of writing: **0.3.x** (pre-1.0 — see warnings below).

---

## When to upgrade

Upgrade deliberately, for a reason — not on a schedule, and not "because there's
a new version."

**Good reasons to upgrade:**
- A bug you're actually hitting is fixed upstream.
- A feature you want has shipped (e.g. a new bypass mode, finalizer improvement).
- You're starting a new development cycle and want the current baseline before
  building more on top.

**Reasons to wait:**
- "There's a newer version" with no specific need — pre-1.0 releases can carry
  breaking changes; don't take the risk without a payoff.
- Mid-sprint, close to a release, or right before a deadline — upgrade in a calm
  window with time to test, never under pressure.

**Hard rule for pre-1.0 (0.x):** treat every upgrade as potentially breaking.
Semantic-versioning guarantees don't apply below 1.0, so a 0.3 → 0.4 jump can
change interfaces or metadata. Read the release notes first, every time.

---

## Before you upgrade: pin and record what you have

So you can always get back to a known-good state, record the exact version
you're on **before** changing anything.

1. Note the current version: open `trigger-actions-framework/` upstream and check
   `sfdx-project.json` → `versionNumber` (and the git commit/tag you pulled).
2. Make sure your repo is clean and committed:
   ```powershell
   git status            # should be clean
   git log --oneline -1  # note the commit you're on
   ```
3. Confirm your tests are green on the **current** version first. Never upgrade
   on top of an already-failing baseline — you won't know what the upgrade broke
   versus what was already broken.

---

## The upgrade procedure

Run from the project root (`D:\Projects\sf-architect-prep`).

### Step 1 — pull the new version to a temp location

Pin to a **specific tag or commit**, not "latest", so the pull is reproducible:

```powershell
# clone the version you intend to adopt (replace TAG with the release tag)
git clone --depth 1 --branch TAG https://github.com/mitchspano/trigger-actions-framework "$env:TEMP\taf-new"

# if you just want the current default branch tip instead of a tag:
# git clone --depth 1 https://github.com/mitchspano/trigger-actions-framework "$env:TEMP\taf-new"
```

### Step 2 — read the release notes for that version

Open the GitHub releases page for the tag you pulled. Look specifically for:
- **Interface changes** — any change to the `TriggerAction` method signatures
  means your action classes (`Case_SetRefundOnCancellation`,
  `Case_DisruptionNotification`) need matching edits.
- **Metadata changes** — new/renamed fields on `Trigger_Action__mdt` or
  `sObject_Trigger_Setting__mdt` mean your custom metadata records may need updating.
- **The Flow contract** — if the `record` variable convention changes, your Flow
  actions need updating.

### Step 3 — replace the folder (with /PURGE so it matches exactly)

```powershell
robocopy "$env:TEMP\taf-new\trigger-actions-framework" `
         "D:\Projects\sf-architect-prep\trigger-actions-framework" /E /PURGE
```

`/PURGE` deletes files that no longer exist upstream, so your copy is an exact
mirror of the new version — no stale leftover classes.

### Step 4 — see exactly what changed

```powershell
git status            # what files changed in trigger-actions-framework/
git diff --stat trigger-actions-framework/
```

Everything changed should be inside `trigger-actions-framework/`. If `git status`
shows changes inside `force-app/`, something is wrong — stop and investigate
(it usually means a file was edited that shouldn't have been).

### Step 5 — validate without deploying

```powershell
sf project deploy start --source-dir trigger-actions-framework `
                        --source-dir force-app --dry-run
```

The dry-run compiles the new framework against your code. Compile errors here
almost always mean an interface changed — your action classes need their
signatures updated to match (see "Recovering" below).

### Step 6 — run the tests

```powershell
sf project deploy start --source-dir trigger-actions-framework --source-dir force-app
sf apex run test --class-names FrameworkScenarioTest CaseRefundServiceTest `
                 --result-format human --wait 10
```

Green tests on the new version = upgrade successful. Commit it:

```powershell
git add trigger-actions-framework
git commit -m "Upgrade Trigger Actions Framework to vX.Y"
```

---

## Recovering if an upgrade breaks

### Compile errors after the swap (most common)
Usually an interface signature changed. Update your action classes to match the
new signatures, then re-run the dry-run. Your **logic** (the services) won't
change — only the thin action adapters that implement the framework's interfaces.

### Metadata errors
A field on `Trigger_Action__mdt` or `sObject_Trigger_Setting__mdt` was renamed or
added. Update your records in `force-app/main/default/customMetadata/` to match
the new field names. Check a sample record in the new framework source for the
current shape.

### You want to abandon the upgrade entirely
Because you committed before upgrading, rollback is one command:

```powershell
git checkout -- trigger-actions-framework      # discard the folder changes
# or, if already committed:
git revert <upgrade-commit>                     # or git reset --hard <previous-commit>
```

This is the whole reason for committing a clean baseline first — the previous
version is always one git command away.

---

## What never changes during an upgrade

These are yours and live in `force-app/` — an upgrade does **not** touch them:

- Your services: `CaseRefundService`, `CaseNotificationService`
- Your selectors / UoW: `CaseSelector`, `UnitOfWork`
- Your async + recovery: `CaseNotificationQueueable`, `ErrorRetryBatch`
- Cross-cutting: `RecursionGuard`, `AppLogger`
- Error pipeline: `Error_Log__c`, `Error_Event__e`, `LogErrorEventTrigger`
- Your Flows and metadata records

At most, an upgrade touches the **thin action adapters** (because they implement
the framework's interfaces). Everything else is insulated by the lane design —
which is exactly why the framework sits in its own package directory and your
logic sits behind a thin layer.

---

## Quick checklist

```
[ ] Tests green on CURRENT version
[ ] Repo clean and committed (known-good baseline)
[ ] Read release notes for the target version
[ ] Pull target version to TEMP (pinned tag/commit)
[ ] robocopy /E /PURGE into trigger-actions-framework/
[ ] git status — only framework folder changed
[ ] dry-run passes (fix action-class signatures if not)
[ ] tests green on NEW version
[ ] commit the upgrade
```
