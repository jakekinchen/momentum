# CamiFit — On-Device Exercise Engine — Design

- **Date:** 2026-06-03
- **Status:** Approved strategy; contract revised per technical review (2026-06-03). Ready to turn into briefs/plan.
- **Working name:** `camifit` (rename freely)
- **Scope of this doc:** Layer 1 (the on-device exercise engine + the Exercise-Program contract). Layers 2–3 are described only enough to fix the seams; they get their own specs.
- **Revision note:** This version folds in a detailed technical review. The strategic bet is unchanged (deterministic on-device executor first, constrained program contract second, agent authoring later). The contract was upgraded from a "per-frame threshold script" to a **timestamped, calibrated signal-processing engine**: first-class timestamps, smoothing/dwell, calibration, pose validity, stable side locking, world landmarks, and replay-based tuning.

---

## 1. Background & motivation

This design grows out of the `rfdetr-mlx` workspace and its `apps/cami` macOS app. Cami today is a camera → JSONL-worker → RF-DETR detection harness, repurposed from an "AirBench" gesture-control shell: detections flow through a `GestureSmoother` that turns stable hand gestures into commands. The repo also contains an in-progress **vision agent** (`apps/cami/daemon/cami-vision-agent.mjs` + `CamiVisionAgentClient.swift`) that translates a natural-language camera request into a **constrained declarative "visual program"** (strict JSON schema, fixed op vocabulary, OpenAI structured output with a scripted fallback, optional Codex runtime).

The goal of this project is different from Cami's RF-DETR-proof mission: an **open-ended, on-device fitness tracker** that watches you do bodyweight exercises, counts reps, checks form, and tracks sets — and where an embedded agent can later **author new exercises/routines dynamically**. The agent does not write arbitrary code; it emits the same validated program JSON the engine already runs (the pattern the vision agent already proves).

### Why a new standalone repo

The fitness app is MediaPipe-pose-centric and barely touches RF-DETR, so it diverges from the `rfdetr-mlx` port mission. It will be a **new standalone repo** that *copies patterns* from Cami (camera capture, the JSONL worker-client transport, the daemon shape) rather than depending on this repo.

---

## 2. The vision: a three-layer architecture

```
┌─ Layer 3: Tracker / persistence ── saved routines, session history, progress     (LATER SPEC)
├─ Layer 2: Agent authoring ──────── sidebar chat + Codex app-server (ChatGPT login);
│                                     NL → validated Exercise-Program JSON           (LATER SPEC)
│                                     (extends the existing vision-agent planner pattern)
└─ Layer 1: On-device executor ───── PoseProvider → joint-angle signals →
                                      a deterministic, timestamped interpreter that RUNS
                                      an Exercise-Program (reps, form rules, holds,
                                      sets/rest). Fully offline. THE FOUNDATION.     (THIS SPEC)
```

**The keystone is the Exercise-Program contract** — the JSON+DSL artifact that Layer 1 *executes* and Layer 2 *generates*. It is identical whether a program is hand-authored or agent-authored. Define it well and the layers stay decoupled.

**On-device vs cloud is not a contradiction:** all pose/rep/form/set tracking is 100% local and works offline. The cloud login (Layer 2) is needed *only to author new routines*; once authored, a routine is cached as local JSON and runs forever offline.

---

## 3. Decisions log

