# Enterprise Org → Architecture Extraction Checklist

**Purpose:** Dissect a real enterprise org as a case study, abstract the architecture skeleton, and rebuild a clean-room generic version in your own dev org for Technical Architect interview prep.

**The discipline (read first):** Extract *patterns and the "why,"* never client assets. Do not copy proprietary metadata, Apex, named endpoints, data, or anything identifying the client. For each item below, the goal is to answer *"what decision was made and why"* — then rebuild a generic equivalent. If a captured detail is specific enough to identify the client, it is too specific to use.

**How to use this:** Work area by area. For each, answer the capture questions, record the *decision + rationale* (not the implementation), then mark whether you'll **Build** (implement the spine in your dev org) or **Doc** (capture as a design decision + diagram only).

---

## 0. Org Context (the framing question)

The interview prompt is usually *"set up an org for X users with these clouds and integrations."* Capture the shape that makes every later decision make sense.

- How many users, split by license type (Salesforce, Platform, Service Cloud, CPQ, partner/community)?
- How many business units / geographies / languages / currencies?
- Single org or multi-org? If single, what forced consolidation; if multi, what forced separation?
- Rough data volume per major object (order of magnitude — thousands? millions?).
- What's the integration surface — roughly how many systems touch Salesforce?

**Capture:** a one-paragraph "org profile" you can recite in 30 seconds.
**Build / Doc:** Doc.

---

## 1. User, License & Access Model

This is the literal "set up an org for X users" answer.

- License mix and *why* each population got the license it did (cost vs capability trade-off).
- Profile strategy: minimal base profiles + permission sets, or fat profiles? Why?
- Permission set groups — used? How are they organized (by role, by feature, by app)?
- Role hierarchy *shape* — how many levels, what drives the branching (geography? function? management chain)?
- How are new users provisioned — manual, SSO/JIT, identity provider driven?

**Capture:** the profile/permission-set philosophy and the role-hierarchy rationale.
**Build:** a representative base profile + 2–3 permission sets + a permission set group, and a 3–4 level role hierarchy.
**Doc:** the full license economics.

---

## 2. Sharing & Visibility (high-value — interviewers dig here)

- OWD per major object, and the *reason* for each setting (Private / Public Read / Read-Write).
- Where is visibility opened back up — role hierarchy, sharing rules, manual, team-based, or Apex managed sharing? Why that mechanism in each case?
- Any account/opportunity/case team usage?
- Any LDV-driven sharing concerns — sharing recalculation pain, ownership skew, group membership locks?
- External sharing — communities/Experience Cloud, sharing sets, sharing groups?

**Capture:** the visibility model as a table (object → OWD → reopening mechanism → why) plus any scale pain points observed.
**Build:** OWD + sharing rules + one Apex sharing example on a representative object.
**Doc:** the full table and the LDV reasoning.

---

## 3. Sales Cloud Spine

- Lead model — captured, scored, routed, converted how? Web-to-lead / queues / assignment rules?
- Opportunity stages and what *gates* movement between them (validation, approvals, required fields).
- Forecasting model — collaborative forecasts, forecast categories, custom?
- Products / price books — standard vs custom price books, how many, segmented by what?
- Territory management in use? What problem did it solve?

**Capture:** the lead-to-cash *front half* as a flow.
**Build:** working lead→opportunity→quote path with stage gating and one assignment rule.
**Doc:** forecasting and territory rationale.

---

## 4. Service Cloud Spine

- Case lifecycle — channels in (email, web, phone, messaging), statuses, closure rules.
- Routing — assignment rules vs Omni-Channel? Routing by skill, queue, capacity? Why?
- Entitlements / Milestones / SLAs — what's tracked, what triggers escalation?
- Knowledge — used? Article types, approval/publishing flow?
- Case automation — Flow, escalation rules, auto-response, macros?

**Capture:** case lifecycle diagram + routing logic + SLA model.
**Build:** case object flow with Omni-Channel routing on one channel + one entitlement/milestone + an escalation rule.
**Doc:** knowledge strategy and multi-channel detail.

---

## 5. CPQ (your flagship territory — go deep)

- Product architecture — standalone vs bundles, option constraints, configuration attributes.
- Price book structure and segmentation; list vs negotiated pricing.
- Pricing rules — price rules, lookup queries, discount schedules. Which are the *gnarly* ones?
- Quote document generation and the approval flow on discounts.
- Quote-to-order-to-contract handoff; renewals/amendments if present.
- The hard part — quote splitting, multi-dimensional quoting, large quote performance? Capture the *specific wall* hit and how it was solved.

