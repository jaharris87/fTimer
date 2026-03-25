Handle review findings for PR #<NN>.

Start with:
1. docs/agent-context.md
2. docs/workflows/findings-disposition.md
3. the PR
4. the review findings
5. the latest handoff note

Task:
- Classify and respond to every finding
- Decide whether to agree and fix, disagree with evidence, or defer with reason
- Open follow-up issues when deferral requires durable tracking

Working rules:
- Do not reread broad repo context unless a finding truly requires it.
- Treat this as a disposition session, not a fresh repo review.
- Keep responses explicit and evidence-based.

Deliverables:
- per-finding disposition
- any needed code/doc/test changes
- any needed follow-up issues
- closeout summary
- session handoff using docs/templates/session-handoff.md

Stop condition:
- Stop once all current findings are addressed and the handoff is written.