### 3.1 Strategic decisions (resolved during brainstorming)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Pose engine | **MediaPipe in a Python worker** | Cross-platform; 33 image landmarks + 3D world landmarks + visibility/presence; fits the worker transport. |
| 2 | RF-DETR's role | **Dropped from v1** | Bodyweight reps/form/sets derive entirely from pose. RF-DETR only adds equipment/object detection, unused by bodyweight. Kept as a designed-for extension for later equipment/sport exercises. |
| 3 | MVP exercises | **Bodyweight basics** (squat, push-up, lunge, plank) | Pure pose-driven; clearest rules; best proving ground for the engine. |
| 4 | Feedback timing | **Live real-time coaching** | Matches the camera→worker pipeline. |
| 5 | Feedback mode | **Visual overlay + light audio** (rep chime) | Spoken voice cues deferred. |
| 6 | Tracker scope (v1) | **In-session only** (+ load/save program JSON) | Session history/progress is Layer 3. |
| 7 | Agent output format | **Constrained rule DSL (JSON + sandboxed expressions)** | Expressive enough for real form rules; never executes arbitrary code. |
| 8 | Auth / transport (Layer 2) | **Codex app-server + ChatGPT login** | Matches "log into OpenAI for agent access"; no API keys for the user; bundled runtime. |
| 9 | Fork target | **New standalone repo** (`camifit`) | Diverges from the RF-DETR port mission; clean identity. |
| 10 | Build order | **Layer 1 + contract first** (squat end-to-end) | The agent is useless without an executor; its output must conform to a contract the executor defines. |
| 11 | Interpreter home | **Whole interpreter in Swift; Python worker is a pure pose source** | A rule DSL must be parsed/evaluated by exactly one sandboxed evaluator or two implementations drift. Swift keeps one evaluator, maximizes testability, and makes the pose worker a thin, swappable component. |

### 3.2 Contract-engineering decisions (from the 2026-06-03 technical review)

| # | Decision | Choice |
|---|----------|--------|
| 12 | Pose boundary | Define a Swift **`PoseProvider` protocol** + stable **`PoseFrame`** struct now, so the engine is independent of JSONL/Python/MediaPipe and a future Apple Vision backend. |
| 13 | MediaPipe running mode | Use **`VIDEO`** mode for v1 (deterministic request/response + internal tracking), not `IMAGE`; defer async `LIVE_STREAM`. |
| 14 | Cadence | Engine is **timestamp-based, never frame-count-based**. Target **12–15 pose fps**; render the camera preview independently at UI frame rate. |
| 15 | Frame transport | **No temp-file-JPEG hot path.** Prefer length-prefixed frames over a pipe / shared memory; temp-file JPEG only for debug + fixture capture. |
| 16 | Calibration | First-class **`setup`** block: required view/landmarks, min visibility, primary-side lock, mirror handling, and a short calibration capture for per-user/per-camera threshold overrides. |
| 17 | Identifier resolution | **Ban frame-by-frame "higher-visibility side."** Expressions use only `left.*`, `right.*`, `primary.*`, and `midpoint(...)`. `primary` is **locked during setup** and stable for the set. `landmark_aliases` map friendly names to `primary.*`. |
| 18 | Temporal filtering | First-class **`filters`** block (EMA/median, by ms window) producing named smoothed signals — kept *outside* the DSL so the DSL stays total and temporal behavior stays deterministic. |
| 19 | Rep dwell/timing | Rep FSM gains `down_min_ms`, `bottom_min_ms`, `up_min_ms`, `cooldown_ms` on top of hysteresis + `min_rom_deg`. |
| 20 | Signal validity | First-class **`validity`** block + a `SignalValue = valid(value, confidence) \| invalid(reason)` type, with an explicit `phase_signal_invalid_policy` (e.g. `freeze_then_reset`) to prevent phantom reps. |
| 21 | Multi-person | Worker runs **`num_poses = 2`** so it can *detect* a multi-person situation: 0 → "step into frame", 1 → run, 2+ → pause + "one person at a time". No dynamic highest-visibility tracking. |
| 22 | Coordinate space | Explicit per-program **`coordinate_space`** (`image2d` for v1); worker emits **both** normalized image landmarks and 3D world landmarks; future per-signal `angle3d(world.*)`. |
| 23 | Geometry helpers | Add `midpoint`, `angle_to_horizontal`, `signed_angle`, and safe `ratio`/division to the function allowlist before authoring presets. |
| 24 | Temporal form rules | Form rules gain `min_violation_ms`, `cooldown_ms`, and `score_weight` so a single noisy frame can't flicker a cue or wreck a rep score. |
| 25 | Replay/tuning debugger | A dev replay view (signals, thresholds, phase timeline, rep events, invalid intervals) is **part of the first vertical**, built before polished UI — it directly attacks the threshold-tuning risk. |
| 26 | Layer 2 pluggability | Agent authoring is an **`AuthoringProvider`** that yields candidate JSON, then runs the *same* schema+DSL validator as local presets. Prefer Codex app-server over **stdio or unix socket** (not websocket); **pin** the Codex CLI/schema version. |