**Capture:** the bundle/pricing model + the single hardest pricing problem and its solution.
**Build:** a bundle with options + 1–2 price rules + a discount approval flow + a quote-split implementation.
**Doc:** the full pricing-rule inventory.

---

## 6. Integration Inventory (capture pattern, never endpoints)

For *each* integrated system, record only the architectural shape:

- **Direction** — inbound, outbound, bidirectional?
- **Timing** — real-time, near-real-time, batch? What drove that?
- **Pattern** — REST/SOAP callout, Platform Events, Change Data Capture, Streaming, middleware (MuleSoft/iPaaS), point-to-point vs hub?
- **Auth pattern** — Named Credential + which OAuth flow? (Capture the *flow type*, never credentials.)
- **Volume & limits** — callout limits, bulkification, governor pressure?
- **Error handling** — retry strategy, dead-letter, idempotency, monitoring/alerting?
- **Why this pattern** over the alternatives?

**Capture:** an integration table (system role → direction → timing → pattern → auth flow → error strategy → why). Genericize system names ("ERP," "billing system," "identity provider").
**Build:** two representative integrations — one Platform Events (async, with retry/error handling) and one REST callout via Named Credential.
**Doc:** the full inventory table.

---

## 7. Automation & Declarative Strategy

- Flow vs Apex decision rule in this org — where's the line drawn and why?
- Trigger framework — one-trigger-per-object? Handler pattern? How is recursion controlled?
- Order-of-execution gotchas they've hit (Flow + trigger interaction, before/after, recalculation).
- Async strategy — Queueable / Batch / Scheduled / Future — what runs where and why?

**Capture:** the automation decision rule + the trickiest order-of-execution case they hit.
**Build:** a trigger framework on one object handling a genuinely tricky order-of-execution scenario + one Queueable or Batch job.
**Doc:** the Flow-vs-Apex governance rule.

---

## 8. Identity & Access (auth, not record-sharing)

- SSO — SAML / OpenID Connect? IdP-initiated or SP-initiated?
- User provisioning — JIT, SCIM, manual?
- OAuth flows in use for integrations and why each (and yes — your `grant_type=password` vs Connected App question lives here).
- MFA / session/security policy posture.

**Capture:** the identity architecture + which OAuth flow serves which use case and why.
**Build:** configure one SSO setup (even with a free test IdP) + one Connected App with the correct OAuth flow.
**Doc:** the flow-selection rationale.

---

## 9. Data Architecture & Scale

- Largest objects and their growth rate; any LDV mitigations (skinny tables, indexing, custom indexes, archiving)?
- Selective query strategy — known non-selective query pain?
- Data model trade-offs — master-detail vs lookup decisions and why; junction objects; denormalization for reporting.
- Reporting/analytics load — does it stress the transactional model? Big Objects / external objects / CRM Analytics?

**Capture:** the LDV pressure points + the data-model trade-offs that were debated.
**Build:** model one representative relationship decision (M-D vs lookup) with the reasoning.
**Doc:** the scale mitigations.

---

## 10. DevOps & Environment Strategy

- Environment topology — how many sandboxes, of what type, for what stage?
- Deployment mechanism — change sets, SFDX/metadata API, unlocked packages (2GP)?
- CI/CD — present? What pipeline, what gates (tests, code coverage, static analysis)?
- Release cadence and how impact/dependency analysis is done before deploy.

**Capture:** the environment + release flow as a diagram.
**Build:** Doc only (don't burn dev-org time rebuilding pipelines).
**Doc:** the full topology and release governance.

---

## Output you should end up with

1. **One "org profile" paragraph** (Section 0) — your 30-second opener.
2. **A clean-room dev org** with the *spines* built: Sales → Service → CPQ working end-to-end, plus 2 representative integrations, a trigger framework, and one SSO/Connected App. (The **Build** items.)
3. **A design-decision dossier** — the tables and diagrams for everything marked **Doc**, each with its *why*.
4. **A "trade-offs in my mouth" sheet** — for every major decision, the alternative you rejected and the reason. This is what wins architecture interviews.

When someone says *"design an org for 2,000 users with Sales, Service, CPQ and three integrations,"* you answer from a real architecture you dissected and rebuilt — not from theory.
