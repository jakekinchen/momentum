# Manual Verification 046: KG Memory Chat E2E

Date: 2026-06-05

## Scope

Verify the end-to-end in-app flow requested for the KG memory chat bridge:

- user tells the coach a health/safety limitation;
- the LLM emits a `camifit-kg-operation` proposal;
- the app validates and appends the operation to the member KG overlay;
- the chat renders a memory-saved artifact instead of exposing raw operation JSON;
- the memory is immediately available to subsequent coach turns.

## Code State Tested

Branch: `feat/monorepo-synthesis`

Touched implementation:

- `Sources/CamiFitApp/CodexAppServerClient.swift`
- `Sources/CamiFitApp/ContentView.swift`
- `Sources/CamiFitApp/KGMemoryProposal.swift`
- `Sources/CamiFitApp/KGMemoryStore.swift`
- `Tests/CamiFitAppTests/CoachAuthoringGateTests.swift`
- `Tests/CamiFitAppTests/KGMemoryPanelModelTests.swift`
- `script/build_and_run.sh`

## Headless / Protocol Evidence

Result: PASS for proposal shape and app-owned write bridge.

`swift test --disable-sandbox --filter KGMemoryPanelModelTests` passed 4 tests, including:

- `testCoachProposalParsesAndAppendsHealthMemoryArtifact`
- `testMalformedCoachProposalDoesNotAppendMemory`

The successful bridge test printed:

```text
kg-memory-chat-bridge artifact=saved title=Left Knee context=true
kg-memory-chat-bridge malformed_ignored=true revision=0
```

A one-off app-server protocol harness using the same `thread/start` and `turn/start` JSON-RPC flow completed successfully. It received an LLM reply containing a fenced `camifit-kg-operation` JSON block for:

```text
I have left knee pain, please remember this for future workouts.
```

The harness session was:

```text
/Users/kelly/.codex/sessions/2026/06/05/rollout-2026-06-05T15-45-34-019e9988-b752-7e91-af8f-2eef7ad037e1.jsonl
```

That proves the Codex app-server protocol can produce the expected LLM operation block.

## GUI E2E Evidence

Result: PASS for the full visible in-app E2E.

The app was launched with:

```bash
: > "$HOME/Library/Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl"
./script/build_and_run.sh --verify
```

The prompt was sent through the visible SwiftUI chat field by accessibility control:

```text
I have left knee pain, please remember this for future workouts.
```

Observed GUI state after the first successful turn:

```text
AXStaticText | I have left knee pain, please remember this for future workouts.
AXStaticText | Got it — for workouts, we’ll avoid aggravating your left knee and favor low-impact, knee-friendly options or modifications.
AXStaticText | Memory saved
AXStaticText | Left Knee health/safety memory added to the local KG.
```

Overlay evidence:

```text
1 /Users/kelly/Library/Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl
{"actor":"agent","effect":{"constraint_type":"BodyRegion","hard":true,"negated":false,"source_text":"I have left knee pain, please remember this for future workouts.","value":"left_knee"},"operation_type":"AddMedicalConstraint","precondition_revision":0,"scope":"member"}
```

The follow-up prompt was then sent through the same visible chat field:

```text
Can I do jump squats today?
```

Observed subsequent-chat response:

```text
I’d skip jump squats today because the jumping/landing can stress your left knee.

Try a gentler option instead:
- Box squats to a chair: 2–3 sets of 8–12
- Glute bridges: 2–3 sets of 10–15
- Step-free wall sit only if pain-free: 2–3 holds of 15–30 seconds

Keep the range of motion comfortable, move slowly, and stop if knee pain increases.
```

The overlay remained at one line after the follow-up turn, so the app acted on the memory without appending a duplicate write.

Current passing app session:

```text
/Users/kelly/.codex/sessions/2026/06/05/rollout-2026-06-05T16-46-45-019e99c0-ba88-7fb2-b2a2-35accc4fe734.jsonl
```

The second user message recorded in that session included the app-injected fact card:

```text
CamiFit local KG fact cards for this user:
- Left Knee: I have left knee pain, please remember this for future workouts.
```

Screenshot evidence:

```text
/tmp/camifit-e2e/kg-memory-after-first-visible.png
/tmp/camifit-e2e/kg-memory-after-followup.png
```

## Fixes Applied During Verification

- Drained `codex app-server` stderr in `CodexAppServerClient`; the server emits repeated warnings and an unread pipe can block the child process.
- Cleared stdout/stderr readability handlers on termination.
- Stopped the Codex child in `ContentView.onDisappear`.
- Updated `script/build_and_run.sh` to terminate direct child processes before killing the app.
- Set coach turns to `effort: low`.
- Set coach thread cwd to an app-owned persistent workspace:
  `Application Support/CamiFit/AgentThreads/Coach`.

The key GUI blocker was `effort: minimal`. A matching app-server harness returned:

```text
invalid_request_error: The following tools cannot be used with reasoning.effort 'minimal': image_gen, web_search.
```

Switching to `effort: low` made the protocol harness complete in about 6 seconds and made the visible GUI E2E pass.

## Thread Workspace Policy

`/tmp` was a verification workaround only. Production CamiFit coach threads use
`Application Support/CamiFit/AgentThreads/Coach` as the Codex thread `cwd`, so
the app does not depend on a disposable directory when relaunched.

Live verification after the policy change:

```text
/Users/kelly/.codex/sessions/2026/06/05/rollout-2026-06-05T17-17-41-019e99dd-0ba5-7391-89eb-6080d9a0f197.jsonl
cwd=/Users/kelly/Library/Application Support/CamiFit/AgentThreads/Coach
```

This directory is the app-owned coach workspace, not the KG writer. Member facts
and memory updates still persist through the validated KG overlay under:

```text
Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl
```

Codex may still write its own JSONL audit/session logs under `~/.codex/sessions`;
those files are Codex's external logs, while CamiFit's durable runtime state lives
under Application Support.

## Verdict

The requested full in-app E2E passed on 2026-06-05:

- the LLM produced a KG operation proposal;
- the app validated and appended it to the member KG overlay;
- the chat showed a memory-saved artifact instead of raw operation JSON;
- the next chat turn used the saved left-knee memory to avoid jump squats.
