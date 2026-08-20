# Cross-Platform Rendering Handover

Status: **implemented** — shared `WidgetRender` target, in-app preview unification, Catalyst Mac app
(in `mac-app/`), and iCloud script sync landed. See `docs/implementation-notes.md`
(2026-08-20 entries) and the "Known limits" caveat (WidgetKit `.appex` is not re-hosted on the Mac;
iCloud/Keychain sharing still needs a signed, provisioned build to verify).

This document is a focused handover for the next engineer who takes up making the
stupid widgets renderer run on both iOS and macOS. It captures the decisions reached,
the constraints discovered while probing, and the exact refactor to perform. It is
deliberately separate from the CLI (`stupid-app`) work in `stupid-ios-dev` — this is an
app-level change inside `stupid-widgets` and does not require touching the CLI.

## Goal

**One shared widget rendering engine across:** the CLI-built iOS app, its iOS WidgetKit
extension, and an Xcode-based Mac app (native or Catalyst) — without duplicating the
render code or letting it drift.

## How the renderer already works today

There are two renderers in the app, and they already embody the correct shape:

- `Sources/StupidWidgets/WidgetExtensionSupport.swift` defines an intermediate
  **`ScriptWidgetSnapshot`** — pure `Sendable` value types (colors as float components,
  fonts as metadata, images as `Data`) — plus **`ScriptWidgetSnapshotView`**, a nearly
  pure-SwiftUI view that renders that snapshot. Its only `UIKit` touch is one
  `UIImage(data:)` at the former site of `Image(uiImage: ...)`.
- `Sources/StupidWidgets/WidgetRenderer.swift` renders the **live `ListWidgetModel`** —
  the JavaScriptCore bridge objects that hold `UIColor`/`UIFont`/`UIImage`. This is the
  deeply `UIKit`-coupled renderer, used for the in-app live preview.

`ScriptWidgetRunner.run(...)` (also in `WidgetExtensionSupport.swift`) already converts a
`ListWidgetModel` → `ScriptWidgetSnapshot`, so the platform-neutral boundary already
exists and is already exercised by the widget extension.

## Recommended plan (lowest lift)

Adopt the `ScriptWidgetSnapshot` → SwiftUI pipeline as the **single** render path in both
the in-app preview and every widget extension, which removes `WidgetRenderer` entirely.

1. **Move the snapshot value types + the shared view into a new macOS-clean SwiftPM
   target**, e.g. `WidgetRender`:
   - `ScriptWidgetSnapshot` + all `ScriptWidget*` value types (from
     `WidgetExtensionSupport.swift`).
   - `ScriptWidgetSnapshotView` + a cross-platform `Image(widgetImageData:)` helper.
   - `Platforms: [.iOS(.v17), .macOS(.v14)]` and **no `UIKit`/`AppKit`/`JavaScriptCore`
     dependency** — only SwiftUI. The one platform seam is the `Image` init:
     ```swift
     #if canImport(AppKit)
     self.init(nsImage: NSImage(data: data) ?? NSImage())
     #elseif canImport(UIKit)
     self.init(uiImage: UIImage(data: data) ?? UIImage())
     #endif
     ```
2. **Replace use of `WidgetRenderer` with the snapshot path** so the in-app live preview
   snapshots the running `ListWidgetModel` and renders `ScriptWidgetSnapshotView`. Delete
   `WidgetRenderer.swift` (its logic is duplicated by `ScriptWidgetSnapshotView`).
3. Pun `ScriptWidget*` types found in tests/extension to reference `WidgetRender` instead
   of the core module.

## Repo layout for sharing with the Mac app

Keep `ScriptWidgetSnapshot`/`ScriptWidgetSnapshotView` as a standalone target inside the
existing `stupid-widgets/Package.swift`, then have **both** build systems depend on that
same local package (no code copying):

```text
stupid-widgets/
├── stupid-widgets/                     # SwiftPM package (CLI-built iOS app)
│   ├── Package.swift
│   └── Sources/
│       ├── WidgetRender/  ▲            # SHARED: snapshot types + view (mac-clean)
│       ├── StupidWidgets/              # JS bridge + models + store (iOS/UiKit)
│       └── StupidWidgetsWidgetExtension/
└── mac-app/                            # Xcode project (native or Catalyst)
    └── StupidWidgetsMac.xcodeproj       # adds local package dep → WidgetRender
```

