# stupid widgets Engineering Handover

Last updated: 2026-08-15

## Current state

stupid widgets is an xtool/SwiftUI iOS app that runs Scriptable-style JavaScript through
JavaScriptCore. The app now has a persistent Documents-backed script library, an editor, fresh
per-run JavaScript contexts, native preview/table/alert presentation, and a client-side ChatGPT AI
assistant. The former Cloudflare/OpenRouter Worker source has been removed.

Verified on `NoFeedSocial iOS 26.3` (`6552DF1D-95CE-48E3-801F-8F80F0AA8D29`):

- The app builds, installs, and launches with xtool.
- Missing bundled samples are seeded into Documents on startup and edits remain across relaunches.
- Create, rename, delete, import, export, and editor autosave are implemented.
- `Hello Widget` runs through the repaired bridge and presents a native widget preview.
- ChatGPT authorization uses an in-app authentication session with OpenCode's browser OAuth flow,
  PKCE, state validation, and automatic callback handling.
- Completed ChatGPT authorization, direct Codex SSE generation, automatic insertion, persistence,
  and execution of generated code have passed end to end on the preferred simulator.
- A generic WidgetKit extension runs mirrored `.scriptable` files through the existing JavaScriptCore
  bridge. Per-instance App Intent configuration allows multiple Home Screen widgets to select
  different scripts.
- Sixteen API-conformance/AI-tool/module/bridge/runtime/persistence tests execute and pass on the
  preferred simulator through the Swift package's generated Xcode scheme.
- Signed device builds persist OAuth and Scriptable `Keychain` values in Keychain Services. xtool's
  pseudo-signed simulator app receives `errSecMissingEntitlement`, so both use isolated,
  development-only UserDefaults records under `targetEnvironment(simulator)`.

The application is usable but is not yet a complete Scriptable replacement. Twenty-two canonical
types remain absent, several registered APIs remain partial, and five of Scriptable's six extension
categories are not present.

## Sources of truth

Read these before changing the project:

1. `AGENTS.md`
2. `docs/engineering-handover.md`
3. `docs/scriptable-architecture.md`
4. `docs/implementation-notes.md`
5. `docs/scriptable-api.json`
6. `stupid-widgets/Tests/StupidWidgetsTests/GeneratedAPIContract.swift`

The generated API contract contains 55 types, four globals, one global function, and 706 documented
members. `tools/generate-api-spec.mjs` writes both contract files; do not edit the generated Swift
fixture by hand. Do not infer behavioral compatibility from registrations alone. The extracted
Scriptable bundle is under ignored `third-party/scriptable/` and must not be committed.

## Layout

```text
./
├── AGENTS.md
├── docs/
├── tools/generate-api-spec.mjs
├── third-party/scriptable/                 # ignored upstream extraction
└── stupid-widgets/
    ├── Package.swift
    ├── Info.plist
    ├── xtool.yml
    ├── Resources/
    ├── Sources/StupidWidgets/             # StupidWidgetsCore
    ├── Sources/StupidWidgetsApp/          # isolated SwiftUI @main entry
    ├── Sources/StupidWidgetsWidgetExtension/
    ├── WidgetMetadata/Metadata.appintents/ # generated App Intent metadata packaged by xtool
    └── Tests/StupidWidgetsTests/
```

The obsolete `ai-backend/` directory, including ignored local secrets, dependencies, and Wrangler
build output, has been removed. It is no longer part of the application.

This exported workspace has no `.git` metadata. Do not initialize or publish a replacement
repository without locating the authoritative repository.

## Build and verification

From `stupid-widgets/`:

```sh
xtool dev run --simulator \
  -u 6552DF1D-95CE-48E3-801F-8F80F0AA8D29 \
  --no-attach --no-logs --launch-timeout 300
```

Compile the simulator test target without invoking the currently un-linkable standalone runner:

```sh
swift build --target StupidWidgetsTests \
  --triple arm64-apple-ios-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"
```

Execute the tests on the preferred simulator:

```sh
set -o pipefail && xcodebuild test \
  -scheme StupidWidgets-Package \
  -destination "platform=iOS Simulator,id=6552DF1D-95CE-48E3-801F-8F80F0AA8D29" \
  | xcpretty
```

Latest verification results:

