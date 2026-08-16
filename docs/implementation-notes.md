# Implementation Notes

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
- iOS app first (xtool/SwiftUI + JavaScriptCore).
- API-compatible: existing Scriptable scripts should run on our platform.
- AI editor: Cloudflare Worker backend (Hono + openai), backend-managed OpenAI key,
  chat generate + iterate UX grounded on `docs/scriptable-api.json`.

### Notes / caveats
- Main executables are FairPlay-encrypted; Swift implementation is not readable. The readable
  resources fully cover the API contract and architecture.
- Spec source of truth: bundled `docs/*.json`; cross-checked with `prototype-extensions.js`.
- No entitlements file shipped in the .ipa (provisioning profile not included in download).

### Next steps
- Scaffold iOS app (xtool) + API-compatible JavaScriptCore bridge, testable against
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
└── stupid-widgets/                  # iOS app (xtool SwiftPM) — IN PROGRESS
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
- xtool SwiftPM app, bundle ID `net.stupidtech.stupidwidgets`, `infoPath: Info.plist`
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
  xtool dev run --simulator -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach --no-logs --launch-timeout 300
  ```
- **CRITICAL build hygiene (learned the hard way):** SwiftPM locks `.build/`. If a build is
  aborted mid-run, its child `swift-build` process keeps the lock and every later build blocks
  on `waiting until that process has finished execution`. Always
  `pkill -9 -f xtool; pkill -9 -f swift-build` before retrying. **Run builds in the foreground**
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
- Changed `xtool.yml` to package the two sample scripts individually at the app bundle root. A
  top-level directory named `Resources` made Foundation interpret the generated app as a legacy
  bundle, hide its root `Info.plist`, and caused simulator installation to fail with
  `Missing bundle ID`. Root packaging also matches `ScriptStore`'s resource lookup.
- Verified `xtool dev run --simulator -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach
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
- Rebuilt and installed with xtool, requested a script through the simulator AI panel, verified
  auto-insertion of `console.log("APP_E2E_OK");`, ran it, and observed `APP_E2E_OK` in the in-app
  console.

---

## 2026-08-15 — Engineering handover consolidated

- Added `docs/engineering-handover.md` as the current takeover guide for another engineer.
- Consolidated verified build and AI E2E state, repository and runtime architecture, exact file
  references, API coverage, local credential handling, xtool recovery steps, manual verification
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
  generated xtool scheme has no test action.
- Verified a green xtool build/install, persistent edits across relaunch, Hello Widget preview,
  completed ChatGPT device authorization, direct Codex SSE generation, automatic editor insertion,
  persistence across relaunch, and execution of generated `CHATGPT_CLIENT_OK` code on the preferred
  simulator.
- Completed OAuth initially failed to persist with `errSecMissingEntitlement` (`-34018`). xtool
  pseudo-signing rejects explicit Keychain access-group entitlements on simulator launch, so
  simulator builds use isolated development-only UserDefaults records for OAuth and the Scriptable
  `Keychain` API. Signed device builds continue to use Keychain Services.
- The xtool build/install/launch command completed successfully: `xtool dev run --simulator -u
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
  `StupidWidgetsApp` target containing only SwiftUI `@main`. The single xtool library product
  still packages the app target and its core dependency.
- Added `StupidWidgetsRootView` as the core-to-app boundary and changed the test target to import
  `StupidWidgetsCore`, removing the duplicate `_main` test-link failure.
- Updated the reflection regression to avoid relying on `Array.prototype.includes` when validating
  the ES6-compatible JavaScriptCore surface.
- Executed all four tests successfully on `NoFeedSocial iOS 26.3` with `xcodebuild test -scheme
  StupidWidgets -destination "platform=iOS Simulator,id=6552DF1D-95CE-48E3-801F-8F80F0AA8D29"`.
- Verified `xtool dev run --simulator -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 --no-attach
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
- Executed eight tests successfully on `NoFeedSocial iOS 26.3`, then verified the xtool app build and
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
- Executed all eleven tests successfully on `NoFeedSocial iOS 26.3`, verified a green xtool build and
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

- Added `StupidWidgetsWidgetExtension` as a second xtool SwiftPM product with shared app-group
  entitlements on the app and extension.
- Added non-destructive mirroring of the complete Documents script library into the app group. Script
  creates, edits, imports, renames, and deletes update the mirrored files; successful widget runs and
  startup synchronization reload WidgetKit timelines.
- Added a public runner boundary that executes the selected JavaScript in a fresh `JSRuntime`, waits
  for asynchronous completion, snapshots widget text/images/stacks/spacers into Sendable values, and
  renders the snapshot inside the extension.
- Added an App Intent widget configuration with a dynamic script entity query. Every Home Screen
  instance stores its own script selection, enabling multiple widgets backed by different scripts.
- Discovered that xtool does not invoke `appintentsmetadataprocessor`. Generated the metadata with an
  Xcode build and explicitly packaged `WidgetMetadata/Metadata.appintents`; `chronod` then resolved
  `SelectScriptIntent` and exposed the configurable widget in the gallery.
- Added a medium stupid widgets widget to the preferred simulator Home Screen. It rendered the
  AI-generated Cape Town weather script with live Open-Meteo data. `Edit Widget` displayed both
  `Hello Widget` and `Read MacStories` in the per-instance Script picker.
- Fixed a startup mirroring race that briefly removed the shared Scripts directory during timeline
  requests. Mirroring now removes only stale files, writes atomically, and reloads timelines after the
  library is complete.
- Verified a final xtool build/install, app relaunch, persistent widget selection, live Home Screen
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
  lists, passed all fourteen simulator tests, completed a green xtool app/widget build and install,
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
  by xtool and App Store validation.

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
  completed a green xtool app/widget build and installation.

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
- Passed all twenty-one simulator tests, completed a green xtool app/widget build and installation,
  repaired the persisted simulator script with CATAAS `fit=cover`, and verified its cat image renders
  in the native widget preview.

---

## 2026-08-15 — Editor error actions

- Added a `Show Error` action directly beneath the completed no-widget empty-state description. It
  switches to the source editor, where the existing runtime console exposes the failure.
- Added a `Copy Error` console action whenever runtime error lines are present. It copies all errors
  while excluding ordinary console output.
- Passed all twenty-one simulator tests and completed a green xtool app/widget build and installation.
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
