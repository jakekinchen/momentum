# Manager Log 001 - Workflow Setup

**Date:** 2026-06-04

## Status

FitGraph now has a repo-local autonomous workflow scaffold based on the reusable
executor/reviewer/manager pattern found in sibling projects.

## Evidence

- `GOAL.md` points at the first FitGraph KG brief.
- `executor-reviewer-pair-programming.md` defines Executor, Reviewer, and
  Manager boundaries.
- `docs/autonomous-workflow/` contains the workflow model and milestone plan.
- `scripts/` contains audit, run, start, stop, and session marker helpers.

## Manager Position

The manager should oversee process health and evidence quality. The manager
should not implement product code unless the user explicitly redirects the
manager to do so.

