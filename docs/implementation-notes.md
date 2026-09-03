# Implementation Notes

## 2026-09-03 — Release 1.0.0 (14) to public TestFlight

- Bumped `CFBundleVersion` 13 → 14 in both `Info.plist` and `WidgetExtension-Info.plist` (marketing
  version stays `1.0.0`), passed `release preflight`, archived, and uploaded build
  `628a5fd8-17bd-48b2-9735-39b37d151eac`.
- Added the build to the `External Testers` beta group and submitted external review; App Store
  Connect now reports **external beta `IN_BETA_TESTING`** (public TestFlight live). The CLI's initial
  "timed out awaiting external review" was just the wait window expiring before Apple completed
  review.
- Release manifest and IPA live under untracked `.release/` (never committed).

---

## 2026-09-03 — Coding Assistance section rework: Provider + Instructions rows

- The Settings **Coding Assistance** section now has two chevron rows:
  - **Provider** — trailing value `ChatGPT` / `None` in the same secondary (gray) styling as the
    existing right-aligned values.
  - **Instructions** — pushes the (renamed) instructions editor.
- A new **Provider** screen is pushed from the Provider row and shows the Provider value, the Account
  email (extracted from the access/id-token JWT `https://api.openai.com/profile.email` claim), and a
  Sign Out button; the signed-out state shows a Connect ChatGPT button and no account row.
- The instructions editor title now reads "Instructions" (was "Coding Assistant Instructions").
- Verified on the `NoFeed 6.5 iPh11PM` simulator: main settings shows `Provider ChatGPT ›` and
  `Instructions ›`; the Provider screen shows Provider=ChatGPT, Account=stephan@stephancill.co.za,
  and Sign Out. Not installed to the iPhone per request.

---

## 2026-09-03 — Settings polish: account email, chevron editor, iCloud instructions

- **ChatGPT row simplified**: the settings section now shows a plain `ChatGPT` row (no leading
  icon, no tinting) with the account **email right-aligned** and a **Sign Out button on its own row
  below**; signed-out state keeps a plain Connect button. Auth errors render as a neutral caption.
- **Account email source**: no extra API call needed — the ChatGPT access-token JWT already carries
  `https://api.openai.com/profile.email` (plus `email` on the id-token). `OpenAICredential` gains an
  `email` field; `AIClient` extracts it at sign-in/refresh, and `loadCredential()` backfills it from
  the stored access token so existing sessions show the email without re-auth (e.g. the simulated
  session resolved `stephan@stephancill.co.za` from the stored token). Token/claim decode was
  refactored into a shared `jwtClaims(from:)` helper.
- **Coding Assistant Instructions row**: the settings sheet now has a `NavigationLink` row with the
  automatic trailing chevron that pushes a dedicated editor (`AssistantInstructionsEditorView`)
  instead of an inline `TextEditor`. The editor uses `.font(.body)` (not monospaced), and the
  **Reset button moved to the top-right toolbar** of the editor screen.
- **iCloud sync**: instructions are stored in `NSUbiquitousKeyValueStore` (key `assistantInstructions`)
  in addition to UserDefaults; `AssistantSettings` loads iCloud-first, observes external
  `didChangeExternallyNotification` changes, and persists both stores on every edit so the style guide
  follows the user's devices. Verified in-app: edit persisted to UserDefaults, Reset restored the
  default and cleared the test marker, and the app kept running (the ubiquitous store write did not
  crash the stripped-entitlement simulator build).
- Not installed to the iPhone per request — verified on the `NoFeed 6.5 iPh11PM` simulator only
  (with the documented stripped-entitlement launch workaround), reusing the simulator's stored ChatGPT
  credential.

---

## 2026-09-03 — Settings, widget-library tools, in-memory chat history, message rewind

- Added a **Settings** gear button to the script list's top-right toolbar
  (`ScriptListView`) opening a new `SettingsSheet`:
  - **ChatGPT connection management** — shows signed-in status with Connect/Sign Out,
    including in-flight sign-in state and OAuth errors. (Previously there was no sign-out
    affordance in-app; the old disconnect action had been removed.)
  - **Coding Assistant Instructions** — an editable `TextEditor` whose contents are
    injected into every coding-assistant conversation. Persisted in UserDefaults under
    `net.stupidtech.stupidwidgets.assistantInstructions`; pre-populated with a Hello
    Widget style guide (dark navy `#1b1b2f`, `#16222A → #3A6073` vertical gradient with
    locations `[0, 1]`, white bold 16 pt title, medium 13 pt date at 0.85 opacity,
    `addSpacer(8)`, vertical layout) plus a "Reset to Hello Widget Style" button.
    `AssistantSettings` (new file) is a shared `ObservableObject` and feeds
    `AgentAIClient.systemPrompt` via `AssistantSettings.current()`.
- Added two **widget-library tools** so the coding assistant can reuse existing widgets:
  `search_widgets(query)` (case-insensitive name substring → names + line counts) and
  `read_widget(name, offset?, limit?)` (bounded, one-based numbered lines of another
  widget). The model is told it may inspect other widgets but only modify the one being
  edited. `AgentAIClient.chat` now receives the current `[WidgetReference]` snapshot
  (name + source of every script in the store) and passes it into `ScriptAgentTools`.
- Chat history is now **persisted in memory** across follow-up messages:
  - New `AgentConversation` (`@MainActor`) holds the full Responses input-item list
    (user messages, reasoning continuations, `function_call`/`function_call_output`,
    assistant `output_text` summaries). `AgentAIClient.chat` seeds its working input from
    it, appends every turn's item, and writes the result back before finishing or failing,
    so follow-ups carry the complete session (including prior tool calls). The final
    assistant output text is now also appended to the conversation for the next turn.
    Nothing here is written to disk, so the history does not survive force quits.
  - `ChatViewModel` drops `messageInput`; `send` no longer needs the old messages-only
    input, and `messages` stays as lightweight bookkeeping for the rewind truncation.
- Reworked **Undo into per-message rewind** (`ChatViewModel.undo()`):
  - Each message that changes the script records a `ChatRewind` (prompt, source-before,
    pre-message message/item counts) in `rewindRecords`.
  - Undo now pops that record, truncates both `messages` and `AgentConversation.items`
    back to before the previous message, restores `source`, **re-populates the prompt
    field with that message's text**, and reruns — so the user sees the request that was
    rewinded. EditorView no longer keeps its own `undoSources`/`pendingUndoSource` stack.
