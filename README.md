# Salesforce Technical Architect Prep

A single home for TA interview prep: a clean-room dev-org build, the architecture decisions behind it, and the trade-offs to defend in an interview.

## The method (one line)
Dissect a real enterprise org for *patterns*, rebuild a generic version here, and be able to defend every decision against the alternatives.

## ⚠️ IP / clean-room rule (non-negotiable)
- This repo holds **clean-room, genericized** work only.
- **Never commit** client metadata, endpoints, credentials, or anything identifying the source org.
- Raw extraction from the client dev org goes in `/extraction-raw/` — which is **git-ignored** and stays local. Only the abstracted version makes it into `/docs`.

## Layout
- `docs/` — the thinking layer (version-controlled, generic)
  - `extraction-checklist.md` — what to extract per architecture area, with Build/Doc calls
  - `claude-code-prompts.md` — copy-paste prompts to pull config via Claude Code
  - `design-decisions.md` — the dossier: each decision + why (fill as you go)
  - `tradeoffs.md` — the "trade-offs in my mouth" sheet (the interview gold)
- `force-app/` — the proving layer: SFDX source for the **Build** items
- `diagrams/` — architecture diagrams for the **Doc** items
- `extraction-raw/` — local only, never committed (see IP rule)

## Build items (implement the spine — these live in force-app)
1. Sales → Service → CPQ end-to-end flow
2. Two integrations: one Platform Event (async + retry), one REST callout via Named Credential
3. A trigger framework on one object handling a tricky order-of-execution case
4. One SSO / Connected App with the correct OAuth flow

Everything else: capture as a **design decision + diagram**, don't rebuild.

## Working loop
1. Run a Claude Code prompt → raw config → save to `extraction-raw/` (local).
2. Bring it to the matching topic chat → reason the *why* + rejected alternatives.
3. Decide Build or Doc.
4. Record the decision in `design-decisions.md` and the trade-off in `tradeoffs.md`.
