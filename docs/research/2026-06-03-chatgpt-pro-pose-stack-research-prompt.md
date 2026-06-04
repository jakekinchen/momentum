# ChatGPT Pro Research Prompt: CamiFit Pose Stack, ANE/CoreML Upgrade Path, and Dynamic Exercise ID

Research this deeply using current web search and produce a practical architecture memo that can later be turned into a PRD.

Context:
- Product working name: CamiFit.
- End-state product: an always-on exercise trainer that runs primarily on an iPhone, with a similar Mac app for users who want a desktop/webcam setup and better third-party camera options.
- The app should identify what exercise the user is doing without requiring them to manually choose every exercise, track reps/holds/sets, give live form feedback, provide analytics, and optionally guide users through a planned workout.
- The current local implementation direction is a deterministic exercise engine that consumes pose landmarks and runs an Exercise-Program JSON contract with a sandboxed rule DSL. The engine owns rep counting, form rules, hold timing, set tracking, cues, and summaries.
- Existing design baseline: MediaPipe Pose Landmarker as the first pose provider, currently in a Python JSONL worker for the Mac prototype, using VIDEO mode, 33 normalized landmarks, 33 world landmarks, visibility/presence, and `num_poses = 2`.
- The architecture should keep a neutral `PoseFrame`/`PoseProvider` boundary so pose engines can be swapped without rewriting rep/form logic.
- Current product intuition: use fast local pose estimation every frame or at 12-30 pose fps, use local temporal exercise classification over pose windows, and use a sparse multimodal/VLM context pass only occasionally: at workout start, every 30-90 seconds, at suspected exercise transitions, or when local confidence is low. Do not assume sending every frame to a cloud model.
- Need to optimize for iPhone performance, battery, thermal stability, and low-latency feedback. We want to understand whether MediaPipe leaves gains on the table by not using Apple Neural Engine/CoreML, and whether an upgrade path exists.

Research questions:
1. Compare pose-estimation options for iPhone and Mac:
   - MediaPipe Pose Landmarker on iOS/macOS.
   - Apple Vision `VNDetectHumanBodyPoseRequest` and 3D body pose APIs.
   - Core ML custom pose models that can run on CPU/GPU/ANE.
   - TensorFlow Lite Core ML delegate and whether it can realistically help MediaPipe/BlazePose-style models.
   - MLX/MLX Swift feasibility for iOS/macOS inference if relevant.
   - Any other credible Apple-native or cross-platform pose options.
2. For each option, compare:
   - landmark count and semantics, including whether it supports feet, hands-adjacent joints, world/3D landmarks, visibility/presence/confidence, multiple people, tracking, and temporal smoothing.
   - performance path: CPU, GPU/Metal, ANE/CoreML, or unknown.
   - expected latency/fps, energy use, thermal behavior, model size, and integration complexity.
   - quality for bodyweight exercises: squat, push-up, lunge, plank, jumping jack, burpee, sit-up/crunch, mountain climber, curl/press if equipment is visible later.
   - support differences between iPhone and Mac.
   - licensing, API stability, and deployment risk.
3. Specifically investigate MediaPipe on iOS:
   - Does MediaPipe Pose Landmarker use CPU/GPU only, or can it use CoreML/ANE through any official or unofficial route?
   - Are MediaPipe `.task` pose models practically convertible to Core ML?
   - Is the underlying BlazePose model separable enough to port, or is the MediaPipe graph/pipeline the real product value?
   - What would be required to build a CoreML/ANE pose provider that matches MediaPipe's useful outputs?
4. Recommend the best architecture for CamiFit:
   - A v1 path that can ship soon and be accurate enough.
   - A v2/v3 upgrade path that gets maximum benefit from ANE/CoreML where it matters.
   - Whether to run one pose provider, multiple providers, a cascade, or an A/B benchmark harness.
   - How to preserve Mac/iPhone parity while still taking advantage of device-specific acceleration.
5. Dynamic exercise identification:
   - Design a local classifier that identifies exercises from rolling pose windows without the user selecting each exercise.
   - Compare deterministic heuristics, traditional ML, CoreML temporal models, TCN/LSTM/Transformer-style classifiers, embedding + nearest-neighbor approaches, and hybrid methods.
   - Include confidence gating, transition detection, unknown/ambiguous exercise handling, and how to avoid false positives during setup/rest/no-person intervals.
   - Explain how sparse VLM/multimodal calls should be used for scene context and priors, not per-frame tracking. The VLM may request more sparse frames until it reaches confidence, then local pose tracking owns the continuous loop.
6. Guided workout mode:
   - Propose how the app should provide a workout plan, guide the user through exercises, and still allow auto-detection when the user deviates or improvises.
   - Include how plan context should bias the exercise classifier without making it brittle.
7. Benchmark and validation plan:
   - Define real-device benchmark methodology for iPhones and Macs.
   - Include metrics: end-to-end pose latency, pose fps, UI feedback latency, energy, thermal throttling, CPU/GPU/ANE usage, landmark stability, no-pose false reps, rep-count accuracy, form-cue precision/recall, exercise-ID F1/confusion matrix, model load time, memory, and battery drain over 20-30 minute sessions.
   - Mention Apple tooling where relevant, such as Instruments, Core ML performance reports, Xcode, and any MediaPipe/TFLite profiling approaches.
   - Include a small golden-fixture dataset plan and live-camera acceptance criteria.
8. Produce a PRD-ready output:
   - Clear recommendation.
   - Option comparison table.
   - Proposed system architecture.
   - Milestone plan from prototype to production.
   - Risks, unknowns, and decision gates.
   - Concrete experiments to run in the next 1-2 weeks.
   - Source links, prioritizing official docs, credible benchmarks, papers/model cards, and production engineering references.

Important constraints:
- Be practical and opinionated. Distinguish sourced facts from synthesis/recommendations.
- If a fact depends on iOS version, chip generation, model variant, or API version, say so explicitly.
- Do not optimize for a cloud-only product. The continuous tracking loop should be local and low-latency.
- Do not assume the user manually selects every exercise. Auto exercise ID is a core product requirement, with an optional guided-workout mode for users who want structure.
- The answer should help us decide whether to keep MediaPipe for v1, add Apple Vision as a provider, invest in CoreML/ANE pose, or use CoreML mostly for temporal exercise classification over pose landmarks.
