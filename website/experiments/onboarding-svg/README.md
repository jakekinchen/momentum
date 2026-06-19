# Onboarding SVG Pixel-Similarity Experiment

This experiment prototypes a web SVG/CSS/JS reconstruction of the macOS onboarding first-slide `MovementTrackingVisual` without touching `website/src/app/page.tsx`.

Open `index.html` directly in a browser. It is intentionally standalone so it can be deleted, snapshotted, or compared without changing the website app route.

## SwiftUI Source Read

Inspected `Sources/CamiFitApp/OnboardingView.swift`:

- `MovementTrackingVisual` is a 250 px tall feature card with an 18 px inset HUD, top `VisualPill` labels, bottom `MetricChip` values, and a centered `PoseFigure` sized 142 x 138 with a -30 px y offset.
- `OnboardingMovementState` is deterministic: a 2.35 second cycle, 9 cycles total, smoothstep squat depth, success glow, reps from 12 through 20, and hold text derived from the counted index.
- `PoseFigure` draws in SwiftUI `Canvas`. Its geometry is formula-driven through `OnboardingPoseFrame`, so it ports cleanly to SVG.
- There is no `MotionEchoFigure` symbol in the current file. The echo behavior is implemented inside `PoseFigure.drawMotionEchoes`, drawing two ghost skeletons at `squat - 0.20` and `squat + 0.20`.
- `VisualPill` and `MetricChip` depend on SwiftUI system colors, SF Symbols, SF font metrics, capsule/rounded-rectangle rasterization, and native text antialiasing.

## Prototype Result

The prototype ports the pose frame geometry and movement state directly, including:

- background gradient and 14 px card radius;
- 18 px HUD padding;
- 76 x 50 metric chips with 9 px spacing;
- 142 x 138 pose viewport and -30 px vertical offset;
- mannequin strokes, mint skeleton, joint dots, motion echoes, and success glow.

It is plausible for product-level visual resemblance. It is not a plausible path to guaranteed 95% pixel similarity by itself because several visible parts are platform-rendered differently in SwiftUI and the browser.

## What A 95% Pixel Similarity Loop Would Need

1. Refactor or test-host the SwiftUI visual with an injectable clock/phase, rather than `TimelineView(.animation)` using wall time.
2. Capture native reference frames at a fixed card size, likely 564 x 250 CSS points at a fixed display scale, through XCTest snapshots or an `ImageRenderer` harness.
3. Capture browser frames with Playwright at the same viewport, scale factor, color profile, and fixed phase.
4. Replace browser approximations for SF Symbols with exported/vector-equivalent symbols, and lock font rendering as closely as possible to SF Pro on macOS.
5. Normalize color management and antialiasing expectations before diffing. Raw pixel equality will over-penalize Canvas/SVG stroke edges and text.
6. Compare a frame set across the 2.35 second cycle with an image diff tool that reports both strict pixel difference and perceptual similarity.

## Recommendation

Pursue this only if the goal is automated visual-regression coverage for the onboarding card. For the marketing website or a web demo, the SVG reconstruction is good enough as a hand-matched approximation, but a 95% pixel-similarity target would spend most of its cost fighting renderer differences in text, symbols, blur, and antialiasing rather than improving user-visible quality.