---

## 4. Goals & non-goals (Layer 1)

**Goal:** an offline engine that, given an Exercise-Program (JSON+DSL) and a live webcam, counts reps, evaluates form rules, tracks sets, and renders live cues + a post-set summary — driven entirely by hand-authored program JSON (no agent yet).

**Success criteria:**
- Squat, push-up, lunge, and plank programs run end-to-end on a live webcam.
- Golden fixtures pass **exactly**: final rep count, **rep timestamps within tolerance windows**, expected phase/cue timelines, and **no false reps during no-person / low-visibility intervals**.
- At least one form fault per exercise is detected and surfaced as a (debounced) cue.
- The engine never executes anything outside the sandboxed DSL allowlist; an invalid program is rejected at load, not at runtime.

**Non-goals (Layer 1):** the Codex agent, sidebar chat, OpenAI/ChatGPT login, session history/progress DB, multi-day programs, weighted/sport exercises, RF-DETR, true multi-person tracking, spoken voice cues, 3D (`world`) rules.

---

## 5. The Exercise-Program contract (the keystone)

This JSON is what Layer 1 executes and Layer 2 will later generate. Full squat program with all v0.1 blocks:

```jsonc
{
  "schemaVersion": 1,
  "id": "bodyweight_squat",
  "name": "Bodyweight Squat",
  "coordinate_space": "image2d",               // image2d (v1) | world (future per-signal angle3d)

  "setup": {                                   // §16 calibration — runs once before the set
    "required_view": "side",
    "required_landmarks": ["primary.hip", "primary.knee", "primary.ankle", "primary.shoulder"],
    "min_visibility": 0.65,
    "primary_side": "auto_lock",               // lock the more-visible side during setup, then hold it
    "mirror_handling": "detect",
    "calibration": {
      "top_pose":    {"instruction": "Stand tall in frame", "capture_seconds": 1.0, "signals": ["knee", "torso_tilt"]}
    }
  },

  "landmark_aliases": {                        // friendly bare names → the locked primary side
    "shoulder": "primary.shoulder",
    "hip":      "primary.hip",
    "knee":     "primary.knee",
    "ankle":    "primary.ankle"
  },

  "signals": {                                 // RAW per-frame derived values (DSL expressions)
    "knee_left":     "angle(left.hip, left.knee, left.ankle)",
    "knee_right":    "angle(right.hip, right.knee, right.ankle)",
    "knee_raw":      "angle(primary.hip, primary.knee, primary.ankle)",
    "torso_raw":     "angle_to_vertical(primary.shoulder, primary.hip)",
    "knee_symmetry": "abs(knee_left - knee_right)"
  },

  "filters": {                                 // §18 temporal smoothing — OUTSIDE the DSL
    "knee":       {"source": "knee_raw",  "type": "ema",    "alpha": 0.35},
    "torso_tilt": {"source": "torso_raw", "type": "median", "window_ms": 200}
  },

  "validity": {                                // §20 what to do when the phase signal goes invalid
    "min_signal_confidence": 0.65,
    "phase_signal_invalid_policy": "freeze_then_reset",
    "freeze_ms": 500,
    "reset_after_ms": 1500
  },

  "rep": {                                     // §19 rep FSM with hysteresis + dwell timing
    "phase_signal": "knee",                    // a FILTERED signal name
    "down_when": "knee < 100",  "down_min_ms": 120,
    "bottom_min_ms": 80,
    "up_when":   "knee > 160",  "up_min_ms": 120,
    "min_rom_deg": 50,
    "cooldown_ms": 250
  },

  "hold": null,                                // plank uses this instead of `rep` (see §5.3)

  "form_rules": [                              // §24 temporal rules
    {"id":"depth",    "when":"phase == 'bottom'",                "expect":"knee <= 95",          "min_violation_ms":0,   "cue":"Go deeper",       "severity":"warn", "score_weight":10, "cooldown_ms":1500},
    {"id":"torso",    "when":"phase in ['descending','bottom']", "expect":"torso_tilt <= 45",    "min_violation_ms":250, "cue":"Chest up",        "severity":"warn", "score_weight":8,  "cooldown_ms":1500},
    {"id":"symmetry", "when":"phase == 'bottom'",                "expect":"knee_symmetry <= 20", "min_violation_ms":0,   "cue":"Even both sides", "severity":"info", "score_weight":4,  "cooldown_ms":2000}
  ],

  "set": {"target_reps": 10}
}
```

