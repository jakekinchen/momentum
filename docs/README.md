# CamiFit Docs

This directory has three kinds of material:

1. **Product direction and architecture** - durable docs that should guide implementation.
2. **External requirements and research** - source material used to justify direction.
3. **Workflow records** - briefs, reviewer messages, manager logs, and executor logs from autonomous development loops.

## Start here

| Need | Read |
|---|---|
| Current KG + CamiFit integration direction | [`design/2026-06-04-camifit-fitgraph-synthesis.md`](design/2026-06-04-camifit-fitgraph-synthesis.md) |
| Core exercise engine architecture | [`design/2026-06-03-camifit-exercise-engine-design.md`](design/2026-06-03-camifit-exercise-engine-design.md) |
| Product north star and pose-stack decisions | [`prd/2026-06-03-camifit-prd.md`](prd/2026-06-03-camifit-prd.md) |
| Candidate-assessment requirements floor | [`../data/golden/candidate-assessment/`](../data/golden/candidate-assessment/) |
| Research prompt, response, and source links | [`research/`](research/) |
| Chat-generated regimen implementation plan | [`superpowers/plans/2026-06-04-chat-regimen-authoring.md`](superpowers/plans/2026-06-04-chat-regimen-authoring.md) |

## Directory map

| Directory | Purpose | Notes |
|---|---|---|
| [`design/`](design/) | Durable technical architecture and synthesis docs. | Treat the CamiFit x FitGraph synthesis doc as canonical for KG integration. |
| [`prd/`](prd/) | Product requirements and north-star product framing. | Drafts should point back to their source research. |
| [`requirements/`](requirements/) | Routing notes for external requirements and golden data. | The canonical candidate-assessment snapshot now lives under `data/golden/`. |
| [`research/`](research/) | Research prompts, responses, source links, and generated protocol references. | Separate research evidence from implementation commitments. |
| [`superpowers/`](superpowers/) | Implementation specs/plans written for agentic execution. | These are tactical plans, not product-level canonical docs. |
| [`manual-verification/`](manual-verification/) | Human-run verification handoffs and visible-app checks. | Use when local tests are not enough to prove user-visible behavior. |
| [`briefs/`](briefs/) | Per-slice implementation briefs. | Workflow history. Do not treat every old brief as current direction. |
| [`manager-log/`](manager-log/) | Manager decisions and milestone handoffs. | Workflow history. |
| [`reviewer-messages/`](reviewer-messages/) | Reviewer outputs from executor/reviewer loops. | Workflow history. |
| [`session-logs/`](session-logs/) | Executor session records. | Workflow history. |
| [`autonomous-workflow/`](autonomous-workflow/) | Reusable loop protocol and templates. | Operational docs for Codex-pair workflows. |

## Canonicality rules

- If design docs conflict, the newest explicitly canonical design doc wins.
- External requirement snapshots under `requirements/` are source material, not code to edit casually.
- Workflow records describe what happened in a slice; they are evidence, not automatically current architecture.
- New durable docs should include a status line such as `Draft`, `Canonical`, `Archived`, or `Superseded`.
