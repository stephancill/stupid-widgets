# stupid widgets — App Store Listing Kit

This document is the submission package for the iOS App Store listing: the feature
list, the marketing copy, and the screenshot set with exact sizes. Screenshots are
captured from real simulator UI in this repo under `.release/screenshots/`.

## Contact kit

- **Bundle ID:** `net.stupidtech.stupidwidgets`
- **App display name:** stupid widgets
- **Team ID:** `6JKMV57Y77`
- **Ready-to-submit build:** next `CFBundleVersion` is `13`
- **Iteration:** current marketing build deployed via TestFlight (build 12)

## Screenshots

Native-resolution captures (ready for App Store Connect — no resizing needed):

| File | Device | Size (px) | App Store slot |
|---|---|---|---|
| `iphone-17promax-library.png` | iPhone 17 Pro Max | 1320 × 2868 | iPhone 6.9″ |
| `iphone-17promax-detail.png` | iPhone 17 Pro Max | 1320 × 2868 | iPhone 6.9″ |
| `iphone-17promax-preview.png` | iPhone 17 Pro Max | 1320 × 2868 | iPhone 6.9″ |
| `iphone-17promax-editor.png` | iPhone 17 Pro Max | 1320 × 2868 | iPhone 6.9″ |
| `iphone-16plus-library.png` | iPhone 16 Plus | 1290 × 2796 | iPhone 6.7″ |
| `iphone-16plus-detail.png` | iPhone 16 Plus | 1290 × 2796 | iPhone 6.7″ |
| `iphone-17pro-library.png` | iPhone 17 Pro | 1206 × 2622 | iPhone 6.3″ |
| `iphone-17pro-detail.png` | iPhone 17 Pro | 1206 × 2622 | iPhone 6.3″ |
| `ipad-library.png` | iPad Pro 13″ | 2064 × 2752 | iPad |
| `ipad-detail.png` | iPad Pro 13″ | 2064 × 2752 | iPad |

### Suggested screenshot ordering (5–7 iPhone, 2–3 iPad)

1. **Library** (`*-library`) — your widget collection at a glance.
2. **Widget preview** (`*-detail` or `*-preview`) — a live, rendered widget.
3. **Code editor** (`iphone-17promax-editor`) — the JavaScript editor with
   syntax-colored source.

Keep the ordering consistent across every size so each iPhone/iPad sequence tells the
same story.

---

## Feature list

1. **Scriptable-compatible** — run existing Scriptable-style JavaScript through the
   same `ListWidget`/`WidgetText`/`WidgetStack` widget tree the ecosystem uses.
2. **A widget library, not a code dump** — create, rename, import, export, duplicate,
   and reorder scripts; small/medium/large previews flip instantly.
3. **Live iOS Home Screen widgets** — render any script as a real Home Screen widget
   via WidgetKit, each instance bound to its own script.
4. **Build with ChatGPT** — describe a widget in plain English and get a working,
   validated script; iterate with inline Undo/Redo and rerun.
5. **AI that verifies its work** — the assistant reads and edits your source, then
   compiles and runs it before declaring success.
6. **iCloud sync** — scripts stay in sync across your devices.
7. **A safe, sandboxed runner** — every run gets a fresh JavaScript context so a buggy
   script can’t leak state into the next one.

## Description (draft)

> **stupid widgets** is a lightweight, Scriptable-compatible way to build rich iOS
> widgets with JavaScript — powered by ChatGPT.
>
> Write your widget as a `ListWidget` script, render it to a live Home Screen widget,
> and keep your whole library in sync across devices via iCloud. Describe what you
> want in the assistant and the app writes a validated, working widget for you — then
> it reruns it before showing you the result.
>
> **Features**
> - Run Scriptable-style widgets: gradients, stacks, dates, and images.
> - Preview in small, medium, and large families.
> - Bind any Home Screen widget to any script, per instance.
> - Ask ChatGPT to generate or fix a widget in plain English.
> - Fresh, isolated JavaScript runtime on every run.
> - iCloud sync for your whole script library.

## What’s New (first commercial release — example)

> - First App Store release of side-by-side widget + code editing.
> - ChatGPT assistant writes, edits, and validates your widgets.
> - Home Screen widgets bound to individual scripts.
> - iCloud library sync with robust rename/duplicate handling.

## Keywords (suggestion)

`widget, scriptable, script, javascript, home screen, automation, chatgpt, ai,
listwidget, ios widget`

## Export compliance

`ITSAppUsesNonExemptEncryption = false` (set). No suppression needed.

## Notes / caveats for App Review

- The App Transport Security exception (`NSAllowsArbitraryLoads`) is present for
  script-initiated web requests. Fine to leave; scripts are user-authored.
- The assistant uses a ChatGPT web-flow OAuth that is currently an **undocumented
  internal endpoint**. Confirm with OpenAI before shipping if App Review scrutinizes
  it, or guard behind opt-in.
- Home Screen widget preview images are rendered from a script snapshot; no
  user-generated content policy issues expected.