### 5.1 The DSL (expression language)

The only thing the LLM ever emits (in Layer 2) is JSON containing these expressions. The language is **total** — no statements, loops, assignment, side effects, or I/O.

- **Operands:** named signals (raw *or* filtered), landmark refs (`left.knee`, `right.ankle`, `primary.hip`), state vars (`phase`, `rep_count`, `time_in_phase_ms`), string literals (`'bottom'`), numeric literals, and list literals (`['descending','bottom']`).
- **Operators:** `+ - * /` (division is safe — divide-by-zero → invalid), comparisons (`< <= > >= == !=`), boolean (`and or not`), membership (`x in [..]`), and range (`x between a and b`).
- **Functions (fixed allowlist):** `angle(a,b,c)` (angle at vertex `b`), `angle_to_vertical(a,b)`, `angle_to_horizontal(a,b)`, `signed_angle(a,b,c)`, `distance(a,b)`, `midpoint(a,b)`, `ratio(x,y)`, `abs(x)`, `min(...)`, `max(...)`. *(Future: `angle3d(world.a, world.b, world.c)`.)*
- **Landmark namespace:** MediaPipe's 33 landmarks mapped to friendly names (`nose`, `shoulder`, `elbow`, `wrist`, `hip`, `knee`, `ankle`, …), addressable **only** as `left.<name>`, `right.<name>`, or `primary.<name>`. `primary` is locked during setup (§16/§17) and stable for the set — there is **no** frame-by-frame side switching inside the evaluator.
- **Identifier resolution order:** (1) **state var** → (2) **defined signal (raw or filtered)** → (3) **`landmark_aliases` entry** → (4) literal/landmark ref. A bare name that is none of these is a **load-time error**.
- **Signals form a DAG.** Raw signals may reference earlier raw signals; **filters** consume a raw `source` and publish a smoothed signal under their own name (e.g. `knee`); `rep`/`form_rules` reference the filtered names. Cycles, forward refs, or unknown names are load-time validation errors.
- **Coordinate space:** angles are computed in the program's `coordinate_space` (`image2d` for v1, x/y normalized). World landmarks are carried in every `PoseFrame` for future 3D rules.

### 5.2 Validity & confidence

Every signal evaluates to a `SignalValue`: `valid(Double, confidence: Double)` or `invalid(reason)`. A signal is `invalid` if any landmark it needs is below `min_visibility`/`presence`, or arithmetic is undefined. Rules whose inputs are invalid are **skipped that frame**. The **rep FSM** additionally applies `validity.phase_signal_invalid_policy` (e.g. `freeze_then_reset`: hold the current phase for `freeze_ms`, then reset to `ready` and mark any in-progress rep invalid after `reset_after_ms`).

### 5.3 Holds (plank et al.)

```jsonc
"rep": null,
"hold": {"signal": "hip_line", "in_range": "hip_line between 160 and 185", "target_seconds": 30}
```
A hold accumulates seconds while `in_range` holds and the signal is valid; it breaks and cues on exit. Same schema family, different evaluator.

### 5.4 Routines (deferred, contract-aware)

A **routine** is an ordered list of single-exercise programs plus per-item targets/rest (`routine: [{programRef, target_reps|target_seconds, rest_seconds}]`). It is a thin wrapper over the single-exercise schema and is **deferred past the squat vertical**; the schema reserves room for it.

---

## 6. Architecture & transport