- xtool app build, installation, and launch: passed without compiler warnings.
- `StupidWidgetsTests` simulator target compilation: passed.
- Simulator-hosted `xcodebuild test`: sixteen tests passed.
- Standalone `swift test` with an iOS triple builds and links, but SwiftPM then attempts to load the
  iOS test bundle in the macOS host process. Use the simulator-hosted `xcodebuild test` command.

Do not package a top-level directory named `Resources`; xtool/Foundation then treats the generated
app as a legacy bundle and installation fails with `Missing bundle ID`. Keep the two resources
listed individually in `xtool.yml`.

If a cancelled build appears locked, inspect `xtool`, `swift-build`, `swift-driver`, and
`swift-frontend` process command lines and terminate only processes belonging to this project.

## Script library

`Models.swift` defines strict `.scriptable` decoding/encoding and `ScriptStore`.

- On startup, missing bundled samples are copied to Documents without overwriting existing files.
- Documents is the writable source of truth.
- Writes are atomic.
- User-facing operations report errors rather than silently discarding them.
- Names reject empty values and path separators; imports and creates choose a unique name.
- Editor and AI insertions use the same persistent source update path.
- `.scriptable` is declared as an imported JSON document type in `Info.plist`.

The editor currently writes on each source change. A cancellable debounce is an optional future
optimization, not a correctness requirement.

### Current simulator data

The E2E verification intentionally exercised autosave against the Documents copies:

- `Hello Widget` currently contains an AI-generated Cape Town weather widget backed by Open-Meteo.
  The app shows it as 97 non-empty lines. An agentic follow-up changed only its two title strings to
  `Cape Town Live`; the native preview then showed 18°C, partly cloudy, feels-like 18°C, and 5 km/h
  wind.
- `Read MacStories` has one harmless additional newline from simulator editor interaction and is
  shown as 62 lines.
- The checked-in files under `stupid-widgets/Resources/` remain unchanged.

To restore either simulator sample using only app behavior, delete its Documents copy from the
script list and relaunch the app. Startup seeding copies the missing bundled resource back into
Documents without overwriting other scripts.

## JavaScript runtime

`JSRuntime` owns a `JSContext`, native object IDs, class specifications, static handlers, and
published presentation state. `ScriptExecution` creates and installs a new runtime for every Run,
which prevents lexical declarations and global mutations from leaking between runs.

The generated per-class bootstrap now:

- terminates generated statements defensively;
- installs descriptors without the previous array-call syntax error;
- unwraps native object markers returned through Promises;
- wraps native object arguments and property values before crossing into Swift;
- provides `_scriptable_keys`, `_scriptable_values`, `toJSON`, and `toString`;
- records each constructor in `__bs._classes`.

Evaluation runs in an async IIFE, supports top-level `await`, reports Promise rejection stacks, and
only presents a widget after asynchronous completion.

`importModule` now creates a local `module` object for each imported file, returns and caches
`module.exports`, inserts initial exports before evaluation for circular dependencies, records direct
dependency paths, and evicts failed evaluations so they can be retried. Resolution supports optional
extensions, `.js` and `.scriptable` files, paths relative to the importing module, configured search
roots, leading-slash paths relative to a search root, and directory `index.js`/`index.scriptable`.
Missing, decode, syntax, and runtime failures surface as JavaScript errors. The main script still has
no known source URL, and iCloud/app-group search roots and a populated `module.list` are not present.

## WidgetKit extension

`StupidWidgetsWidgetExtension` is a generic runner rather than a hard-coded native widget:

- The app mirrors the full Documents script library into
  `group.net.stupidtech.stupidwidgets/Scripts` on load and every write/rename/delete.
- Running a script that successfully produces a `ListWidget` requests a WidgetKit timeline reload.
- The extension loads the script selected for that widget instance, creates a fresh `JSRuntime`, sets
  `config.runsInWidget`, waits for asynchronous completion, snapshots the native widget tree into
  Sendable values, and renders it with SwiftUI.
- Font snapshots preserve Scriptable system weight, monospaced, and italic semantics explicitly;
  custom fonts retain their names and sizes.
- `SelectScriptIntent` uses a dynamic `AppEntity` query over the mirrored script library. Every Home
  Screen widget instance stores its own selection, so multiple instances can run different scripts.
- Small, medium, and large system families are registered. Accessory families remain absent.

