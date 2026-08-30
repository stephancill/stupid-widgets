# stupid widgets — App Store Copy

Final App Store Connect text for **stupid widgets** (`net.stupidtech.stupidwidgets`).
Paste directly into the App Store Connect app-page fields. Character limits are noted
as guides for the English (primary) locale.

---

## App name

```
stupid widgets
```

---

## Subtitle (max 30 chars)

```
Scriptable widgets, powered by ChatGPT
```

(_24 chars — within limit._)

## Promotional text

```
Build iOS and Mac widgets with JavaScript.
```

## Description

```
stupid widgets is a lightweight runtime for building rich iOS widgets with JavaScript —
with a widget scripting API that is backwards compatible with Scriptable, plus a
ChatGPT assistant that writes the code for you. Existing Scriptable scripts just run.

Write a widget as a ListWidget script, render it in small, medium, and large, then
pin it to your Home Screen as a live WidgetKit widget. Your scripts also run as Mac
widgets, and iCloud keeps your whole library in sync across iPhone, iPad, and Mac.

Describe the widget you want in plain English and the assistant writes it, compiles
it, and runs it before declaring success. Nothing to set up — just type and watch it
render.

FEATURES
• Scriptable-compatible widget scripting API — existing Scriptable scripts just run.
• Rich widgets built with JavaScript: gradients, stacks, dates, text, and images.
• Preview instantly in small, medium, and large families.
• Bind any Home Screen widget to any script, per instance.
• Mac widget compatibility — the same scripts run on macOS.
• iCloud sync keeps every script in sync across your devices.
• Generate or fix a widget with ChatGPT in plain English.
• Fresh, isolated JavaScript runtime on every run.
• Import, export, rename, and organize scripts with ease.
```

> ~1,100 characters — inside the 4,000-character description limit.

---

## Keywords (limit 100 chars, comma-separated, no spaces)

```
widget,scriptable,script,javascript,home screen,automation,chatgpt,ai,listwidget,ios
```

---

## What's New (first release)

```
First release: build Scriptable-compatible widgets, render them on your Home Screen,
and let ChatGPT write or fix any script.
```

---

## App icon alt text

```
A rounded square app icon for stupid widgets.
```

## Screenshot captions (optional — App Store uses these on Pro Motion listings)

1. **Library** — “Your widgets, all in one place.”
2. **Widget preview** — “Live previews for every widget size.”
3. **Editor** — “Code it, or describe it to the assistant.”
4. **Home Screen widget** — “On your Home Screen, live.”
5. **Preview** — “Rendered with the same widget engine.”

---

## Notes for submission

- **Bundle ID:** `net.stupidtech.stupidwidgets`
- **Display name:** stupid widgets
- **Team ID:** `6JKMV57Y77`
- **Next build:** `13` (increment build 12 → 13 before upload)
- **Export compliance:** `ITSAppUsesNonExemptEncryption = false` is set — no
  encryption declaration needed.
- **App Review caveat to review before upload:** the ChatGPT assistant uses a web-flow
  OAuth and an internal chatgpt.com endpoint that is not an officially documented API.
  Confirm acceptability or guard it behind an opt-in / plan-supported flow before
  shipping, as it may draw review scrutiny.