```
 New repo:  camifit/                          (Swift app target + Python pose worker + presets/)

   Camera (Swift)                              PoseProvider (protocol)
        │  frames at UI rate                        │  AsyncStream<PoseFrame> at ~12–15 fps
        ▼                                           ▼
   [frame transport]  ──────────────▶  Python pose worker (MediaPipe VIDEO mode, num_poses=2)
        (length-prefixed frames over a pipe / shared mem;          │  JSONL: pose frames (see §8)
         temp-file JPEG = debug/fixture only)                      ▼
   Swift  ExerciseEngine
     ├─ ProgramLoader     (parse + validate JSON+DSL at load; reject bad programs)
     ├─ SignalEvaluator   (parse + eval DSL → SignalValue table)   ← the one evaluator
     ├─ FilterPipeline    (EMA/median by ms window → filtered signals)
     ├─ ValidityGate      (confidence/visibility → valid/invalid + FSM policy)
     ├─ RepStateMachine   (phase transitions, hysteresis, ROM, dwell timing)
     ├─ HoldEvaluator     (time-in-range accumulation)
     ├─ FormEvaluator     (temporal rules → debounced cues + weighted score)
     ├─ SetTracker        (reps → sets, rest detection)
     ├─▶ Overlay (skeleton + rep counter + one active cue + set progress)
     ├─▶ Audio  (rep chime; debounced fault tone)
     ├─▶ Post-set summary
     └─▶ TraceSink (per-frame trace for the replay debugger §13)
```