- Fixed a `read_widget` bug found by the new tests: a `guard let name = … , let widget =
  …` combined guard leaked the *tool name* (`read_widget`) into the "No widget named …"
  error path (guard-bound constants aren't visible inside the `else`). Split into two
  guards so the error reports the real requested name.
- Tests: added `search_widgets`, `read_widget` (found + rejection), and
  `AgentConversation` truncation/replace coverage. All 38 simulator tests pass through the
  generated `StupidWidgets-Package` scheme.
- Simulator verification (NoFeedSocial + NoFeed 6.5 iPh11PM) required the documented
  iCloud-entitlement launch workaround (re-sign a copy with only
  `com.apple.security.application-groups`). Verified on `NoFeed 6.5 iPh11PM`
  (`F3CC8933-53E2-4FA5-9754-908812BBDC1B`): settings sheet opens from the gear, shows
  Connect (signed out) / instructions pre-populated with the style guide / footer / Reset
  button, and the detail view still renders Hello World with the signed-out
  "Edit with ChatGPT" pill. Signed-in undo/history E2E needs OpenAI credentials.

---

## 2026-09-03 — Added `stupid-widget-creator` skill

- Created `skills/stupid-widget-creator` in this repository: an opencode skill for creating,
  designing, and debugging stupid widgets (`.widget` JavaScript scripts for the app).
- `SKILL.md` covers the creation workflow, script anatomy (`config.runsInWidget`,
  `Script.setWidget`, `Script.complete`, `presentMedium()` preview branch), data-source guidance with
  `Request`, and the hard limits of the current implementation.
- `references/api.md` documents the implemented JS bridge subset and the `.widget` JSON envelope
  (fields, palette/glyph metadata, UUID), plus a validation checklist.
- `references/design.md` covers family sizes (small 155×155 / medium 329×155 / large 329×345 /
  extraLarge 345×345), layout guidance, refresh strategy, graceful-degradation patterns, and
  verification steps.
- `scripts/make_widget.mjs` wraps a JS source file into a valid `.widget` envelope (random UUID,
  correct JSON escaping); verified with a sample script, passes oxlint.
- `assets/starter.widget` is a ready-to-copy starter envelope.
- Documented the rendering limitations so agents avoid no-op members: `WidgetText` shadows,
  `WidgetStack` backgrounds/size/corner/border, `WidgetImage` border/tint, `Color.dynamic`, and
  `url` (stored, not tappable) — stacks render only layout, spacing, and children.
- Symlinked to the global skills collection at
  `~/.config/opencode/skills/stupid-widget-creator` and added a ground rule to `AGENTS.md` requiring
  the skill be kept in sync whenever the implemented API, rendering behavior, or `.widget` format
  changes.

---

## 2026-08-30 — Populated App Store listing via ASC API

- Attached build 13 to the existing App Store version `1.0`
  (`PREPARE_FOR_SUBMISSION`) — build marketing version is `1.0.0`, ASC accepted the
  `1.0` version once the build was attached.
- Populated the `en-GB` localization via the ASC API (custom ES256 JWT from
  `asc.key.pem`): **description** (from `docs/app-store-copy.md`), **keywords**,
  **promotional text**, **support URL** (`https://stupidtech.net`) — confirmed `SET`.
  `whatsNew` is state-locked ("cannot be edited at this time"); set via ASC UI.
- Uploaded **11 screenshots** via the reserved-file-upload flow. Critical constraint:
  ASC rejects screenshots that don't match the device's exact aspect ratio
  (`IMAGE_INCORRECT_DIMENSIONS`). The padded `styled/` images were all rejected; a new
  `ratio/` generator writes caption + device inside the native canvas, which ASC accepts
  (all `assetDeliveryState = COMPLETE`):
  - `APP_IPHONE_67`: 7 (17 Pro Max ×5 + 16 Plus ×2)
  - `APP_IPHONE_61`: 2 (17 Pro)
  - `APP_IPAD_PRO_3GEN_129`: 2 (iPad resized to 12.9″ 2048×2732; 13″ 2064×2752 is an
    unrecognized dimension)
- API gotchas: use `cryptography` raw ES256 (openssl `dgst` emits DER → `401`), do
  **not** send the JWT `Authorization` header to the AWS presigned upload URL (→ `400`),
  and space requests ~3s to avoid intermittent `401`/429.

---

## 2026-08-30 — App Store submission: version 1.0.0 (13) uploaded

- Declared `CFBundleShortVersionString = 1.0.0` in both `Info.plist` and
  `WidgetExtension-Info.plist` (previously they only carried `CFBundleVersion`; the
  build injected the marketing version, but `release preflight` required it stated
  statically).
- Bumped both plists in lockstep to build **13** (1.0.0(13)) via
  `stupid-app release bump --build-number 13`.
- `release preflight` passed; `release archive` produced a signed, post-verify IPA at
  `.release/StupidWidgets.ipa` (SHA-256 `1a3813d5…`); `release upload --wait` landed
  build `23afa67e` in App Store Connect.
- Live ASC state: processing `VALID`, internal beta `IN_BETA_TESTING`, external beta
  `READY_FOR_BETA_SUBMISSION`. Release manifest at `.release/release-manifest.json`.
- App Store listing (description/keywords/screenshots) is now **populated via the API**
  (see above); the remaining manual fields are app subtitle and What's New, set in
  App Store Connect.

---

## 2026-08-30 — App Store listing kit (screenshots + feature list) and simulator AI credential

- Prepared the App Store submission content (screenshots + feature list) and seeded a
  ChatGPT credential for the simulator AI flow.
- Built and installed the current app on four simulators (iPhone 17 Pro, 17 Pro Max,
  16 Plus, iPad Pro 13″), each image captured at native resolution:
  `docs/app-store-listing.md` maps each file to its App Store slot. Raw PNGs live in
  `.release/screenshots/` (untracked).
- The remits used come from the existing seeding pattern in `ScriptStore`; the three
  `.widget` samples are local Documents data only, mirroring the removed bundled
  samples. No bundled resources changed.

### Simulator launch regression (iCloud entitlements)

- The app would not launch on the simulator: `simctl spawn` failed with
  `Compatibility: Security policy issue` / `NSPOSIXErrorDomain code 163`.
- Root cause: the provisioning-time iCloud/CloudKit entitlements
  (`com.apple.developer.icloud-container-environment`, `icloud-services`,
  `ubiquity-container-identifiers`) are signed into the simulator build and
  `launchd` refuses to spawn an app carrying cloud-container entitlements without a
  real provisioning profile. Other simulator apps launch fine.
- A re-signed copy with only `com.apple.security.application-groups` launches
  correctly. This is a regression vs. previous simulator runs (which predated the
  cloud entitlements commit). Not fixed in the source yet — only worked around for
  the screenshots via `/tmp/simapp`. Flagged in the handover/SR risk.
- Security note: launching on simulator for screenshots therefore requires the
  entitlement-stripped build; do not ship that stripped entitlement set to devices.

### ChatGPT credential for the simulator flow

- The signed Catalyst app on this Mac (TestFlight) stores its own Keychain item scoped
  to the app access group, so the macOS `security` CLI / an unsigned helper cannot
  read it (`-25300`/`-34018`).
- Per user choice, seeded the simulator app's `OpenAICredential` (JSON under
  `net.stupidtech.stupidwidgets.openai` in UserDefaults) from OpenCode's
  `~/.codex/auth.json` (auth_mode `chatgpt`, same OAuth flow the app uses). Verified:
  the detail view shows the signed-in "Describe changes" assistant instead of
  "Edit with ChatGPT". No secrets were printed or committed.

- On an iOS device the `ScriptStore` reads the iCloud ubiquity container
  (`Documents/Scripts`). A single not-yet-downloaded/coalescing `.widget` file made
  `reload()` abort, leaving the in-app widget list frozen, and plain `Data(contentsOf:)`
  reads could fail on ubiquity items. Reported as "renaming is broken and widget list
  doesn't update" on the iPhone.
- `Script.fromFile` now reads through `NSFileCoordinator` and starts a download for iCloud
  placeholders that are not yet current before decoding.
- `ScriptStore.reload()` now decodes each `.widget` file independently and drops files that
  fail to read instead of aborting the whole reload (so one transient cloud item can't
  blank/ freeze the list). Directory-enumeration errors still surface via `errorMessage`.
- Rename/create/delete/import already mutate the in-memory list directly, which now can no
  longer be clobbered by a stale read; verified in-app on the simulator.
- Added `ScriptStoreTests.testRenameUpdatesListAndPersists` (rename updates the list, the
  file is actually renamed on disk, and the new name survives a reload). All 32 simulator
  tests pass. Could not re-verify on the physical iPhone because it wasn't reachable via
  usbmuxd during this session.

## 2026-08-20 — Fix duplicate widget list rows

- A widget's persistent `id` was derived from its *name* (`Script.stableID(for: name)`), and
  `rename` keeps that id. So renaming "Untitled" → "Untitled 2" (id stays
  `stableID("Untitled.widget")`), then creating a new "Untitled", produced a second file with
  the same id. Since `ScriptListView.ForEach` keys rows by `script.id`, two rows shared one
  identity and rendered as duplicate line items.
- `ScriptStore.create` now assigns a genuinely random `UUID()` (persisted in the manifest)
  instead of a name-derived id, so new widgets can never collide after a rename. The
  `stableID(from:)` fallback remains only for reading legacy files that lack an `id` field.
