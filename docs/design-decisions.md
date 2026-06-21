# Design-Decision Dossier

One entry per architectural decision. Capture the decision, the context, and — critically — *why this over the alternatives*. Generic only; no client detail.

> Template per entry below. Duplicate as you go.

---

## [Area] — [Decision name]
- **Context:** (org shape / scale that frames the decision)
- **Decision:** (what was chosen)
- **Why:** (the reasoning)
- **Alternatives rejected:** (what else was on the table, and why not)
- **Breaks at scale when:** (the limit / failure point)
- **Build or Doc:**

---

## Example — Sharing: Opportunity OWD
- **Context:** ~2,000 sales users, reps own their pipeline, sales pods collaborate.
- **Decision:** Private OWD, reopened via criteria-based sharing rule to the pod.
- **Why:** Default expectation is reps see only their own deals; collaboration follows the *team*, not the management chain.
- **Alternatives rejected:** Role-hierarchy reopening (follows mgmt chain, wrong axis); Apex managed sharing (overkill — criteria are static at this volume).
- **Breaks at scale when:** sharing recalculation / ownership skew at very high row counts.
- **Build or Doc:** Build (representative object).