xtool does not run `appintentsmetadataprocessor`. The generated
`WidgetMetadata/Metadata.appintents` directory is therefore packaged explicitly as an extension
resource. Regenerate it with an Xcode build of the `StupidWidgetsWidgetExtension` scheme whenever
`SelectScriptIntent`, `ScriptEntity`, or `ScriptQuery` changes, then replace the checked-in metadata.
Without it, `chronod` reports `Metadata not found for ... SelectScriptIntent` and hides the widget
from the gallery.

Verified Home Screen flow on the preferred simulator:

1. Run the Cape Town weather script in stupid widgets.
2. Edit Home Screen, choose Add Widget, and select stupid widgets.
3. Add the medium family; it renders live Cape Town weather through JavaScriptCore.
4. Long-press it and choose Edit Widget. The Script picker lists both `Hello Widget` and
   `Read MacStories`; each added instance can retain a different selection.
5. Reinstall and relaunch the app. The selection persists and the mirrored library reload refreshes
   the timeline without a transient missing-script state.

High-impact fixes included in the current implementation:

- `new Request(url)` retains its URL.
- Request responses and table-created cells receive native object IDs.
- Invalid JSON rejects `Request.loadJSON()`.
- `Font(name, size)`, widget images, and spacer lengths honor constructor/method arguments.
- Stack layout defaults horizontal and stack padding methods work.
- `UITable.removeRow(row)` no longer performs unsafe empty-array index arithmetic.
- FileManager directory APIs are methods, file sizes are kilobytes, and `fileName` honors its
  extension argument.
- Timer intervals are milliseconds.
- `Script.name()` is a function.

## ChatGPT integration

`AIClient.swift` handles ChatGPT OAuth, while `AgentAIClient.swift` mirrors OpenCode's Codex
Responses tool loop:

- OAuth client: `app_EMoamEEZ73f0CkXaXp7hrann`.
- Authorization starts at `https://auth.openai.com/oauth/authorize` in an
  `ASWebAuthenticationSession`, using OpenCode's browser-flow parameters and the registered
  `http://localhost:1455/auth/callback` redirect.
- A short-lived local TCP listener on port 1455 receives the loopback callback and returns a small
  completion response before the app closes the authentication session. Treating `http` as a direct
  authentication-session callback scheme caused redirects to loop and must not be restored.
- The app generates a fresh cryptographic PKCE verifier/challenge and state for every attempt,
  validates the complete callback origin/path and state, then exchanges the returned authorization
  code at `https://auth.openai.com/oauth/token`.
- On signed devices, credentials are persisted as one Keychain record with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- On xtool's pseudo-signed simulator, OAuth credentials use a development-only UserDefaults record
  because Security.framework returns `errSecMissingEntitlement` (`-34018`). An attempted explicit
  access-group entitlement made the pseudo-signed app fail to launch and was removed.
- Access tokens refresh five minutes before expiry, preserving the previous refresh token when the
  response does not rotate it.
- Completions stream from `https://chatgpt.com/backend-api/codex/responses` using Responses SSE.
- `response.completed` terminates each provider turn immediately instead of waiting for the HTTP
  connection to close.
- The model receives `read_script(offset, limit)` and `edit_script(old_text, new_text)` tools rather
  than the entire editor contents. Reads are capped at 200 numbered lines. Edits require one exact,
  unique match and fail loudly on zero or multiple matches.
- Tool calls are accumulated by Responses item ID, replayed with `function_call_output`, and may run
  for up to one hundred provider turns. Encrypted reasoning continuation data is preserved with
  `store: false`.
- Successful edit tools update the editor through the normal autosave path; final assistant text is
  only a short summary and no longer reproduces the full script.
- Script details expose an inline bottom control rather than a separate assistant screen: standalone
  Undo and Reload buttons flank a material-capsule prompt with its own Play submit action. Prompt text
  stays visible and editing/Undo are disabled during a request, then the prompt clears on completion.
  Successful edits rerun the widget; Undo restores the source snapshot from before the latest AI edit
  and reruns it, while Reload executes the current source again in a fresh runtime.
- Cancellation terminates the local stream task.

The ChatGPT backend endpoint and borrowed OpenCode client registration are undocumented interfaces.
They can change and should not be assumed App Store-safe without OpenAI approval. Tokens, account
IDs, and response bodies must never be logged.