- `ScriptStore.reload()` now deduplicates on load: if two files resolve to the same id, the
  later one is given a fresh `UUID()` (persisted), repairing already-written duplicates on
  the device.
- Added `ScriptStoreTests.testRenameThenRecreateSameNameDoesNotDuplicateIDs` and
  `testReloadDeduplicatesCollidingIDs`. All ScriptStore/logical tests pass; the duplicate fix
  was deployed to the iPhone for manual confirmation.

---

## 2026-08-20 — Widget UX, `.widget` domain, device/iCloud provisioning

- Switched scripts from the `.scriptable` file extension to **`.widget`** across `ScriptStore`
  (filter/seed/paths), the WidgetKit extension's `availableScripts`, module resolution
  (`RuntimeRegistration`), the `Info.plist` document type, and the bundled/config resource lists.
  The `.scriptable` name and `scriptable-api.json` docs bundle are unchanged.
- Gave scripts a **persistent identity**: the `.widget` manifest now carries an `id`; `ScriptStore`
  reads it (falling back to a filename-derived UUID for legacy files). This stops the `Widget Not
  Found` failure after rename/edit because navigation ids no longer churn on `reload()`.
- Removed the two built-in sample widgets (the widgets list now starts empty with a **"No Widgets"**
  empty state) and deleted the redundant `xtool.yml`.
- "New widget" now creates `Untitled Widget` (auto-uniqued) and **opens its detail directly** instead
  of the naming dialog; the naming alert is rename-only.
- New widgets begin from the recovered **hello-world boilerplate** (gradient + date/time + title).
- The Small/Medium/Large **preview preference is now persisted per widget** (`preview_family`).
- When ChatGPT is disconnected the bottom bar shows a bordered **"Edit with ChatGPT"** pill (same
  54pt height + border as the reload circle and input), keeping the reload button. While busy, the
  **current agent tool call** displays in muted text above the input (new `.toolCalled` event).
