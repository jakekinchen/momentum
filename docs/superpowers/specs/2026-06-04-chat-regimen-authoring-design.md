# CamiFit — Chat-Driven Regimen & Exercise Authoring (Design)

- **Date:** 2026-06-04
- **Status:** Approved design, pending spec review
- **Scope:** Feature 1 of 2. The 3D demonstration avatar is a **separate, later spec** (`procedural keyframed SceneKit skeleton`), built after this ships.
- **Depends on:** the Codex-backed coach chat (`CodexAppServerClient`, `ChatViewModel`) on branch `feat/codex-coach-and-shell`.

## Goal

The coach chat can **dynamically generate workout content and show it to the user**:

1. **Routines** — an ordered sequence of exercises with sets/reps/holds/rest.
2. **New exercises** — brand-new pose-tracking `ExerciseProgram` contracts the engine can actually run (the user explicitly chose this over "routines of existing exercises only").

Generated content renders as a card in the chat and, when saved, becomes a selectable, trackable exercise in the app.

## Approach: fenced JSON blocks in the reply

The agent answers conversationally **and** appends a fenced code block the app parses:

- ` ```camifit-exercise ` → a full `ExerciseProgram` JSON object.
- ` ```camifit-routine ` → a `WorkoutRoutine` JSON object.

Chosen over Codex tool-calling (would require servicing `item/tool/call` server requests — we currently reply `-32601`) and over a hidden second structured turn (extra orchestration). Fenced blocks need **no protocol changes** and keep the chat conversational.

## Data model

- **Exercise:** reuse the engine's existing `ExerciseProgram` (`Codable`) verbatim — same schema as bundled presets (`schemaVersion`, `signals` as `angle(...)` expressions, `rep`/`hold` config, `form_rules`, etc.).
- **Routine:** new `WorkoutRoutine: Codable` in `CamiFitApp` (UI-layer, not engine):
  ```
  WorkoutRoutine { id, name, description, blocks: [RoutineBlock] }
  RoutineBlock { exerciseRef: ExerciseRef, sets: Int, reps: Int?, holdSeconds: Double?, restSeconds: Int }
  ExerciseRef = .preset(id: String) | .inline(ExerciseProgram)   // inline = newly authored
  ```

## Agent contract

Extend the coach's `baseInstructions`/`developerInstructions` in `CodexAppServerClient`:

- On a "make me a workout / new exercise" request, reply in prose **and** append the appropriate fenced block.
- Embed **one full existing preset** (`bodyweight_squat`) as a verbatim template, plus the field rules: signals are `angle(primary.hip, primary.knee, primary.ankle)`-style expressions over the known landmark namespace; provide a `rep` block **or** a `hold` block; set `required_landmarks` and a `calibration` capture; keep `schemaVersion: 1`.
- Keep it bounded: one exercise or one routine per reply.

## Parsing & validation (app side)

On `turn/completed`, scan the finalized assistant message for fenced `camifit-exercise` / `camifit-routine` blocks:

1. **Parse** the JSON.
2. **Decode** into `ExerciseProgram` / `WorkoutRoutine` (structural validation via `Codable` + `ProgramLoader`).
3. **Dry-run** each exercise through the engine against a neutral sample `PoseFrame` to catch evaluation errors (undefined landmark, bad signal expression) without a crash.
4. On failure → render an **error card** ("Couldn't validate this exercise — ask the coach to revise") with the decode/eval error. The app may auto-send a short corrective follow-up turn containing the error text (best-effort, capped at one retry).

A small `RegimenBlockParser` owns step 1–3 and is unit-tested independently of the chat.

## Persistence & engine integration

- Accepted exercises are written as `ExerciseProgram` JSON to `~/Library/Application Support/CamiFit/Presets/<id>.json`.
- The preset loader (`AppExerciseSessionViewModel` / `AppRecordedRunCatalog`-style resolution) currently returns the **first** non-empty candidate dir. Change it to **merge** the bundled presets dir and the user Application-Support dir (user entries win on id collision). New exercises then appear in the **Exercise picker** and are trackable via Live Camera like any preset.
- Routines are written to `~/Library/Application Support/CamiFit/Routines/<id>.json`. A lightweight `RoutineStore` loads/saves them.

## UI

- **Inline cards in the chat transcript.** When a finalized assistant message yields a valid block, render a `RegimenCard` below the bubble:
  - Exercise card: name, what it tracks (reps/hold), a "Generated — may need tuning" note; actions **Save & add to exercises**, **Discard**.
  - Routine card: name, description, the ordered block list (exercise · sets × reps / hold · rest); actions **Start routine** (selects block 1's exercise, shows a small progress strip), **Save**, **Discard**.
- Saving an exercise calls the new preset writer + `loadAvailablePresets()`; the picker updates reactively.
- Routine "Start" sets the active exercise to the first block and surfaces a compact routine progress indicator in the detail hero (block N of M); advancing is manual for v1.

## Non-goals (this spec)

- The 3D avatar (separate spec).
- Editing generated exercises in a form UI (only accept/discard for v1).
- Multi-user / cloud sync of routines (local files only).
- Guaranteeing rep-count **accuracy** of AI-authored exercises (see caveat).

## Caveats & risks

- **AI-authored pose math is approximate.** A generated `ExerciseProgram` can decode and dry-run cleanly yet still miscount reps or mis-validate form, because the signal thresholds/geometry may be wrong for the real movement. We validate *structure* and *non-crashing*, not *correctness*. Cards carry a "Generated — may need tuning" label, and the new exercise is clearly distinguished from curated presets.
- **Prompt size.** Embedding a full preset template grows the system prompt; keep to one example.
- **Coordination:** this builds on the unmerged Codex-coach branch; sequence accordingly (see status).

## Testing

- **Unit:** `RegimenBlockParser` extracts fenced blocks from mixed prose; valid `ExerciseProgram`/`WorkoutRoutine` decode; malformed JSON and structurally-invalid programs are rejected with a useful error; dry-run rejects a program referencing an unknown landmark.
- **Unit:** preset loader merges bundled + user dirs (user wins on id collision); preset writer round-trips.
- **Integration (manual / live, not CI):** ask the coach "create a calf-raise exercise" and confirm it returns a parseable `camifit-exercise` block that decodes and dry-runs.

## Rollout

Feature 1 ships as its own branch/PR off `feat/codex-coach-and-shell`. The avatar spec + implementation follows.
