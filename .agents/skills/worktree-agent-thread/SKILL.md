---
name: worktree-agent-thread
description: Set up and manage isolated repository workspaces for agent threads. Use when Codex needs to run parallel implementation, review, test, or automation work without file-write conflicts, when a task mentions git worktrees, second working folders, cloud/local isolation, worker threads, or avoiding interference between agents.
---

# Worktree Agent Thread

Use this skill before starting parallel or long-running agent work in a shared repository. Prefer git worktrees when the repository supports them; use a full copy only when git metadata, submodules, large ignored files, or tooling make worktrees impractical.

## Repo Notes

- This checkout participates in a linked-worktree setup. Always run `git worktree list --porcelain` before creating, removing, or assigning a worker workspace.
- Preserve `/Users/kelly/Developer/camifit` because it owns the common `.git` directory for linked worktrees. Use `/Users/kelly/Developer/camifit-pose` only for pose-worker-specific work.
- Keep app-owned runtime state under Application Support distinct from Codex session logs.
- For broad proof, prefer `scripts/run_monorepo_gates.sh`. For app-visible work, add `./script/build_and_run.sh --verify` or a live app/browser/device proof when relevant.

## Workflow

1. Preflight.
   - Read governing repo instructions.
   - Inspect `git status --short`, current branch, remotes, and existing worktrees.
   - Identify the task owner, branch naming pattern, allowed mutations, and proof target.
   - Stop if the current tree has user changes that the new thread would need to rewrite.

2. Choose isolation.
   - Use `git worktree add` for ordinary git repositories.
   - Use a full directory copy for repos without git, tasks involving ignored/generated state that must travel with the worker, or tools that do not behave correctly in linked worktrees.
   - Use cloud agents only when credentials, filesystem access, and environment parity are explicit; do not assume cloud isolation preserves local secrets, devices, or running services.

3. Create the workspace.
   - Name branches and folders predictably: `<repo>-agent-<short-task>` or `<repo>-wt/<short-task>`.
   - Keep the worktree outside the active checkout when possible.
   - Record the source branch, target branch, workspace path, and cleanup command.

4. Handoff.
   - Give each worker one coherent objective, repo/path scope, allowed actions, forbidden actions, proof command, and stop conditions.
   - Include relevant issue/PR URLs or local file paths, but do not pass secrets or broad environment dumps.
   - Use `references/handoff-template.md` for multi-worker or durable runs.

5. Reconcile.
   - Require the worker to report changed files, proof commands, proof results, blockers, and merge risk.
   - Review diffs from the isolated workspace before merging or copying changes back.
   - Prefer non-interactive merge/rebase commands. Do not overwrite the main checkout's uncommitted user work.

6. Cleanup.
   - Remove completed worktrees only after useful changes are merged, copied, or intentionally discarded.
   - Keep failed worktrees until their logs or diffs are no longer needed.
   - Report any workspace intentionally left behind.

## Safety Rules

- Treat the live checkout and user changes as protected state.
- Never run destructive cleanup commands against an ambiguous path.
- Do not assume CI credentials, device access, local services, or ignored files exist in the isolated workspace.
- Keep proof state explicit: created workspace, implemented change, tested locally, CI passed, merged, or deployed.

## Common Commands

```bash
git status --short
git worktree list
git worktree add ../<repo>-wt-<task> -b agent/<task> HEAD
git -C ../<repo>-wt-<task> status --short
git worktree remove ../<repo>-wt-<task>
```