- Device/iCloud provisioning: enabled **iCloud + CloudKit**, registered the
  **`iCloud.net.stupidtech.stupidwidgets`** container on the App ID, and slimmed the entitlements to
  `icloud-services`, `ubiquity-container-identifiers`, and `application-groups` (dropped the `$()`-based
  keychain/kvstore/env keys the CLI can't expand). iCloud script sync points `ScriptStore` at the
  ubiquity container with `NSMetadataQuery` change observation; ChatGPT credentials sync via iCloud
  Keychain (`kSecAttrSynchronizable`).
- Added a passwordless CoreDevice `sudoers` rule for the installed CLI; relies on a real dev profile
  for `00008130-001C4CA030A1401C` that authorizes the iCloud container.
- Steps 1–4 of the cross-platform plan landed earlier: `WidgetRender` target, preview/extension
  unified on `ScriptWidgetSnapshotView`, `WidgetRenderer.swift` removed, and a **Catalyst Mac app** in
  `mac-app/` (xcodegen `project.yml`) importing `StupidWidgetsCore`. `StupidWidgetsCore` is now an
  importable library product.

---

## 2026-08-20 — Cross-platform rendering + iCloud + Catalyst Mac app (end to end)

Implements `docs/cross-platform-rendering-handover.md` through to the Mac and iCloud pieces.

### Shared rendering target (completed earlier this session)
- Added the macOS-clean `WidgetRender` SwiftPM target (snapshot value types + `ScriptWidgetSnapshotView` +
  a cross-platform `Image(widgetImageData:)`). Its only platform seam uses `#if canImport(UIKit)` first,
  then `#elseif canImport(AppKit)` — the order matters so Mac Catalyst takes the `uiImage` branch
  (under Catalyst both frameworks are importable but `Image(nsImage:)` is invalid).
- Deleted `WidgetRenderer.swift`; the in-app preview and WidgetKit extension both render the shared
  `ScriptWidgetSnapshotView`. `StupidWidgetsCore` is now an exported library product
  (`Package.swift`) so an external Xcode project can depend on it.

### iCloud script sync (source of truth)
- Pointed `ScriptStore` at the app's ubiquity container (`Documents/Scripts`) first, falling back to
  stores when iCloud is unavailable; the app-group mirror (for the widget extension) is unchanged.
- Added `NSMetadataQuery` (ubiquitous Documents scope, `kMDItemFSName ENDSWITH .scriptable`) so external
  edits on another device trigger `ScriptStore.reload()` → the widget timelines refresh.
- Added CloudKit/Documents iCloud entitlement (`com.apple.developer.ubiquity-container-identifiers` =
  `iCloud.net.stupidtech.stupidwidgets`) plus a keychain-access-groups entitlement to the iOS app's
  `StupidWidgets.entitlements` and the Mac app's entitlements.

### ChatGPT credentials across apps
- `AIClient` now saves the OpenAI credential to the device Keychain with
  `kSecAttrSynchronizable = true` and `kSecAttrAccessibleAfterFirstUnlock` (was
  `...ThisDeviceOnly`). Because the iOS app and the Catalyst Mac app share the same bundle
  identifier and team access group, the iCloud Keychain syncs the ChatGPT credential across
  devices and the Mac app. Simulator builds keep the existing UserDefaults fallback.

### Catalyst Mac app
- Added `mac-app/` (committed `project.yml`, `Sources/StupidWidgetsMac/StupidWidgetsMacApp.swift`,
  `StupidWidgetsMac.entitlements`). Regenerate the checked-in `StupidWidgetsMac.xcodeproj` with
  `xcodegen generate` from `mac-app/`.
- It is a Mac Catalyst app (same bundle id `net.stupidtech.stupidwidgets`) importing the local
  `StupidWidgets` package's `StupidWidgetsCore` product — it shares the JS bridge, models, store,
  iCloud sync, and the `WidgetRender` engine.
- `xcodegen` was installed via Homebrew.
- Verified: `xcodebuild build -project StupidWidgetsMac.xcodeproj -scheme StupidWidgetsMac
  -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO` **Build Succeeded**;
  the same `WidgetRender` sources build standalone for native macOS and for the iOS simulator.

### Known limits / needs-device-verification
- iCloud and Keychain sharing require a real signed/provisioned build (and a team) — not exercised on
  the simulator or in the sandbox. `$(TeamIdentifierPrefix)`/`$(AppIdentifierPrefix)` expand under
  Xcode; the CLI build path should be confirmed.
- WidgetKit Home Screen widgets are not re-hosted on the Mac; the Catalyst app shares everything else
  but does not embed the `.appex` (Mac Catalyst widget-extension embedding is limited).
- `kSecAttrSynchronizable` can surface `errSecMissingEntitlement` until provisioning is set up; this
  surfaces as a keychain-storage error rather than being silently swallowed.

---

## 2026-08-20 — Shared WidgetRender target (cross-platform rendering)

- Added a new macOS-clean SwiftPM target `WidgetRender` (`Sources/WidgetRender/`) that contains
  the pure `ScriptWidget*` value types and `ScriptWidgetSnapshotView`, plus a cross-platform
  `Image(widgetImageData:)` helper (the only platform seam, using a `#if canImport(AppKit)` branch).
  It depends only on SwiftUI (`Platforms: [.iOS(.v17), .macOS(.v14)]`), with no
  `UIKit`/`AppKit`/`JavaScriptCore`.
- Moved the snapshot value types and the shared view out of
  `Sources/StupidWidgets/WidgetExtensionSupport.swift` (core) into `WidgetRender`. `WidgetRender` is
  now a dependency of `StupidWidgetsCore`, `StupidWidgetsWidgetExtension`, and the tests; the app and
  extension can both render the exact same snapshot view.
- Deleted `Sources/StupidWidgets/WidgetRenderer.swift`. The in-app live preview (`WidgetPreviewCanvas`
  in `Views.swift`) now snapshots the running `ListWidgetModel` via `ScriptWidgetRunner.snapshot(widget:)`
  and renders the shared `ScriptWidgetSnapshotView`, matching the WidgetKit extension path. Any
  previously-internal `WidgetRenderer` member is gone; its per-family corner-radius clip is preserved in
  the preview canvas.
- `WidgetExtensionSupport.swift` retains the UIKit-coupled runners/conversions only: the app-group
  `StupidWidgetsWidgetStorage`, `SharedWidgetScript`, `ScriptWidgetRunner` (JS→snapshot), and a new core
  `ScriptWidgetFont` `UIFont`-based initializer extension (the `ScriptWidget*` types are now in
  `WidgetRender`). To preserve preview/extensions fidelity that the old renderer had, the snapshot now
  also carries a background-image case (`ScriptWidgetBackground.image(Data)`), a date-relative/offset/timer
  label path, and an image fit-vs-fill flag (`fills`).
- Verified: `swift build --target WidgetRender` compiles cleanly for macOS; the iOS simulator package and
  test target build; all 31 simulator tests pass through the `StupidWidgets-Package` scheme.

---

## 2026-08-20 — Raise agent tool-loop limit

- `AgentAIClient.chat` loop raised from 8 to 100 provider turns
  (`for _ in 0..<100`), updated the exceeded-limit error string.
- Why: a real weather-widget request ("show the weather in cape town") was
  stopped after 8 turns — multi-`search_api` + repeated `edit_script` +
  runtime-validation retries exceed a fixed 8-turn ceiling. 100 is a generous
  cap with no convergence guard; if it still truncates, add a no-progress
  guard instead of a higher number.

## 2026-08-15 — Inspection & API spec extraction

### What was done
- Downloaded and extracted Scriptable 1.7.19 (`dk.simonbs.Scriptable`) via ipatool.
- Extracted the app bundle to `third-party/scriptable/` (gitignored).
- Wrote `tools/generate-api-spec.mjs` and generated `docs/scriptable-api.json`:
  - 55 types, 4 globals (`args`, `config`, `console`, `module`), 1 function (`importModule`),
    791 doc pages, 706 documented members.
  - Every type annotated with its runtime member list recovered from
    `ScriptableKit.framework/prototype-extensions.js` (the JS bridge reflection contract).
- Wrote `docs/scriptable-architecture.md`: bundle inventory, runtime architecture (ScriptableKit +
  JavaScriptCore, bridge pattern), `.scriptable` file format, 6 app extensions, Siri/Shortcuts
  intents, integrations (URL scheme, GCDWebServer "Add to Home Screen" PWA trick, iCloud),
  editor stack (Runestone + Tern + tree-sitter), gap analysis, and the AI editor design.

### Decisions locked (user)
- iOS app first (SwiftUI + JavaScriptCore).
- API-compatible: existing Scriptable scripts should run on our platform.
- AI editor: Cloudflare Worker backend (Hono + openai), backend-managed OpenAI key,
  chat generate + iterate UX grounded on `docs/scriptable-api.json`.

### Notes / caveats
- Main executables are FairPlay-encrypted; Swift implementation is not readable. The readable
  resources fully cover the API contract and architecture.
- Spec source of truth: bundled `docs/*.json`; cross-checked with `prototype-extensions.js`.
- No entitlements file shipped in the .ipa (provisioning profile not included in download).

### Next steps
- Scaffold iOS app  + API-compatible JavaScriptCore bridge, testable against
  `docs/scriptable-api.json`.
- Cloudflare Worker AI backend (`POST /chat` streaming, system prompt distilled from the spec).
- Editor AI panel + wiring.

---

## 2026-08-15 — AI backend + iOS app built (handoff)

**Status: WORK IN PROGRESS. The AI backend is complete and tested. The iOS app is ~90% written
but the last full build was never verified green.** Read this whole section before continuing.

### Repository layout
```
./
├── AGENTS.md                        # workflow rules (read docs before changes)
├── docs/
│   ├── scriptable-architecture.md   # inventory + design
│   ├── scriptable-api.json          # canonical API spec (compat contract)
│   └── implementation-notes.md      # this file
├── tools/generate-api-spec.mjs      # regenerates scriptable-api.json (bun run)
├── third-party/scriptable/          # gitignored: extracted Scriptable.app bundle
├── ai-backend/                      # Cloudflare Worker — COMPLETE
└── stupid-widgets/                  # iOS app (SwiftPM) — IN PROGRESS
```

### AI backend — COMPLETE (Cloudflare Worker)
- Stack: Hono + `openai` npm client pointed at **OpenRouter**
  (`baseURL https://openrouter.ai/api/v1`), streaming SSE, zod validation.
- Default model `deepseek/deepseek-v4-flash` (`wrangler.jsonc` `vars.AI_MODEL`).
- Files: `src/index.ts` (routes), `src/system-prompt.ts` (prompt builder),
  `src/api-reference.ts` (**generated** by `bun run distill` from `docs/scriptable-api.json` —
  do not hand-edit).
- Endpoints:
  - `GET /health` → `{ ok: true }`
  - `POST /chat` body `{ messages: [{role, content}], script?, model? }`,
    auth `Authorization: Bearer <AI_BACKEND_TOKEN>`. SSE events:
    `data: {"type":"delta","text":...}`, `{"type":"done"}`, `{"type":"error",...}`.
- Secrets (dev: `.dev.vars` / `.dev.vars.local`; prod: `wrangler secret put`):
  `OPENROUTER_API_KEY` (backend-managed, not on device), `AI_BACKEND_TOKEN`.
- Verified locally: 401 without token, 400 bad body, 502 upstream with a fake key.
  **Not tested with a real key** — set a real `OPENROUTER_API_KEY` to see streaming.
- Commands (from `ai-backend/`): `bun install` done; `bun run dev` (wrangler on :8787),
  `bun run deploy`, `bun run distill`, `bun run typecheck`.
- Gotchas discovered:
  - Do **not** `export` named values (e.g. `DEFAULT_MODEL`) from `index.ts` — the
    Workers runtime treats every named export as a handler → startup crash. Keep it `const`.
  - Backticks inside TS template literals that render Markdown code fences must be escaped.

### iOS app — IN PROGRESS (`stupid-widgets/`)
- SwiftPM app, bundle ID `net.stupidtech.stupidwidgets`, `infoPath: Info.plist`
  (contains `NSAppTransportSecurity` allow-arbitrary for dev HTTP), `resources: Resources`
  (2 bundled `.scriptable` samples).
- Targets iOS simulator `NoFeedSocial iOS 26.3` (UDID `6552DF1D-95CE-48E3-801F-8F80F0AA8D29`).

#### Architecture (all files in `Sources/StupidWidgets/`)
- `JSBridge.swift` — the JS↔Swift bridge core. `@MainActor protocol JSObject` (conforming
  classes inherit MainActor isolation); `JSRuntime` owns `JSContext`, a native object store
  keyed by int id, static handler registries, and injects a JS bootstrap that generates a
  wrapper class per `JSClassSpec` (constructor `new X()`, `Object.defineProperty` accessors
  for props, prototype methods, promise wrappers for async methods). Gateway
  `@convention(block)` closures (`__stupidWidgets_*`) dispatch to Swift and are wrapped in
  `MainActor.assumeIsolated`; non-Sendable returns go through `AnyBox`.
  **Marker protocol:** Swift returns native objects to JS as the string `"__bs_obj:<id>"`
  which JS resolves via `__bs._object(id)` into a prototype-wired wrapper.
- `RuntimeRegistration.swift` — `installScriptableAPI(scriptName:)` registers all classes and
  globals. **Constructor args** (e.g. `new Color("#fff")`) work via factory
  `(JSRuntime, [Any]) -> JSObject`.
- `WidgetModels.swift` — value models (Color/Font/Size/Point/Rect/Image/Data) + widget element
  tree (ListWidget/WidgetStack/WidgetText/WidgetDate/WidgetImage/WidgetSpacer/LinearGradient).
  `add*` methods append to `children`; `present*` calls `runtime.presentPreview`.
- `SystemBridges.swift` — Device (static), SFSymbol, FileManager (local FS), Timer, DateFormatter,
  RelativeDateTimeFormatter, Path (no-op), plus `StaticOnlyObject` for pure-static classes.
- `NetworkBridges.swift` — Request (URLSession async via `jsAsync`, multipart), RequestResponse,
  Notification (+ static center methods), NotificationAction.
- `UIBridges.swift` — Alert (async present → sheet), UITable/UITableRow/UITableCell (async
  present → sheet), QuickLook (async static), Safari, plus `AlertRequest`/`PreviewRequest`.
- `WidgetRenderer.swift` — SwiftUI rendering of the widget tree.
- `Models.swift` — `Script` model + `ScriptStore` (loads bundled `.scriptable` JSON).
- `Views.swift` — `@main StupidWidgetsApp`, `ScriptListView`, `EditorView` (TextEditor + Run +
  console + AI/settings sheets), AlertSheet/WidgetPreviewSheet/TableSheet, `AIPanel` chat,
  `SettingsSheet` (AI base URL + token).
- `AIClient.swift` + `ChatViewModel.swift` — SSE client + chat state; auto-extracts the first
  ```` ```js ```` code block from a response and inserts it into the editor.

#### Implemented API surface (subset, ~30 of 55 types)
ListWidget, WidgetStack/Text/Date/Image/Spacer, LinearGradient, Color, Font, Size, Point, Rect,
Image, Data, Device, SFSymbol, Keychain (UserDefaults-backed), Pasteboard, UUID, FileManager,
Timer, DateFormatter, RelativeDateTimeFormatter, Path, Request(+Response), Notification(+Action),
Alert, UITable/Row/Cell, QuickLook, Safari. Globals: `config`, `args`, `module`, `console`,
`Script` (name/setWidget/complete/setShortcutOutput), `importModule`.
Not implemented: Calendar/Contacts/Location/Photos/Mail/Message/Dictation/Speech/WebView/
DrawContext/DocumentPicker/ShareSheet/CallbackURL/URLScheme/XMLParser.

### Build status & how to build
- **Known-good state:** code has been iterated until it compiles except one error which was just
  fixed — `RelativeDateTimeFormatterModel.jsCall` missing return in `SystemBridges.swift`.
  **The final full build has NOT been run/verified.** Run this from `stupid-widgets/`:
  ```
  stupid-app run --simulator --udid 6552DF1D-95CE-48E3-801F-8F80F0AA8D29
  ```
- **CRITICAL build hygiene (learned the hard way):** SwiftPM locks `.build/`. If a build is
  aborted mid-run, its child `swift-build` process keeps the lock and every later build blocks
  on `waiting until that process has finished execution`. Always
  `pkill -9 -f swift-build` before retrying. **Run builds in the foreground**
  (no `nohup ... &`) so an abort kills the build instead of orphaning it.
- First full build is slow (few minutes, ~15 Swift files). Subsequent incremental builds are fast.
- Remaining warnings (non-blocking): some `Any?` implicit-coercion warnings; deprecated
  `onChange(of:perform:)` was already updated to the two-arg form.

### Known issues / next steps (for the new person)
1. **Verify a green build + launch** on the simulator. Fix any remaining compile errors.
2. **Runtime smoke test:** run "Hello Widget" — expect a widget preview sheet. Debug the
   JS↔Swift bridge (use `console.log` lines in the EditorView console area).
3. **Live AI test:** put a real `OPENROUTER_API_KEY` in `ai-backend/.dev.vars`, run the worker,
   and from the app's "Server" sheet set base URL `http://127.0.0.1:8787` and the
   `AI_BACKEND_TOKEN`; then "AI" → describe a widget → auto-insert.
4. Implement the remaining ~25 API types (see above) against `docs/scriptable-api.json`;
   every type's member list is in `runtimeMembers` for test assertions.
5. Later: widget app extension (WidgetKit), Siri/Shortcuts intents, macOS port, real Keychain
   (not UserDefaults), iCloud script sync, `DrawContext`/`WebView`.

---

## 2026-08-15 — Simulator build and launch verified

- Fixed a Swift compiler stall in `WidgetRenderer`: recursive widget stacks created a recursive
  opaque `some View` type between `child` and `stackView`. The recursive `child` boundary now uses
  `AnyView` type erasure.
- Changed `stupid-app.yml` to package the two sample scripts individually at the app bundle root. A
  top-level directory named `Resources` made Foundation interpret the generated app as a legacy
  bundle, hide its root `Info.plist`, and caused simulator installation to fail with
  `Missing bundle ID`. Root packaging also matches `ScriptStore`'s resource lookup.
- Verified stupid-app run --simulator -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach
  --no-logs --launch-timeout 300` builds and installs successfully.
- Verified launch on `NoFeedSocial iOS 26.3`; the initial script list exposes `Hello Widget` and
  `Read MacStories`.

---

## 2026-08-15 — AI flow verified end to end

- Ran the local Cloudflare Worker with the ignored `.env.local` `OPENROUTER_API_KEY` and verified
  authenticated `/chat` SSE streaming against OpenRouter.
- Fixed multiline fenced-code extraction in `ChatViewModel`. The previous regular expression did
  not match across newlines and would also have retained the `js` language marker. The app now
  inserts only the fenced code body.
- Fixed console bridge argument marshalling in `RuntimeRegistration`. JavaScript console methods
  now collect variadic arguments into an array before invoking the native logger, so calls such as
  `console.log("text")` no longer fail while converting a primitive to `NSArray`.
- Rebuilt and installed through the build tool, requested a script through the simulator AI panel, verified
  auto-insertion of `console.log("APP_E2E_OK");`, ran it, and observed `APP_E2E_OK` in the in-app
  console.

---

## 2026-08-15 — Engineering handover consolidated

- Added `docs/engineering-handover.md` as the current takeover guide for another engineer.
- Consolidated verified build and AI E2E state, repository and runtime architecture, exact file
  references, API coverage, local credential handling,  recovery steps, manual verification
  flows, known defects, stale historical-note corrections, and a prioritized implementation plan.
- Cross-checked the guide against the current code, including effective versus declared API
  coverage, source-control status, scoped build-process cleanup, table crash/object-allocation risks,
  notification limitations, and a reproducible local Wrangler secret-generation procedure.
- Added the handover to the mandatory read-first documents in `AGENTS.md`.

---

## 2026-08-15 — Persistent app, deterministic runtime, and client-side ChatGPT

- Removed the Cloudflare/OpenRouter backend source and replaced the server settings flow with
  OpenCode-compatible ChatGPT device OAuth.
- Added signed-device Keychain persistence, early token refresh/rotation, account-ID extraction,
  direct Codex Responses requests, SSE streaming, cancellation, sign-out, and device-flow
  cancellation UI.
- Replaced bundle-only script loading with strict Documents-backed `.scriptable` encoding, startup
  seeding of missing samples, atomic autosave, create, rename, delete, import, export, validation, and surfaced
  storage errors.
- Declared `.scriptable` as an imported JSON document type.
- Added a fresh runtime per Run, defensive bootstrap terminators, Promise native-object unwrapping,
  reflection helpers, top-level `await`, completion-aware preview presentation, and Promise rejection
  reporting.
- Fixed `Request(url)`, response/cell/action allocation, JSON rejection, Font arguments, widget
  image/spacer/padding behavior, horizontal stack defaults, safe table removal, Script.name(),
  FileManager method shapes/basic semantics, Timer milliseconds, formatter ordering/reference dates,
  and moved the Scriptable Keychain API to Keychain Services on signed devices.
- Added simulator-targeted runtime and persistence regression tests. Test sources compile; final
  standalone linking remains blocked by the library target's embedded SwiftUI `@main`, while the
  generated scheme has no test action.
- Verified a green build/install, persistent edits across relaunch, Hello Widget preview,
  completed ChatGPT device authorization, direct Codex SSE generation, automatic editor insertion,
  persistence across relaunch, and execution of generated `CHATGPT_CLIENT_OK` code on the preferred
  simulator.
- Completed OAuth initially failed to persist with `errSecMissingEntitlement` (`-34018`). 
pseudo-signing rejects explicit Keychain access-group entitlements on simulator launch, so
  simulator builds use isolated development-only UserDefaults records for OAuth and the Scriptable
  `Keychain` API. Signed device builds continue to use Keychain Services.
- The build/install/launch command completed successfully: stupid-app run --simulator -u
  6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach --no-logs --launch-timeout 300`.
- The simulator test-target compilation command completed successfully: `swift build --target
  StupidWidgetsTests --triple arm64-apple-ios-simulator --sdk "$(xcrun --sdk iphonesimulator
  --show-sdk-path)"`.
- E2E verification changed only simulator Documents data: `Hello Widget` now contains the generated
  `console.log("CHATGPT_CLIENT_OK")`, and `Read MacStories` has one additional newline. Checked-in
  bundled resources remain unchanged; deleting either script in-app and relaunching restores its
  bundled copy.

---

## 2026-08-15 — Simulator tests made executable

- Split the package into a reusable `StupidWidgetsCore` target and a minimal
  `StupidWidgetsApp` target containing only SwiftUI `@main`. The single  library product
  still packages the app target and its core dependency.
- Added `StupidWidgetsRootView` as the core-to-app boundary and changed the test target to import
  `StupidWidgetsCore`, removing the duplicate `_main` test-link failure.
- Updated the reflection regression to avoid relying on `Array.prototype.includes` when validating
  the ES6-compatible JavaScriptCore surface.
- Executed all four tests successfully on `NoFeedSocial iOS 26.3` with `xcodebuild test -scheme
  StupidWidgets -destination "platform=iOS Simulator,id=6552DF1D-95CE-48E3-801F-8F80F0AA8D29"`.
- Verified stupid-app run --simulator -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach
  --no-logs --launch-timeout 300` still builds and installs, then explicitly launched
  `net.stupidtech.stupidwidgets` with `simctl`.

---

## 2026-08-15 — Generated API structural conformance coverage

- Extended `tools/generate-api-spec.mjs` to generate
  `stupid-widgets/Tests/StupidWidgetsTests/GeneratedAPIContract.swift` alongside
  `docs/scriptable-api.json`. The Swift fixture normalizes canonical instance properties and
  instance/static synchronous/Promise methods for all 55 types.
- Added a read-only `JSClassShape` snapshot so tests compare installed registration metadata without
  invoking APIs that present UI, request permissions, or mutate storage.
- Added structural tests that strictly compare 16 complete registered types to the generated
  contract, lock the 16 partial and 22 absent type inventories, allow only the two known internal
  helper types, and verify the special `Script` global's four canonical functions.
- Regenerated the API artifacts, formatted and linted the JavaScript generator with oxfmt/oxlint, and
  formatted the manually changed Swift sources with `swift format`.
- Executed eight tests successfully on `NoFeedSocial iOS 26.3`, then verified the  app build and
  installation and explicitly launched `net.stupidtech.stupidwidgets` as simulator PID `40215`.

---

## 2026-08-15 — Scriptable module loading completed

- Replaced the shared-global `importModule` wrapper with per-file `module` objects containing local
  `exports`, metadata, and dependencies. Imports now return `module.exports` and cache it by resolved
  standardized path.
- Added early cache insertion for circular imports, final export replacement support, dependency
  path tracking, failed-evaluation eviction, and explicit missing/decode/evaluation errors.
- Added optional-extension resolution for `.js` and `.scriptable`, importer-relative lookup,
  configured search roots, leading-slash search-root paths, and directory
  `index.js`/`index.scriptable` lookup.
- Added three simulator regressions covering exports, relative and directory resolution, caching,
  dependency records, circular imports, strict `.scriptable` loading, missing-module errors, thrown
  module errors, and successful retry after a failed evaluation.
- Executed all eleven tests successfully on `NoFeedSocial iOS 26.3`, verified a green build and
  installation, and explicitly launched `net.stupidtech.stupidwidgets` as simulator PID `43455`.

---

## 2026-08-15 — Agentic AI editing and weather-widget E2E

- Reproduced a completed Codex response that left the AI sheet busy because the SSE client marked
  `response.completed` but continued waiting for the HTTP stream to close. Terminal events now end
  the provider turn immediately.
- Replaced whole-script prompting and full-file responses with an OpenCode-style Responses tool loop
  in `AgentAIClient.swift`. The model can read up to 200 numbered lines with `read_script` and apply a
  minimal exact replacement with `edit_script`; ambiguous or stale edits return recoverable tool
  errors.
- Added explicit `function_call`/`function_call_output` continuation, streamed argument assembly by
  item ID, authoritative final arguments, encrypted reasoning replay for `store: false`, an eight-turn
  limit, cancellation, and immediate editor/autosave updates after successful edit tools.
- Added three unit regressions for bounded reads, exact edits, and ambiguous-edit rejection. All
  fourteen simulator tests pass.
- Used the authenticated app to generate and run a 97-non-empty-line Cape Town weather widget using
  Open-Meteo. The preview showed 18°C, partly cloudy, feels-like 18°C, and 5 km/h wind.
- Verified a follow-up agent request changed only two title strings from `Cape Town Weather` to
  `Cape Town Live`, completed in under ten seconds, persisted, and rendered correctly on rerun.
- Verified the installed app bundle has no `PlugIns` directory. stupid widgets can preview the
  generated widget but cannot add it to the iOS Home Screen until a generic WidgetKit runner extension
  exists.

---

## 2026-08-15 — Generic configurable WidgetKit runner

- Added `StupidWidgetsWidgetExtension` as a second SwiftPM product with shared app-group
  entitlements on the app and extension.
- Added non-destructive mirroring of the complete Documents script library into the app group. Script
  creates, edits, imports, renames, and deletes update the mirrored files; successful widget runs and
  startup synchronization reload WidgetKit timelines.
- Added a public runner boundary that executes the selected JavaScript in a fresh `JSRuntime`, waits
  for asynchronous completion, snapshots widget text/images/stacks/spacers into Sendable values, and
  renders the snapshot inside the extension.
- Added an App Intent widget configuration with a dynamic script entity query. Every Home Screen
  instance stores its own script selection, enabling multiple widgets backed by different scripts.
- Discovered that  does not invoke `appintentsmetadataprocessor`. Generated the metadata with an
  Xcode build and explicitly packaged `WidgetMetadata/Metadata.appintents`; `chronod` then resolved
  `SelectScriptIntent` and exposed the configurable widget in the gallery.
- Added a medium stupid widgets widget to the preferred simulator Home Screen. It rendered the
  AI-generated Cape Town weather script with live Open-Meteo data. `Edit Widget` displayed both
  `Hello Widget` and `Read MacStories` in the per-instance Script picker.
- Fixed a startup mirroring race that briefly removed the shared Scripts directory during timeline
  requests. Mirroring now removes only stale files, writes atomically, and reloads timelines after the
  library is complete.
- Verified a final build/install, app relaunch, persistent widget selection, live Home Screen
  refresh at 17°C, and all fourteen simulator tests using the `StupidWidgets-Package` scheme.

---

## 2026-08-15 — Renamed to stupid widgets

- Renamed the Swift package, products, targets, source directories, tests, app entry point, root view,
  widget bundle, widget type, storage helper, and JavaScript bridge globals to `StupidWidgets` names.
  User-facing app and widget names use the lowercase `stupid widgets` brand.
- Changed the app bundle identifier to `net.stupidtech.stupidwidgets`, the widget extension to
  `net.stupidtech.stupidwidgets.widget`, the shared app group to
  `group.net.stupidtech.stupidwidgets`, and related UTI, Keychain service, notification, multipart,
  HTTP originator, and user-agent identifiers to the same namespace.
- This is a breaking rename. It intentionally does not migrate scripts, widget selections, or
  credentials from the previous app-group, bundle, and Keychain namespaces.
- Updated the sample widget, API generator output path, App Intent metadata, architecture notes, and
  engineering handover. Regenerated the 55-type API contract and confirmed Xcode-generated App Intent
  metadata is semantically identical to the checked-in metadata.
- Formatted all Swift and JavaScript sources, passed oxlint with no findings, validated all property
  lists, passed all fourteen simulator tests, completed a green app/widget build and install,
  confirmed the installed `CFBundleDisplayName` is `stupid widgets`, and launched
  `net.stupidtech.stupidwidgets` on the preferred simulator as PID `3138`.

---

## 2026-08-15 — Edge-to-edge widget rendering

- Disabled WidgetKit's default content margins so script widget backgrounds extend to every edge of
  the widget pane.
- Made the snapshot root explicitly fill all available width and height while preserving the
  renderer's internal 14-point content padding.

---

## 2026-08-15 — Removed obsolete AI backend leftovers

- Confirmed the app has no references to or runtime dependency on the former Cloudflare/OpenRouter
  Worker; ChatGPT authorization and Codex Responses streaming run directly on-device.
- Removed the residual `ai-backend/` directory, which contained only ignored local secrets,
  installed dependencies, empty source directories, and Wrangler build output.

---

## 2026-08-15 — App icon

- Added complete iPhone, iPad, and App Store icon sets generated from the supplied square artwork.
- Configured the asset catalog, concrete bundled icon resources, and primary icon metadata required
  by  and App Store validation.

---

## 2026-08-15 — Preview-first script details

- Removed the script-list import toolbar button and simplified script rows to compact icons with
  regular-sized names and no source line counts.
- Changed script details to execute and render widget output inline by default. Source remains
  available through an explicit Edit/Preview toggle, and Run and AI remain in the bottom toolbar.
- Removed the detail-view Account button and its separate account sheet. The assistant's signed-out
  state now starts ChatGPT device authorization directly and shows authorization progress, the copied
  user code, cancellation, and errors in place; the existing disconnect action moved into the signed-in
  assistant toolbar.

---

## 2026-08-15 — In-app ChatGPT browser OAuth

- Replaced OpenCode's headless device-code flow, external browser launch, copied user code, and token
  polling with its ChatGPT Pro/Plus browser authorization-code flow in an
  `ASWebAuthenticationSession`.
- Added a fresh cryptographic PKCE verifier/challenge and OAuth state per attempt, exact validation of
  the registered `http://localhost:1455/auth/callback` URL and returned state, automatic callback
  capture, and authorization-code exchange. Existing credential persistence, refresh, account-ID
  extraction, and disconnect behavior remain unchanged.
- The loopback callback is served by a short-lived local TCP listener on port 1455, matching
  OpenCode's browser implementation. An initial attempt to register plain `http` itself as the
  authentication-session callback scheme compiled and opened the correct OpenAI page but caused an
  infinite redirect after sign-in; the local listener fixes that failure mode.
- Simplified the assistant's signed-out state to one Connect ChatGPT action; authentication and
  cancellation now happen entirely in the system authentication sheet without a displayed code.
- Verified on the preferred simulator that the authentication sheet opens the OpenAI sign-in flow,
  completes through the loopback listener, closes automatically, and signs the assistant in without
  a redirect loop.

---

## 2026-08-15 — Inline change prompt and undo

- Removed the detail toolbar's Run and AI buttons and deleted the assistant sheet, message bubbles,
  auto-insert toggle, and sheet-only account controls.
- Added a bottom safe-area row matching stupid authenticator's search treatment. Standalone circular
  Undo and Reload buttons flank a material-capsule multiline Describe changes field with its own Play
  submit action. Play initiates ChatGPT authorization when necessary or submits the request when signed
  in; while active it becomes a Stop action. Reload always rerenders the current source.
- During a request, the prompt remains visible while text editing and Undo are disabled. It clears only
  after the request finishes.
- Prompt text is measured at the compact field's available body-text width. Content exceeding two
  compact lines expands into a taller full-width rounded rectangle, hides Undo and Reload, and pins
  Play/Stop to the top right. Deleting back to two compact lines restores the standard row.
- The compact capsule remains one visible, horizontally scrolling line; the two-line threshold is
  based on how the complete prompt would wrap at that compact width.
- Expansion now preserves one persistent `TextField` and changes only its layout and surrounding
  controls, preventing keyboard focus from being lost at either transition.
- AI edits continue through the existing bounded tool loop and autosave path. The detail reruns the
  widget when a request finishes, while Undo restores the source snapshot captured before the latest
  AI edit and reruns the restored widget.
- Assistant and authentication failures now surface as alerts on the detail view because there is no
  longer a transcript screen.

---

## 2026-08-15 — Native widget property assignment fix

- Diagnosed an inline request to make widget text blue that correctly edited and persisted
  `Color.blue()` assignments but still rendered fallback white text.
- Fixed the JavaScript bootstrap to convert native bridge objects to object-ID markers recursively
  when they are passed as constructor/method arguments or assigned to instance/static properties.
  Previously returned objects were unwrapped correctly, but sending them back into Swift lost their
  native identity. This affected text colors and other object-valued properties such as gradients and
  images.
- Added a runtime regression that evaluates `text.textColor = Color.blue()` and verifies the resulting
  widget model retains the named color. The suite now contains fifteen tests.
- Made prompt text explicitly gray while the request field is disabled.
- Hid the standalone Undo control when no AI source snapshot is available; it remains visible but
  disabled while a request is active if undo history exists.
- Verified on the preferred simulator that the previously persisted blue-text request now renders both
  widget text elements in blue and that the sample's native gradient renders instead of the fallback
  background.

---

## 2026-08-15 — Home Screen widget font fidelity

- Fixed WidgetKit snapshots to preserve Scriptable system font weight, monospaced, and italic
  semantics separately from UIKit's internal font name. The extension rebuilds system fonts with
  SwiftUI's system APIs and uses `Font.custom` only for actual custom fonts.
- Fixed monospaced Scriptable font factories whose weight prefix previously prevented the runtime from
  constructing a monospaced `UIFont`.
- Added a regression confirming bold system font metadata survives into the widget snapshot. The suite
  now contains sixteen tests.
- Verified the existing Home Screen widget on the preferred simulator renders the title bold while
  retaining a distinct regular-weight date line after rebuilding and reloading the extension.

---

## 2026-08-15 — Public repository and TestFlight preparation

- Excluded the obsolete pre-rename `BetterScriptable/` build tree from source control so generated
  binaries and stale app artifacts cannot enter the public repository.
- Declared that the app does not use non-exempt encryption, preventing App Store Connect export
  compliance from blocking TestFlight processing.
- Added ignored project-local release configuration for the main app and WidgetKit extension,
  including beta description and per-build testing notes.
- Completed App Store document-type metadata by marking the app as an alternate `.scriptable`
  handler that imports rather than edits files in place.

---

## 2026-08-15 — Agent compilation retry

- Added a compile-only JavaScriptCore validation pass after every successful agent `edit_script`
  call, using the same async-function shape as normal script execution so top-level `await` remains
  valid.
- Compilation failures are returned directly to the active ChatGPT tool loop with an instruction to
  continue editing. The agent prompt now explicitly prevents completion until a subsequent edit
  compiles.
- Added regressions for top-level-await compilation, syntax-error detection, and recoverable
  compilation feedback in edit-tool output.
- Compiled the simulator test target, passed all eighteen tests on the preferred simulator, and
  completed a green app/widget build and installation.

---

## 2026-08-15 — Agent widget runtime validation

- Diagnosed a cat-image edit that compiled but failed at runtime because CATAAS rejected the generated
  `fit=crop` query with HTTP 400 JSON, causing `Request.loadImage()` to reject with `not an image`.
- Added an automatic completion gate that executes the fully edited script in a fresh Scriptable
  runtime, waits for asynchronous work, and requires error-free completion plus a widget passed to
  `Script.setWidget`.
- Runtime, network, decoding, timeout, and missing-widget failures are now fed back into the same
  ChatGPT tool loop so the agent continues editing instead of leaving a broken widget.
- Added validator regressions for thrown runtime errors, missing widgets, and successful widgets.
- Changed asynchronous execution failure propagation to retain the JavaScript error message rather
  than the unhelpful JavaScriptCore stack placeholder `@`, giving the agent actionable retry context.
- Passed all twenty-one simulator tests, completed a green app/widget build and installation,
  repaired the persisted simulator script with CATAAS `fit=cover`, and verified its cat image renders
  in the native widget preview.

---

## 2026-08-15 — Editor error actions

- Added a `Show Error` action directly beneath the completed no-widget empty-state description. It
  switches to the source editor, where the existing runtime console exposes the failure.
- Added a `Copy Error` console action whenever runtime error lines are present. It copies all errors
  while excluding ordinary console output.
- Passed all twenty-one simulator tests and completed a green app/widget build and installation.
  Verified with a temporary failing simulator script that `Show Error` opens the editor and
  `Copy Error` places the exact runtime failure on the pasteboard, then removed the temporary script
  and relaunched the app.
- Moved `Show Error` into the empty state's native action area and removed the prominent filled style.
- Diagnosed the cat widget's transient empty state as an unawaited async `main()` call: the outer script
  completed before image loading reached `Script.setWidget`. Updated the agent instructions to always
  await async entry points and repaired the persisted simulator script to use `await main()`.

---

## 2026-08-15 — Rounded Scriptable fonts

- Reproduced `Stupid.scriptable` against both live stats endpoints and traced its rendered error state
  to the missing canonical `Font.boldRoundedSystemFont` factory.
- Added all nine Scriptable rounded system font factories with their correct weights and preserved the
  rounded design through WidgetKit snapshots.
- Added a runtime regression covering `Font.boldRoundedSystemFont(30)` assignment to widget text.
- Passed all twenty-two simulator tests, rebuilt and installed the app, and verified the unchanged
  imported script renders live Search and RPC values on the preferred simulator.
- Passed all twenty-one simulator tests, rebuilt and installed the app/widget bundle, and verified the
  awaited cat widget renders successfully in both the app preview and Home Screen widget.

---

## 2026-08-15 — Widget-context detail execution

- Fixed script details running with `config.runsInApp`, which made scripts such as `Read MacStories`
  take their table/QuickLook branch and cover the detail with a sheet.
- Runtime installation now accepts an explicit widget-execution mode used by detail previews, agent
  validation, and the WidgetKit extension. Explicit app-context QuickLook and table presentation
  behavior remains unchanged.
- Added a regression confirming detail execution selects the widget branch rather than the app branch.

---

## 2026-08-15 — Confirmed script creation

- Changed the main-screen add action to collect a script name before creating any file or list entry.
- Cancelling the naming alert now leaves the script library unchanged; confirming Create persists the
  new script with the entered name.

---

## 2026-08-16 — Script list styling

- Matched stupid torrent's system inset list and compact row treatment, using a body-sized single-line
  script name and a trailing abbreviated relative file-edit date.
- Added the same effective 16-point gap between the large navigation title and first page content as
  stupid torrent's sectioned list.
- Matched its split swipe-action treatment with destructive Delete on the trailing edge and Rename on
  the leading edge. Export remains available from the row context menu.
- Renamed the main navigation heading from Scripts to Widgets.
- Set matching explicit build numbers on the app and WidgetKit extension so App Store archives do not
  inherit mismatched generated defaults.

---

## 2026-08-16 — Detail title editing

- Made the script detail navigation title tappable and added the same Rename Script text-field alert
  used by the main script list.
- Title changes use the existing persistent rename path and immediately update the detail title and
  script execution name while surfacing existing validation errors.
- Bumped the app and WidgetKit extension together from build 3 to build 4 for TestFlight and added a
  project rule requiring synchronized build numbers before release archives and uploads.

---

## 2026-08-16 — Widget creation and gradient rendering

- Changed the new-widget naming alert to use Widget terminology and navigate directly to the new
  widget detail after creation. Rename and storage error alerts now use the same Widget terminology.
- Ordered the app library by descending file-edit time and clear cached URL resource values so an
  autosave immediately moves the edited widget to the top.
- Preserved background gradients, stop locations, and start/end points through the WidgetKit snapshot
  path instead of replacing them with the fallback color. The in-app renderer now honors stop
  locations as well.
- Corrected eight-digit `#RRGGBBAA` color decoding and the explicit alpha argument accepted by
  `new Color(hex, alpha)`, fixing translucent gradient colors used by widget scripts.
- Added regressions for edit-recency ordering, color channels/alpha, and WidgetKit gradient snapshots;
  all twenty-six simulator tests pass.

---

## 2026-08-16 — Explicit script rerun control

- Renamed the detail control's internal render action and accessibility label to explicitly describe
  rerunning the widget script. Reload remains wired to `ScriptExecution.run`, which creates a fresh
  JavaScript runtime and evaluates the current source rather than refreshing the existing SwiftUI tree.
- Added a regression proving consecutive detail runs replace the runtime and produce a new widget.
  All twenty-seven simulator tests pass.

---

## 2026-08-16 — New widget name validation

- Disabled the naming alert's Create action while its input is empty or contains only whitespace.
- Prepopulated new widget names with `Untitled Widget`, focused the field on presentation, and selected
  the complete default name so typing immediately replaces it.
- Bumped the app and WidgetKit extension together from build 4 to build 5 for TestFlight.

---

## 2026-08-16 — Widget HTTP requests

- Added the app's Scriptable-compatible arbitrary-load transport policy to the WidgetKit extension.
  Plain HTTP requests now use the same ATS policy in Home Screen widgets as they do in app previews.
- Bumped the app and WidgetKit extension together from build 5 to build 6 for TestFlight.

---

## 2026-08-16 — Small-widget layout and size previews

- Made widget rendering axis-aware in both app previews and WidgetKit. Text in horizontal stacks now
  keeps its intrinsic width, and fixed stack spacers consume their requested horizontal width instead
  of expanding and forcing labels into distant truncated columns.
- Preserved root widget padding and text minimum scale factors through the WidgetKit snapshot path.
- Added Small, Medium, and Large controls to widget details. Selecting a family reruns the script with
  the corresponding `config.widgetFamily` and renders it at that family's aspect ratio.
- WidgetKit execution now also supplies the actual system family through `config.widgetFamily`.
- Passed all twenty-nine simulator tests, completed an  app/extension build and installation,
  and verified the family selector and correctly sized Small preview on the preferred simulator.
- Bumped the app and WidgetKit extension together from build 6 to build 7 for TestFlight.

---

## 2026-08-16 — Agent API documentation lookup

- Extended the API extraction generator to emit a pages-free `Resources/scriptable-api.json` from the
  same canonical Scriptable source as `docs/scriptable-api.json`, and packaged it in the iOS app.
- Added a bounded `search_api` agent tool. Exact type queries return type summaries and member
  signatures, exact qualified member queries return descriptions, parameters, return values, and URLs,
  and broader terms return up to twelve ranked results.
- Updated the agent instructions to consult API documentation instead of guessing while retaining the
  implemented-API allowlist because the canonical docs also describe APIs that remain unavailable.
- Added regressions for exact member lookup, type overviews, and fuzzy API search.
- Passed all thirty-one simulator tests and verified the bundled resource is present in the built app.
  In an authenticated E2E request, the agent was explicitly asked to look up `Point` and
  `LinearGradient.startPoint`, added only the documented diagonal-gradient assignments, passed
  compilation and runtime validation, and rendered the result; Undo then restored the original script.
- Bumped the app and WidgetKit extension together from build 7 to build 8 for TestFlight.