Rule: anything touching `UIKit`/`JavaScriptCore` stays **out of** `WidgetRender`.
`WidgetRender` only consumes `Sendable snapshot values.

## Mac app choice: Catalyst vs native

This drives the whole repo split:

- **Catalyst (recommended, also re-hosts the widget `.appex`):** the Mac app imports
  `StupidWidgetsCore` (the JS bridge + models run under Catalyst unchanged) *and*
  `WidgetRender`. Both script execution and rendering share, and the existing WidgetKit
  `.appex` is re-hosted on the Mac. Lowest total code. UI note: Catalyst runs
  `UIKit`, so `WidgetExtensionSupport.swift`'s `UIColor`/`UIImage` code needs no port.
- **Native macOS:** import only `WidgetRender` (fully platform-native), but the
  JavaScriptCore bridge + model layer still isn’t written for a non-`UIKit` host, so the
  JS→model conversion would need a separate implementation. Lowest *render* lift, but
  higher *port* cost for script execution.
- **CLI `platform mac`/Catalyst via the CLI: rejected** (see “Constraints”).

## Constraints discovered while probing

- Catalyst on this host is **not** reachable through the CLI’s ordinary `swift build`
  pipeline. It needs the `MacOSX.sdk` plus its `System/iOSSupport` sub-sysroot merged,
  which plain `swift build` does not do, and this specific machine has two Xcodes
  (`Xcode.app`, `Xcode-26.1.1.app`) whose Catalyst `swiftmodule` (built with the `.4.7`
  compiler) mismatches the selected `.4.8` toolchain → `failed to build module 'Swift'`.
  Catalyst builds work, but should go through **Xcode**, not the CLI.
- Native macOS (`swift build --sdk macosx --triple arm64-apple-macosx`)
  **builds cleanly** in the CLI’s model — this is the only mac path feasible to the CLI.
- Therefore: for real cross-platform widgets, **don’t extend the CLI**; do the Mac app in
  Xcode and share the renderer via the `WidgetRender` target. (A CLI native-mac “platform
  mac” lane remains viable later if a standalone, non-widget Mac app is ever wanted.)

## iCloud script sync (related, also app-level)

Chosen approach: **iCloud Documents (ubiquitous container) + the existing app-group
mirror.**

- Point `ScriptStore`’s directory at the iCloud container instead of `:documentDirectory`
  (same `NSUbiquitousKeyStore`-style file operations; no model change).
- Add the `com.apple.developer.ubiquity-container-identifiers` entitlement to both the
  iOS app and the Mac app (same container `iCloud.<TeamID>.net.stupidtech.stupidwidgets`).
- Observe container changes (e.g. `NSMetadataQuery` or `NSUbiquitousKeyValueStore` change)
  and call the existing `ScriptStore.reload()` so edits on one device appear on the other.
- Keep the app-group mirror for the WidgetKit extension (it can’t read iCloud directly on
  each timeline refresh) — the existing `syncWidgetScripts()` already maintains that copy.
- Alternative (simplest API, small size): `NSUbiquitousKeyValueStore` holding the
  scripts as a dictionary. Fine if scripts are tiny; otherwise Files is the better fit.

## Suggested order of work

1. `WidgetRender` target split (Plan step 1–3) — smallest and unlocks everything.
2. Replace preview with the shared view / remove `WidgetRenderer`.
3. Verify iOS targets still build and the simulator widget path still renders.
4. Verify `WidgetRender` builds standalone for macOS (`swift build --target WidgetRender`).
5. Mac app in Xcode: Catalyst first (import `StupidWidgetsCore` + `WidgetRender`).
6. iCloud Documents sync (app-level; independent of platform work).

## Verification commands

From `stupid-widgets/`:

- Shared target macOS-clean proof: `swift build --target WidgetRender`.
- iOS simulator compile:
  `swift build --target StupidWidgetsTests --triple arm64-apple-ios-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`.
- Simulator tests:
  `set -o pipefail && xcodebuild test -scheme StupidWidgets-Package -destination "platform=iOS Simulator,id=<UDID>" | xcpretty`.

## Open questions

- Catalyst vs native for the Mac app; Catalyst recommended unless product/App-Store
  MAS constraints (architecture, native mac UI expectations, or notarization) force native.
- Whether iCloud should be the source of truth immediately or behind a toggle (mirror vs
  primary).