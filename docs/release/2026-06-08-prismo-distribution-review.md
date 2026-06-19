# Prismo/Remixel Distribution Review for Momentum

Date: 2026-06-08

Source reviewed: `/Users/kelly/.openclaw/workspace-mac-factory/projects/prismo-macos`

## Observations

1. Prismo keeps product identity centralized before release work runs. Scripts read generated identity values for app name, bundle id, support paths, release naming, download URLs, and update URLs instead of repeating constants.
2. The release workflow is split into named gates: environment check, dry run, external archive, external DMG packaging, notarization, publish, release health, live readiness, rollback, and origin-main fast lane.
3. The fast lane builds from a clean temporary checkout of `origin/main`, which avoids accidentally shipping local dirty state.
4. The direct-distribution path is the active release lane. Tests assert that MAS/TestFlight paths are not referenced by current release scripts and runbooks.
5. The installer DMG is not a raw folder image. It is a read-write DMG first, then Finder metadata is configured before converting to compressed UDZO.
6. The DMG window has a rendered background that says how to install the app and uses the app icon plus an Applications target.
7. The DMG layout is set through Finder AppleScript: icon view, hidden toolbar/status bar, fixed bounds, icon size, text size, background picture, and explicit icon positions.
8. Prismo creates an Applications alias through Finder. Momentum currently uses a symlink to `/Applications`, which is easier to verify in scripts and still behaves correctly in Finder.
9. The final DMG is signed with Developer ID Application after conversion.
10. Notarization is explicit for both the app archive and the DMG. The app is stapled before it is inserted into the public DMG, and the DMG is stapled afterward.
11. Notary submissions write JSON logs so failures can be inspected after the fact.
12. Gatekeeper checks are run on both the app bundle and the DMG with `spctl`.
13. The release scripts emit machine-readable `key=value` outputs for paths, status, notarization logs, and artifact metadata.
14. The publish step signs Sparkle updates with EdDSA and verifies the Sparkle-reported length against the actual artifact size.
15. Artifact publishing uses immutable versioned object keys for the DMG and release metadata.
16. A mutable `latest.json` pointer is published with no-cache headers, separating stable archive bytes from the update discovery document.
17. Release metadata includes version, build, channel, published date, minimum macOS version, SHA-256, file size, direct download URL, release page URL, support URL, and Sparkle signature.
18. Public download URLs and update URLs come from the direct distribution profile rather than being hard-coded in app code.
19. Sparkle configuration is bootstrapped into generated public env files with the public key, appcast URL, and scheduled update interval.
20. The app embeds Sparkle and validates `SUFeedURL` and `SUPublicEDKey` in tests.
21. The app exposes update state through an app-level update-support model, including automatic-check/download settings and manual update checks.
22. Release health checks validate the installed app bundle, bundled frameworks, metadata, privacy manifest, bundled Node/runtime payloads, and update config.
23. Live release checks hit the public appcast, update API, and versioned download route after publish.
24. A rollback script exists as part of the release surface, not as an afterthought.
25. The local development refresh path is also documented: rebuild/install, kill the running installed app, and reopen the installed bundle.

## Applied to Momentum Now

1. Momentum now renders a branded installer background at release time.
2. Momentum now creates the DMG through a read-write layout pass, configures Finder presentation, then converts to a compressed signed DMG.
3. Momentum keeps the `/Applications` symlink and verifies it during smoke tests because it is deterministic and easy to assert.
4. Momentum now has a release health check script that validates the app bundle, Info.plist naming, pose-worker payload, signing, stapling, DMG contents, and optional live download bytes.

## Recommended Next Phase

1. Add a Momentum release profile that centralizes bundle id, app name, version/build, support URL, download URL, update API URL, and appcast URL.
2. Generate release metadata JSON beside every public DMG and publish a mutable latest pointer.
3. Add a website update endpoint that can return the latest Momentum macOS release metadata.
4. Add Sparkle to the macOS app once the release metadata contract is stable.
5. Add tests for release-surface drift so old ZIP or stale CamiFit naming cannot re-enter the public path.
6. Add a one-command clean-release lane that builds from a clean checkout, then publishes and verifies the live download URL.
