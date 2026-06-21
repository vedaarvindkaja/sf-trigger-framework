# Claude Code Org-Extraction Prompts

**Use with:** a **dev/sandbox copy** of the enterprise org (never prod directly), authorized via `sf org login web`, run from inside an SFDX project folder so `sf project retrieve` has a target.

**Golden rule:** Claude Code extracts **WHAT** is configured. It does **NOT** know **WHY** — that reasoning is yours (and the interview skill). If it volunteers rationale, treat it as a hypothesis to verify, not a fact.

**IP discipline:** When extracting integrations/identity, capture the *pattern* and *flow type* only. Genericize system names and **never** record endpoints, credentials, or client-identifying detail.

Tip: add `and tell me what you could NOT determine from metadata alone` to the end of any prompt — that surfaces exactly the gaps you must reason through yourself.

---

## 0. Org Profile

```
Query this org and give me a one-paragraph profile: total active users, breakdown of active users by profile, and license usage. Use:
SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense
SELECT Profile.Name, COUNT(Id) FROM User WHERE IsActive=true GROUP BY Profile.Name
Also report enabled currencies/languages and whether it's multi-currency. Summarize what kind of org this is in 3 sentences.
```

## 1. Users, License & Access Model

```
Map this org's access model. List all profiles and all permission sets (names only), and any permission set groups with their member sets. Then query the full role hierarchy:
SELECT Name, ParentRole.Name FROM UserRole ORDER BY ParentRole.Name
Show the role hierarchy as an indented tree and tell me how many levels deep it goes and what seems to drive the branching (geography, function, etc. — flag this as a guess).
```

## 2. Sharing & Visibility

```
Retrieve org-wide defaults for all standard and custom objects and present them as a table: object | internal OWD | external OWD. Then list all sharing rules per object (criteria-based vs owner-based). Then search the Apex codebase for any manual/Apex sharing (references to "__Share" objects or Sharing.create). Summarize the visibility model and flag where access is reopened by hierarchy vs sharing rules vs Apex.
```

## 3. Sales Cloud Spine

```
Extract the Sales Cloud configuration. Query OpportunityStage (MasterLabel, IsClosed, IsWon, SortOrder) and list the stages in order. List Opportunity and Lead record types. Find lead assignment rules and any Flows on Lead/Opportunity. List price books (SELECT Name, IsStandard, IsActive FROM Pricebook2). Describe the lead-to-opportunity path as a flow.
```

## 4. Service Cloud Spine

```
Extract the Service Cloud setup. List Case record types and Case status values. Retrieve Omni-Channel config (service channels, routing configs, presence statuses) if present. List entitlement processes and milestones. Find escalation rules, auto-response rules, and any Case Flows. Summarize the case lifecycle and routing model.
```

## 5. CPQ

```
This org uses Salesforce CPQ (SBQQ namespace). Inventory the CPQ config:
- Products with bundles: query SBQQ__ProductOption__c grouped by parent product
- Price rules: SELECT Name, SBQQ__ConditionsMet__c, SBQQ__EvaluationEvent__c FROM SBQQ__PriceRule__c
- Discount schedules and any price action/lookup queries
- Quote-related custom fields and any quote-line Flows or triggers
Summarize the bundle/pricing architecture and call out the most complex pricing rule you find.
```

## 6. Integration Inventory  *(pattern only — genericize, no endpoints/creds)*

```
Inventory this org's integration surface WITHOUT recording any endpoints, URLs, or credentials. Find and list:
- Connected Apps (names + OAuth scopes + which OAuth flow)
- Named Credentials (name + auth protocol type ONLY, redact the URL)
- Platform Events (custom objects ending in __e) and their fields
- Change Data Capture enabled entities
- Scheduled/async jobs: SELECT CronJobDetail.Name, State FROM CronTrigger ; recent AsyncApexJob types
- Apex classes implementing callouts (search for HttpRequest / @future(callout=true) / Database.AllowsCallouts)
For each integration, give me: direction | timing (real-time/batch) | pattern (REST/Platform Event/CDC/etc) | auth flow type. Genericize all system names.
```

## 7. Automation & Trigger Framework

```
Analyze the automation strategy. List all Apex triggers grouped by object (flag any object with more than one trigger). Identify whether a trigger handler framework is used (look for a base handler class, trigger handler interface, or dispatch pattern) and describe it. List all active record-triggered and screen Flows by object. List Batch, Queueable, Schedulable, and @future classes. Tell me where the Flow-vs-Apex line appears to be drawn.
```

## 8. Identity & Access

```
Extract the identity architecture WITHOUT recording secrets. Retrieve SAML SSO configs and Auth. Providers (names, protocol — SAML vs OpenID Connect — and IdP-initiated vs SP-initiated). List Connected Apps used for inbound OAuth and the OAuth flow each implies from its scopes/config. Report MFA/session settings if retrievable. Summarize which OAuth flow serves which use case.
```

## 9. Data Architecture & Scale

```
Profile the data model for scale. Get approximate record counts for the largest objects (use sf data query with COUNT() on the major standard + custom objects). For the top 5 largest objects, list their relationship fields and tell me which are master-detail vs lookup. Flag any objects likely to be Large Data Volume candidates. Identify any custom indexes or external/Big Objects. Summarize the LDV pressure points.
```

## 10. DevOps & Environment  *(Doc only — light extraction)*

```
From this org, list any deployment-related metadata: installed managed packages (sf package installed list), any unlocked package namespaces, and named credentials/remote sites pointing at CI tooling. Note: most environment/release strategy can't be read from a single org — flag what's missing so I capture it as a design decision instead.
```

---

## Working loop per topic

1. Paste the prompt → let Claude Code pull the **what**.
2. Save its output (the raw config inventory).
3. Bring it to the matching topic chat in the Project → we reason the **why** and the rejected alternatives.
4. Decide **Build** (implement the spine in your dev org) or **Doc** (design-decision + diagram).
5. Add the trade-off to your "trade-offs in my mouth" sheet.

The prompts are the fast part. The reps are in step 3.
