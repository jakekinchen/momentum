# CamiFit Agent Guidance

## Active Worktree

Use `/Users/kelly/Developer/camifit-app` for the CamiFit macOS app and
FitGraph synthesis lane.

- Active branch: `feat/monorepo-synthesis`
- This is the current app/synthesis worktree.
- Run build and test commands from this directory unless the user explicitly
  asks for another worktree.

## Other Local Worktrees

The same git repository also has these local worktrees:

- `/Users/kelly/Developer/camifit` on `feat/chat-regimen`
  - This is the original/main worktree for the repo and currently owns the
    common `.git` directory used by linked worktrees.
  - Do not use it for the active macOS synthesis lane.
  - Do not delete or rename this directory casually; doing so can break linked
    worktrees such as `camifit-app`.
- `/Users/kelly/Developer/camifit-pose` on `pose-worker`
  - Use only for pose-worker-specific work.

If you need to inspect the layout, run:

```bash
git worktree list --porcelain
```

## Version Control Rules

- Keep commits scoped to the active worktree and branch.
- Before editing, run `git status --short --branch` in the intended worktree.
- Before committing, verify `git rev-parse --show-toplevel` is
  `/Users/kelly/Developer/camifit-app` for this lane.
- Do not stage unrelated untracked files from other worktrees.

## Runtime State

CamiFit app-owned runtime state belongs under Application Support, not `/tmp`:

- Coach thread cwd:
  `~/Library/Application Support/CamiFit/AgentThreads/Coach`
- Member KG overlay:
  `~/Library/Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl`

Codex may also maintain external audit/session logs under `~/.codex/sessions`.
Those logs are not the CamiFit app-owned state.

## Repo-Local Skills

Prefer repo-local skills under `.agents/skills/` for these workflows:

- `worktree-agent-thread`: use before creating parallel CamiFit workers. Confirm `git worktree list --porcelain` first and never delete or rename `/Users/kelly/Developer/camifit` or `/Users/kelly/Developer/camifit-pose` casually.
- `self-audit-pass`: use before handoff when app, KG, motion, camera, or website behavior changes. Keep build/test proof separate from installed-app, live-camera, or hardware proof.
- `goal-loop`: use for `GOAL.md`-driven Codex loops and autonomous workflow cycles. Prefer the existing scripts under `scripts/` when they cover the task.
