---
name: stupid-widget-creator
description: Create, design, and debug stupid widgets — JavaScript widget scripts (`.widget` files) for the stupid-widgets iOS app, an API-compatible Scriptable alternative. Use when the user asks to make/build/write a widget, turn an idea or data source into a Home Screen widget, add or update a widget script, style a widget's layout/colors/fonts, or debug why a widget doesn't render or refresh. Covers the `.widget` file format, the implemented JS bridge API (ListWidget, WidgetStack, WidgetText/Date/Image/Spacer, LinearGradient, Color, Font, Request, Script, config), layout guidance for small/medium/large families, and verification in the app and on the Home Screen.
---

# Stupid Widget Creator

stupid widgets is a SwiftUI iOS app that runs Scriptable-style JavaScript through JavaScriptCore.
A *widget* is a single `.widget` file: a JSON envelope wrapping a JavaScript script that builds a
`ListWidget` tree. The same script runs in the app's detail preview and in the WidgetKit Home Screen
extension.

## Workflow

1. **Clarify the ask.** What data should the widget show (static, or live via HTTP), what family
   (small/medium/large), how often it should refresh, and whether tapping should link somewhere.
2. **Read the implemented API before writing JS.** Not the whole Scriptable spec: this app exposes a
   subset, and several registered members do not render yet. See `references/api.md`.
3. **Design the layout** for the target family with the sizing in `references/design.md`.
4. **Write the script** using an async IIFE-friendly top-level style (top-level `await` is supported).
5. **Wrap it in the `.widget` JSON envelope** described in `references/api.md`
   (or run `scripts/make_widget.mjs`).
6. **Verify:** build/install and run it in the app preview, then add it to the Home Screen simulator
   if a full WidgetKit check is wanted (see `references/design.md`).

## Anatomy of a widget script

Minimum viable widget:

```javascript
const widget = new ListWidget();
widget.setPadding(16, 16, 16, 16);

const title = widget.addText("Hello");
title.font = Font.boldSystemFont(16);
title.textColor = Color.white();

const sub = widget.addText("stupid widgets");
sub.font = Font.systemFont(12);
sub.textColor = new Color("#94a3b8");

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
```

Rules that always apply:

- Build one `ListWidget` with `addText`/`addDate`/`addImage`/`addSpacer`/`addStack`.
- When `config.runsInWidget` is true, hand the widget to `Script.setWidget(widget)`; otherwise present
  it with `widget.presentSmall()`, `presentMedium()`, or `presentLarge()` (family preview).
- Always call `Script.complete()` at the end (required for the WidgetKit extension).
- Top-level `await` works, so you can `await` `Request.loadJSON()` directly in the script body.
- `ListWidget` ordering is top-to-bottom; nest rows/columns with `addStack()` and
  `stack.layoutHorizontally()` / `layoutVertically()`.

## Data sources

Use `Request` for live data:

```javascript
const req = new Request("https://api.example.com/stats.json");
req.timeoutInterval = 10; // seconds
const json = await req.loadJSON();
```

`load()`, `loadString()`, `loadJSON()`, and `loadImage()` are implemented. A widget refresh is
bounded by the OS, so keep scripts fast, and **always degrade gracefully**: wrap fetches so one
failed endpoint shows partial data or a message instead of an empty widget (see the `settle` pattern
in `references/design.md`). Set `widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000)`
to hint the next refresh.

## Hard limits (do not rely on these)

The following are registered/generated but **not rendered or not functional yet**:

- `WidgetText` shadows (`shadowColor`, `shadowRadius`, `shadowOffset`) — no visual effect.
- `WidgetStack` backgrounds, `size`, `cornerRadius`, `borderWidth`, `borderColor` — stacks render
  only their layout, spacing, and children. Put backgrounds/borders/corners on the `ListWidget`.
- `WidgetImage.borderColor`, `borderWidth`, `tintColor` — no visual effect; `imageSize`,
  `imageOpacity`, `cornerRadius`, and content mode do render.
- `Color.dynamic(light, dark)` — returns a fixed gray; use a static color instead.
- `ListWidget.url` and element `url` — stored but not yet tappable; harmless to set.
- Large API families — Calendar, Contacts, Location, Photos, Mail, Message, WebView, DrawContext,
  Speech, Reminders, etc. are **absent**. Do not write scripts that use them.

## Repository context

- Widgets live as `.widget` JSON in the app's Documents library (and mirror to the shared
  `group.net.stupidtech.stupidwidgets/Scripts` app-group directory for the extension).
- The app seeds `Bundle.main` `.widget` resources into Documents on first launch without overwriting.
- Canonical Scriptable docs/spec live in `docs/scriptable-api.json` (55 types); this skill's
  `references/api.md` is the authoritative *implemented* subset for writing working widgets.

## Resources

- `references/api.md` — the implemented JS bridge API: `.widget` file format, globals, widget/value
  classes, and verification guidance.
- `references/design.md` — widget family sizes, layout patterns, styling guidance, and complete
  example scripts.
- `scripts/make_widget.mjs` — wraps a JavaScript source file into a valid `.widget` JSON envelope
  (random UUID, correct escaping). Run with `bun`.
- `assets/starter.widget` — a ready-to-copy starter widget envelope.