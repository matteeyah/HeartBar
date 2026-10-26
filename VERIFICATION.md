# Verification

Validated locally on October 26, 2026, using Apple Swift 6.4 Command Line Tools on Apple Silicon. Full Xcode is not installed on this Mac.

## Completed

| Check | Result |
| --- | --- |
| Swift Testing suite | 28 tests in four suites passed, including seven invalid-reading parameter cases. |
| Release app | Built a universal `HeartBar.app`; `lipo` confirms `arm64` and `x86_64`. |
| Minimum OS | `vtool` reports macOS 14.0 for both architectures. |
| Bundle signature | Ad-hoc signature passes `codesign --verify --deep --strict`. |
| Launch | Opened the packaged app through Launch Services and confirmed its process remains running. |
| Background behavior | An injected screenshot-only source publishes three sample friends and changes menu-bar values while all windows are hidden. |
| Appearance | Rendered and visually inspected the popover in light and dark mode, the empty state, and the Friends and Connection views. |
| Preferences compatibility | Saved friends and favorites still load when obsolete demo or placement settings are present; subsequent saves omit the removed settings. |
| Xcode project | Property lists parse; all object references and source paths resolve; a shared app scheme and unit-test target are included. |

The suite exercises protocol messages, topic routing, invalid payloads, join rejections and timeouts, bounded backoff, reconnect cancellation, the exact stale-reading boundary, immediate loss of live status on failure, credential replacement/removal, failed credential-write handling, startup without an API key, late-event rejection, persistence, reordering, sleep/wake transitions, and the favorite limit.

Reproduce with:

```sh
Scripts/swift.sh test
Scripts/build-app.sh --universal
Scripts/verify-ui.sh
```

The UI harness uses an injected sample source and in-memory settings, never the real Keychain or a network connection. The simulator lives only in `Scripts/VerifyUI.swift`, outside the app targets. PNGs are written to `build/previews/`. Temporary render windows are never ordered onscreen. The Command Line Tools test wrapper selects the legacy SwiftPM test runner because this toolchain's default runner requires full Xcode; its deprecation warning is expected. The universal build emits an SDK-level Intel deprecation warning, but both output slices have a verified macOS 14.0 minimum.

## Remaining interactive or external checks

- **Live HypeRate:** no API key or active friend ID was supplied. Enter these in Connection/Friends settings and confirm live BPM with the sender. Screenshot fixtures and fake-transport tests do not establish service compatibility.
- **Full Xcode:** open the project with Xcode 16+ and run Cmd-R/Cmd-U to validate its app/test targets, sandbox entitlement behavior, and Keychain access. The app was built and run through the separate SwiftPM path here.
- **Interaction:** open and dismiss the menu-bar popover, toggle favorites, and open Settings. Verify typing and Cmd-V in the API-key field.
- **Real sleep/wake:** sleep and wake the Mac while streaming. Connections should resume and values remain unavailable until a new reading. Tests verify source lifecycle transitions without sleeping this Mac.
- **VoiceOver:** read each card, favorite/retry controls, menu-bar item, and settings. Accessibility labels are implemented; a spoken VoiceOver pass remains pending.
- **Intel/macOS 14 hardware:** the Intel slice cross-compiles but has not run on an Intel Mac or a macOS 14 installation.

Signed distribution, a custom Watch app, historical recording, and Events-roster import are outside this version.
