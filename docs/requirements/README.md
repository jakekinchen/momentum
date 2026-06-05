# Requirements

This folder stores routing notes for external requirements and golden data used
as source material for CamiFit planning.

## Candidate assessment

[`../../data/golden/candidate-assessment/`](../../data/golden/candidate-assessment/)
is the canonical vendored snapshot of the Future Research AI Engineer
take-home:

- `ASSESSMENT.md` - full requirements spec.
- `data/exercises.json` - 50-exercise golden catalog.
- `data/member-context.json` - synthetic member context for Jordan Rivera.
- `PROVENANCE.md` - source URL, upstream commit, file hashes, license note, and
  snapshot notes.

Treat that folder as a golden spec. If the upstream assessment changes, refresh
the snapshot intentionally and update `data/golden/candidate-assessment/PROVENANCE.md`.
