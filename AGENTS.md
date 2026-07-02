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
- Remotes: `origin` (github.com/jakekinchen/momentum) is canonical — it hosts
  the public releases the website download redirects to; `gitlab`
  (gitlab.com/jakekinchen/camifit) is a mirror. Push `main` to origin first,
  mirror to gitlab after. Release tags are `macos-<version>`.
- `main` is the active branch for this worktree (the
  `feat/monorepo-synthesis` note below is historical). Fetch and reconcile
  `origin/main` before starting substantial work — parallel lanes land there.

## Guide-Motion Promotion Checklist

Promoting an exercise to guide-ready touches SIX enforcement layers plus
expectation lists; missing one fails gates or, worse, ships silently. In
order:

1. `scripts/motion_reference/exercise_motion_profiles.json` — profile exits
   fail-closed (`viewer_status`, `capture.status` accepted kind).
2. Python audits (`audit_motion_coverage.py`) — capture status in the
   accepted set; manifest branch for the source kind; unit tests.
3. Bundle: `Sources/CamiFitApp/Resources/MotionDemos/<id>.jsonl` +
   acceptance manifest (visual_review, engine_replay, live_app_review,
   artifact_integrity) — review-only demos instead carry
   `packaging_scope: motion_review_gallery_demo_only`.
4. Swift gate: `AppExerciseTrackingGate.guideReadyPresetIDs` (add) and
   `referenceCaptureRequiredPresetIDs` (remove).
5. Swift manifest eligibility: `MotionDemoSourceKind` case +
   `MotionDemoManifest.isGuideEligible` branch (only for NEW source kinds).
6. `script/build_and_run.sh` — move the id from the review-only loop to the
   packaged-guide loop.

Expectation lists that must follow: `MediaPipePoseProviderTests` replay case,
`AvatarHumanoidGLBAssetTests`, `AppExerciseSessionViewModelTests`,
`AssignmentExerciseCatalog(.swift + Tests)`, `MotionGuideAccuracyTests`
baseline (`Tests/CamiFitEngineTests/Fixtures/motion_accuracy_baseline.json`),
`test_preflight_motion_data_factory.py`, and the five guide manifests'
`live_app_review` installed inventory (all must state the same N traces,
verified against a real `/Applications/Momentum.app` install before release).

## Agent Pitfalls

- Piping a command into `tail`/`grep` masks its exit code — capture
  `exit=$?` explicitly or write logs to a file (a release-script failure was
  once misread as success this way).
- Finder AppleScript (DMG layout) is blocked in headless contexts; the
  release script auto-falls back to
  `scripts/release_assets/momentum_dmg_layout.DS_Store`. Do not "fix" the
  AppleEvent timeout by retrying.
- The strict motion audits depend on local-only `dist/` artifacts; a fresh
  clone cannot pass `--require-trackable-reference-clips`. CI runs the
  non-strict tier; the strict tier is the release-machine preflight.

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
