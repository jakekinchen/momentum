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

Result: FAIL / BLOCKED for the full visible in-app E2E.

The app was launched with:

```bash
: > "$HOME/Library/Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl"
./script/build_and_run.sh --verify
```

The prompt was sent through the visible SwiftUI chat field by accessibility control:

```text
I have left knee pain, please remember this for future workouts.
```

Observed GUI state after the first full watchdog attempt:

```text
AXStaticText | I have left knee pain, please remember this for future workouts.
AXStaticText | ⚠️ Codex did not respond in time.
```

Overlay evidence:

```text
0 /Users/kelly/Library/Application Support/CamiFit/KnowledgeGraph/overlays/member/current.jsonl
```

Current app session evidence after applying stderr-drain, stale-child cleanup, minimal effort, and `/tmp` cwd fixes:

```text
/Users/kelly/.codex/sessions/2026/06/05/rollout-2026-06-05T16-01-24-019e9997-374e-7c33-ae7e-109d3350059e.jsonl
meta=["019e9997-374e-7c33-ae7e-109d3350059e", "/tmp"]
turn=["019e9997-4b3c-72a0-b3ec-90798a4e0171", "/tmp", "gpt-5.5", "minimal", "auto"]
counts={"message"=>3}
```

The app-server session records the user message but no reasoning item and no assistant message. Since the app never receives the LLM response, it cannot parse an operation, append the overlay, render the artifact, or prove subsequent-chat behavior in the GUI.

## Fixes Applied During Verification

- Drained `codex app-server` stderr in `CodexAppServerClient`; the server emits repeated warnings and an unread pipe can block the child process.
- Cleared stdout/stderr readability handlers on termination.
- Stopped the Codex child in `ContentView.onDisappear`.
- Updated `script/build_and_run.sh` to terminate direct child processes before killing the app.
- Reduced coach turns to `effort: minimal`.
- Set coach thread cwd to `/tmp`, matching the successful protocol harness.

These fixes are valid hardening, but they did not make the visible GUI E2E pass on 2026-06-05.

## Verdict

Planning and bridge implementation are ready enough to review, but the requested full in-app E2E is not complete yet.

The next blocking issue is the GUI-launched Codex app-server turn lifecycle: the turn is accepted and logged, but the model turn does not produce reasoning or assistant output before the app watchdog. The KG memory parser/store path should not be treated as the active blocker until the GUI app-server turn returns a response.