**Frame transport priority (decision #15):** (1) length-prefixed RGB/BGRA frames over a dedicated pipe; (2) shared-memory ring buffer with JSONL control; (3) JPEG over pipe if compression is needed; (4) temp-file JPEG **debug/fixture only**. v1 ships whichever of (1)/(3) reaches the 12–15 fps target simplest; the temp-file path from Cami is copied solely as a debug fallback and fixture-capture tool. Transport is hidden behind the `PoseProvider` boundary, so changing it never touches the engine.

---

## 7. The pose boundary & interpreter (Swift)

### 7.1 `PoseProvider` boundary (decision #12)

```swift
protocol PoseProvider {
    func start() async throws
    func frames() -> AsyncStream<PoseFrame>
    func stop()
}

struct PoseFrame {
    let frameID: Int64
    let timestampMS: Int64
    let imageSize: CGSize
    let normalizedLandmarks: [PoseLandmark]      // x,y,z normalized + visibility + presence
    let worldLandmarks: [PoseWorldLandmark]?     // metric 3D, carried even if unused in v1
    let posesDetected: Int
    let primaryPoseID: String?
    let latencyMS: Double
}

struct PoseLandmark { let x, y, z: Double; let visibility, presence: Double }
struct PoseWorldLandmark { let x, y, z: Double }
```

The first concrete provider wraps the MediaPipe JSONL worker. Apple Vision (17-joint 3D body pose, most-prominent person) can be added later as another `PoseProvider` without touching the engine — at the cost of a landmark-mapping adapter.

### 7.2 Interpreter components

All stateful components are **pure and frame-fed** (timestamps in, snapshot out — the proven `GestureSmoother` shape), so they unit-test without a camera.

- **ProgramLoader / validation:** parse JSON; parse every DSL expression to an AST; verify the signal/filter DAG (no cycles/forward refs), allowlisted functions only, and that every referenced signal/landmark/alias exists. **Invalid programs are rejected at load** with a precise error; they never reach the live loop.
- **SignalEvaluator:** recursive-descent (Pratt) parser → AST, evaluated against the landmark table + state vars to a `SignalValue`. Built-in functions only; no dynamic dispatch.
- **FilterPipeline:** applies `filters` (EMA by `alpha`, median by `window_ms`) to raw signals, keyed by `timestampMS` (window math is time-based, not frame-count-based), publishing filtered signals.
- **ValidityGate:** maps visibility/presence/confidence to valid/invalid and enforces `validity` policy on the phase signal.
- **RepStateMachine:** `ready → descending → bottom → ascending → repCounted`, with hysteresis (`down_when`/`up_when`), `min_rom_deg`, and dwell timers (`down_min_ms`, `bottom_min_ms`, `up_min_ms`, `cooldown_ms`). Emits per-rep ROM, tempo, and start/end timestamps.
- **HoldEvaluator:** time-in-range accumulation for holds.
- **FormEvaluator:** for each rule whose `when` holds, evaluate `expect`; a violation must persist `min_violation_ms` before it cues; cues respect `cooldown_ms`; failures reduce a weighted per-rep score (`score_weight`). Set score = mean rep score.
- **SetTracker:** reps→`target_reps` (or seconds→`target_seconds`), rest-gap detection; structured to host routines later.

---

## 8. Pose worker (Python)

- MediaPipe Tasks `PoseLandmarker` in **`VIDEO`** running mode with the `pose_landmarker_lite.task` bundle (~3 MB), `num_poses = 2`. Consumes frames over the chosen transport (§6); emits one JSONL pose record per frame:

```json
{ "type":"pose", "frame_id":123, "timestamp_ms":169..., "image_size":[1280,720],
  "poses_detected":1, "primary_pose_id":"0",
  "landmarks":[{"x":0.5,"y":0.4,"z":-0.1,"visibility":0.97,"presence":0.99}, "…33"],
  "world_landmarks":[{"x":0.02,"y":-0.31,"z":0.04}, "…33"],
  "latency_ms":18.3 }
```

- Preserves the **visibility vs presence** distinction and **both** normalized image and 3D world landmarks (decisions #9/#22) — never flattened into one ambiguous `[x,y,z,vis]` tuple.
- **Mock + fixture / replay paths** emit deterministic recorded landmark sequences, so CI and Swift tests never need a camera or the model bundle. Fixture playback drives the replay debugger and the acceptance fixtures.
- **Health** reports `pose_ready` (+ install hint if MediaPipe or the bundle is missing), mirroring the current worker's missing-model handling.
- The worker holds **no exercise/session state** — it is a pure, timestamped pose source.

---

## 9. Feedback

- **Overlay:** skeleton with bones tinted green/amber/red by active form rules, a large rep counter, one current cue, set progress. Reuses Cami's aspect-fill coordinate-mapping pattern.
- **Audio (`AVFoundation`):** a chime on each *counted* rep; a debounced low tone on a `warn`-severity fault. No spoken voice in v1.
- **Post-set summary card:** reps, set score, best/worst rep, average tempo, top fault, "do another set".

---

## 10. Persistence (Layer 1 scope)

- Load Exercise-Program JSON from a **bundled `presets/` directory** plus a **user programs directory**, so later, agent-generated programs written into the user dir simply appear in the picker.
- **No session history / progress DB yet** — that is Layer 3.

---

## 11. The Layer 2 seam (designed-for, not built here)

Agent authoring is an **`AuthoringProvider`** abstraction: it yields a *candidate* Exercise-Program JSON, which is then run through the **exact same schema + DSL validator** as local presets before being written to the user programs dir. No Codex/app-server detail leaks into Layer 1 or the schema.

When Layer 2 is built: prefer the Codex app-server over **stdio (default JSONL) or a local unix socket**, not the experimental/unsupported websocket; **pin** the Codex CLI runtime + generated-schema version (the schema artifacts are version-specific and the Python SDK drives a pinned local app-server over JSON-RPC). Auth is the Codex app-server's ChatGPT login, surfaced in a right-sidebar chat. Because the DSL is total and sandboxed, an agent-authored program is no more dangerous than a hand-authored one.

---

## 12. Error handling & edge cases

| Case | Handling |
|---|---|
| 0 poses | "Step into frame"; engine holds `ready`; no false reps |
| 1 pose | Run normally against the locked `primary` side |
| 2+ poses (`num_poses=2`) | Pause + "One person at a time" (decision #21) |
| Low landmark visibility/presence | Dependent rules skipped this frame; phase-signal policy applies (`freeze_then_reset`); framing cue |
| Wrong camera view | `setup.required_view` + one-time check; warn when key joints unreliable |
| Invalid program (bad DSL / unknown fn / DAG cycle / missing signal) | Rejected at **load** with a precise error; never runs |
| Pose worker crash mid-set | PoseProvider surfaces termination; engine freezes; summary offered for reps so far |
| MediaPipe / model bundle missing | Health `pose_ready:false` + install hint; actionable app error |
| Mirrored camera | `setup.mirror_handling:"detect"` resolves left/right before the set |

---

## 13. Testing & tuning

- **Swift (XCTest):** `SignalEvaluator` parsing/eval + allowlist/DAG-rejection (incl. **DSL fuzzing**); `FilterPipeline` time-window math; `ValidityGate` policy; `RepStateMachine` fed synthetic **timestamped** angle traces → assert exact rep counts, hysteresis, ROM, dwell timing; `FormEvaluator` debounce + scoring; `ProgramLoader` valid/invalid programs.
- **Event-timeline golden fixtures** (recorded landmark traces, committed JSON), at least three per exercise — **clean / shallow / noisy-occluded** — asserting: final rep count, rep timestamps within tolerance windows, phase-change and cue-window timelines, invalid-pose intervals, and **no false reps during no-person / low-visibility stretches**.
- **Python:** landmark output shape (visibility+presence, image+world); mock/fixture determinism; health readiness.
- **Replay/tuning debugger (decision #25, part of the first vertical):** a dev view that replays a recorded landmark trace and plots video/skeleton, `knee_raw` vs filtered `knee`, down/up thresholds, the phase timeline, rep events, active form rules, and invalid-landmark intervals. This is the primary instrument for threshold tuning and is built *before* the polished overlay.

---

## 14. Revised first vertical (squat) — narrowed

1. **Contract v0.1** — JSON Schema; DSL parser; explicit `coordinate_space`; `setup`/calibration; `filters`; `validity` policy; rep FSM timing fields; temporal form-rule fields.
2. **Pose worker v0.1** — MediaPipe `VIDEO` mode; timestamped frames; `num_poses = 2`; normalized + world landmarks (visibility + presence); no temp-file-JPEG hot path; fixture/replay playback mode.
3. **Engine v0.1** — signal evaluation; filter pipeline; validity propagation; squat FSM; cue aggregation; local trace output.
4. **Replay debugger** — plot signals + thresholds; replay recorded landmarks; inspect phase transitions and cues.
5. **Minimal live UI** — skeleton; rep count; one active cue; chime; basic set summary.
6. **Acceptance gate** — ≥3 squat fixtures (clean, shallow, noisy/occluded); exact final rep count; rep timestamps within tolerance windows; no false reps during no-person / low-visibility intervals.

Only after that gate passes do we add push-up, lunge, and plank as **added program JSON + evaluator/golden-fixture coverage** — the payoff of the data-driven contract.

- **Repo:** new standalone repo, working name `camifit`, created as the first implementation step.
- **Spec location:** this doc lives in `rfdetr-mlx/docs/superpowers/specs/` (active planning workspace) and is copied into `camifit/` at scaffold time.

---

## 15. Open questions & risks

- **Single-camera depth** limits some 3D faults (knee valgus). v1 stays `image2d`; `world` landmarks are carried for later `angle3d` rules.
- **Per-exercise threshold tuning** is the real effort. The replay debugger + clean/shallow/noisy fixtures + calibration overrides are the mitigations.
- **Cadence vs cost:** 12–15 pose fps is the target; transport choice (§6) is the lever if MediaPipe `VIDEO` + the pipe doesn't reach it.
- **Mirror & primary-side locking** correctness is setup-critical; covered by `setup` + fixtures including a mirrored capture.
- **Model-bundle download** (~3 MB) is small and within standing approval; exact install goes in the brief's env step.
- **Routine schema** is reserved but unspecified; fleshed out post squat vertical.

---

## 16. Next step

On approval, scaffold the `camifit` repo and drive the squat vertical (§14) through the **Codex executor/reviewer loop**: update the active mission/GOAL, write the first brief for **Contract v0.1 + Pose worker v0.1**, then run the pair cycle. Each slice leaves a brief, a session log, validation output, and a reviewer decision per the repo's evidence discipline.

---

## References (from the technical review)

- MediaPipe Pose Landmarker guide — 33 landmarks, image + world output, `num_poses`, running modes: https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker
- MediaPipe Pose Landmarker for Python — VIDEO/LIVE_STREAM semantics, visibility + presence: https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker/python
- Codex app-server README — stdio default, unix socket, websocket experimental, version-specific schema: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
- Codex SDK — local app-server over JSON-RPC, pinned CLI runtime: https://developers.openai.com/codex/sdk
- Apple Vision 3D body pose (WWDC23) — 17-joint 3D skeleton, most-prominent person: https://developer.apple.com/videos/play/wwdc2023/111241/
