# Trade-offs In My Mouth

The interview sheet. For every major decision: the choice, the alternative, the one-line reason you picked one. Drill these until they're reflexive.

| Area | Chose | Over | Because | Breaks when |
|------|-------|------|---------|-------------|
| Sharing | Sharing rule | Role hierarchy | Visibility follows the team, not the mgmt chain | LDV recalc / ownership skew |
| Integration | Platform Event | REST callout | Decoupled, async, replayable; publisher doesn't wait | Need synchronous response / strict ordering |
| Automation | Flow | Apex | Declarative, maintainable for simple branching | Complex bulk logic / callouts / recursion control |
| (add rows as you go) | | | | |
