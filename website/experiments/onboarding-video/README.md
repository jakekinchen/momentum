# Onboarding Movement Video Experiment

This experiment captures the macOS SwiftUI onboarding movement visual into
web-ready loop assets without modifying the app or website homepage.

```bash
cd /Users/kelly/Developer/camifit-app
website/experiments/onboarding-video/capture-swiftui-onboarding.sh
```

The script builds a temporary Swift package under this experiment directory,
copies `Sources/CamiFitApp/OnboardingView.swift` and `BrandLogoMark.swift`,
then appends an AppKit-only capture wrapper to the copied onboarding source.
That wrapper renders the existing private `OnboardingFeatureVisual(stepID:
.movement)` from SwiftUI in a short-lived borderless window, captures the
`NSHostingView` display cache into PNG frames, and uses `ffmpeg` to encode the
frames into lightweight website assets.

Default outputs:

- `website/public/app-assets/onboarding/movement-tracking-swiftui-poster.jpg`
- `website/public/app-assets/onboarding/movement-tracking-swiftui.mp4`
- `website/public/app-assets/onboarding/movement-tracking-swiftui.webm`

Useful overrides:

```bash
WIDTH=960 HEIGHT=408 \
  website/experiments/onboarding-video/capture-swiftui-onboarding.sh
```

For a quick proof slice instead of the full metric-counter loop:

```bash
FPS=30 DURATION_SECONDS=2.4 \
  website/experiments/onboarding-video/capture-swiftui-onboarding.sh
```

Set `KEEP_CAPTURE_TMP=1` to keep the temporary package and PNG frame sequence
for inspection.