The AI prompt describes the high-value implemented surface and exposes a bounded `search_api` tool
backed by `Resources/scriptable-api.json`. `tools/generate-api-spec.mjs` generates that pages-free app
resource from the same canonical extraction as `docs/scriptable-api.json`, so the agent can look up
exact types, members, signatures, parameters, return values, summaries, and documentation URLs without
embedding the full 55-type reference in every request. Canonical docs include APIs that are not
implemented yet; the system prompt's supported-type allowlist and runtime validation remain the
execution guardrails.

The latest verified AI E2E sequence was:

1. Open the existing `Hello Widget` editor with the persisted ChatGPT authorization.
2. Generate a Cape Town weather widget using Open-Meteo and run it successfully in the native
   medium-widget preview.
3. Ask to change both visible titles from `Cape Town Weather` to `Cape Town Live` without changing
   anything else.
4. Confirm the agent reads bounded script context, applies two targeted edits, and completes in under
   ten seconds without emitting the full 97-line script.
5. Run again and confirm the updated title and live Cape Town weather remain correct.

## Tests

`Package.swift` separates `StupidWidgetsCore` from the small `StupidWidgetsApp` target that owns
SwiftUI `@main`. `StupidWidgetsTests` covers generated API structure, bridge/bootstrap
installation, top-level await, fresh-context isolation, named widget-color assignment, WidgetKit
font metadata, agent read/edit tools, and persistence. All sixteen tests execute through the generated Xcode scheme on the preferred simulator, so the
documented command is suitable for simulator CI coverage.

`tools/generate-api-spec.mjs` normalizes documented properties and instance/static Promise methods
into `GeneratedAPIContract.swift`. `APIConformanceTests` compares that generated contract with a
read-only snapshot of installed `JSClassSpec` shapes. Current structural classifications are:

- 16 complete registered types, checked member-for-member and by placement;
- 16 partial registered types, explicitly inventoried;
- 22 absent canonical types, explicitly inventoried;
- `Script`, checked separately as a plain global object;
- `RequestResponse` and `NotificationAction`, accepted as internal helper registrations.

These are structural checks, not behavioral compatibility claims. Partial types are currently status
locked but do not yet snapshot every known missing, extra, misplaced, or sync/async member.

## Remaining compatibility work

Entirely absent canonical types:

`Calendar`, `CalendarEvent`, `CallbackURL`, `Contact`, `ContactsContainer`, `ContactsGroup`,
`DatePicker`, `Dictation`, `DocumentPicker`, `DrawContext`, `Location`, `Mail`, `Message`, `Photos`,
`RecurrenceRule`, `Reminder`, `ShareSheet`, `Speech`, `TextField`, `URLScheme`, `WebView`, `XMLParser`.

Important partial areas:

- Alert text fields are not represented or rendered.
- Module loading still lacks iCloud/app-group roots and a populated `module.list`.
- Notifications lack permission request/error propagation and complete trigger behavior.
- FileManager iCloud/bookmark/tag/extended-attribute behavior remains absent.
- Widget rendering omits several stack/image styles, links, accessory families, and configurable
  parameters beyond script selection.
- Request multipart signatures and redirect callbacks remain incomplete.
- UITable static factory placement, subtitles, alignment, and remote images remain incomplete.
- Color parsing/mutation and `Color.dynamic` are not fully compatible.
- No Calendar/Contacts/Photos/Location/Reminders permission declarations exist yet.
- No Shortcuts, share, notification-content, or QuickLook extension exists.

## Next priorities

1. Expand partial-type conformance tests to snapshot missing, extra, misplaced, and async-mismatched
   members.
2. Complete Alert/TextField, UITable, Request, Notification, Color, Font, and FileManager behavior.
3. Add low-dependency absent APIs: `URLScheme`, `Speech`, `XMLParser`, `ShareSheet`, then
   `DatePicker` and `CallbackURL`.
4. Finish module search roots/`module.list` and resolve the main script relative to its file URL.
5. Add permission-backed APIs in coherent framework groups.
6. Complete WidgetKit rendering fidelity and add App Intents/Shortcuts, share, and notification
   extensions.
7. Replace the undocumented ChatGPT client registration if an approved native registration becomes
   available.

Before committing, build/install on the preferred simulator, compile the test target, update
`docs/implementation-notes.md`, and inspect changes for credentials or generated artifacts.
