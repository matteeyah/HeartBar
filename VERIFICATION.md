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
| Demo background behavior | Real demo source publishes all three friends and changes menu-bar values while all windows are hidden. |
| Panel configuration | Programmatic checks verify nonactivating behavior, inability to become the key/main window, first-click acceptance, all-Spaces/full-screen flags, width, and saved visibility. |
| Appearance | Rendered and visually inspected the real sidebar in light and dark mode, plus popover, empty state, and all three settings sections. |
| Xcode project | Property lists parse; all object references and source paths resolve; a shared app scheme and unit-test target are included. |

The suite exercises protocol messages, topic routing, invalid payloads, join rejections and timeouts, bounded backoff, reconnect cancellation, the exact stale-reading boundary, immediate loss of live status on failure, credential replacement/removal, failed credential-write handling, late-event rejection, persistence, reordering, demo separation, sleep/wake transitions, and the favorite limit.

Reproduce with:

```sh
Scripts/swift.sh test
Scripts/build-app.sh --universal
Scripts/verify-ui.sh
```

The UI harness uses in-memory settings and never accesses the real Keychain. PNGs are written to `build/previews/`. Temporary render windows are never ordered onscreen. The Command Line Tools test wrapper selects the legacy SwiftPM test runner because this toolchain's default runner requires full Xcode; its deprecation warning is expected. The universal build emits an SDK-level Intel deprecation warning, but both output slices have a verified macOS 14.0 minimum.

## Remaining interactive or external checks

- **Live HypeRate:** no API key or active friend ID was supplied. Enter these in Connection/Friends settings, turn off Demo mode, and confirm live BPM with the sender. Demo and fake-transport tests do not establish service compatibility.
- **Full Xcode:** open the project with Xcode 16+ and run Cmd-R/Cmd-U to validate its app/test targets, sandbox entitlement behavior, and Keychain access. The app was built and run through the separate SwiftPM path here.
- **Focus:** while typing in another app, click a sidebar star and leave it visible for several reading updates; the other app should retain keyboard focus. Open Settings and verify typing and Cmd-V in the API-key field.
- **Spaces/full screen:** move between Spaces and enter another app's full-screen mode; confirm sidebar placement. Automated checks validate collection behavior flags, not WindowServer transitions.
- **Multiple displays:** select another display, move/resize the sidebar, relaunch, disconnect the selected display, then reconnect it. Check saved placement and fallback. This needs actual display changes.
- **Real sleep/wake:** sleep and wake the Mac while streaming. Connections should resume and values remain unavailable until a new reading. Tests verify source lifecycle transitions without sleeping this Mac.
- **VoiceOver:** read each card, favorite/retry controls, menu-bar item, and settings. Accessibility labels are implemented; a spoken VoiceOver pass remains pending.
- **Intel/macOS 14 hardware:** the Intel slice cross-compiles but has not run on an Intel Mac or a macOS 14 installation.

Signed distribution, a custom Watch app, historical recording, and Events-roster import are outside this version.
