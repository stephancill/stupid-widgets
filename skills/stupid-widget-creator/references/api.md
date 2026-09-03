# Implemented Widget API

The stupid-widgets app runs Scriptable-style JavaScript through JavaScriptCore. This document is the
authoritative **implemented subset** for writing working widgets. Members marked ✗ are registered on
the JS object but have no effect yet (see *No-ops* at the end).

When in doubt, inspect `stupid-widgets/Sources/StupidWidgets/RuntimeRegistration.swift` and
`WidgetModels.swift` — they are the source of truth.

## The `.widget` file format

A widget is a JSON envelope (UTType `public.json`). The app loads files whose path extension is
`widget` from the Documents library and the app-group Scripts mirror.

```json
{
  "id": "0E2E1D1A-4F2D-4B1E-8A3C-9F0F1A2B3C4D",
  "name": "Stupid Counter",
  "icon": { "color": "purple", "glyph": "sun" },
  "script": "// JavaScript source...",
  "always_run_in_app": false,
  "preview_family": "medium",
  "share_sheet_inputs": []
}
```

- `id` — optional; a UUID string. Omit it and the app derives a stable ID from the filename.
- `name` — required display name; must be non-empty and contain no `/` or `:`.
- `icon` — optional metadata for the app list. `color` is a palette name (Scriptable palette, e.g.
  `purple`, `red`); `glyph` is a Font Awesome glyph name.
- `script` — required JavaScript source.
- `always_run_in_app` — optional boolean.
- `preview_family` — optional default preview family (`small` | `medium` | `large`); the app persists
  a per-widget selection.
- `share_sheet_inputs` — optional array.

Generate a valid envelope from any JS file with:

```sh
bun scripts/make_widget.mjs --name "My Widget" --script ./my-widget.js --color purple --glyph sun
```

## Globals

### `config`
- `config.runsInApp` — true when run from the app UI outside a preview/detail context.
- `config.runsInWidget` — true in the detail preview and the WidgetKit extension.
- `config.runsWithSiri` — always false.
- `config.widgetFamily` — `small` | `medium` | `large` | `extraLarge` (plus accessory strings when
  requested). Set by the family selector / extension; defaults to `medium`.
- `config.widget` — always `null`.

### `Script`
- `Script.name()` — **function**, returns the script name.
- `Script.setWidget(widget)` — hands a `ListWidget` to the runtime for preview/Home Screen.
- `Script.complete()` — marks the run complete; required for widgets.
- `Script.setShortcutOutput(value)` — implemented (Shortcuts output).

### `args`
`shortcutParameter`, `plainTexts`, `images`, `urls`, `fileURLs`, `notification`,
`queryParameters`, `widgetParameter` — populated per context; widgets get empty defaults.

### `module` and `importModule(name)`
Per-file `module` objects (`filename`, `list`, `moduleName`, `dependencies`, `exports`).
`importModule(name)` resolves `.js`/`.widget` relative to the importer or search roots. Widgets can be
split across imported files; imports are cached per run.

### `console`
`log`, `warn`, `debug`, `error`, `logError` — route to the in-app console.

## Widget classes

### `ListWidget` (constructor: `new ListWidget()`)
Properties:
- `spacing` — number, gap between child elements.
- `url` ✗ — stored, not tappable yet.
- `refreshAfterDate` — Date; hint for the next widget refresh.
- `backgroundColor` — `Color`.
- `backgroundImage` — `Image`.
- `backgroundGradient` — `LinearGradient`.

Methods:
- `addText(text)` → `WidgetText`
- `addDate(date)` → `WidgetDate`
- `addImage(image)` → `WidgetImage`
- `addSpacer(length?)` → `WidgetSpacer`
- `addStack()` → `WidgetStack`
- `setPadding(top, leading, bottom, trailing)` / `useDefaultPadding()`
- `presentSmall()` / `presentMedium()` / `presentLarge()` / `presentExtraLarge()`
  / `presentAccessoryInline()` / `presentAccessoryCircular()` / `presentAccessoryRectangular()`
  — async previews (in-app only).

### `WidgetStack` (from `addStack()`)
Properties: `spacing`, `url` ✗, `backgroundColor` ✗, `backgroundImage` ✗, `backgroundGradient` ✗,
`size` ✗, `cornerRadius` ✗, `borderWidth` ✗, `borderColor` ✗.

Methods: `addText`, `addDate`, `addImage`, `addSpacer`, `addStack`, `setPadding`,
`useDefaultPadding`, `layoutHorizontally()`, `layoutVertically()`, `topAlignContent()`,
`centerAlignContent()`, `bottomAlignContent()`.

**Stacks render only layout, spacing, and children.** Default layout is horizontal.

### `WidgetText` (from `addText(text)`)
Properties: `text`, `textColor` (`Color`), `font` (`Font`), `textOpacity` (0–1), `lineLimit`
(number; 0 = unlimited), `minimumScaleFactor` (0–1, shrink-to-fit ratio), `url` ✗,
`shadowColor` ✗, `shadowRadius` ✗, `shadowOffset` ✗.

Methods: `leftAlignText()`, `centerAlignText()`, `rightAlignText()`.

### `WidgetDate` (from `addDate(date)`)
Properties: `date`, `textColor`, `font`, `textOpacity`, `lineLimit`, `minimumScaleFactor`, `url` ✗.

Methods: `applyTimeStyle()`, `applyDateStyle()`, `applyRelativeStyle()`, `applyOffsetStyle()`,
`applyTimerStyle()`, `leftAlignText()`, `centerAlignText()`, `rightAlignText()`.

### `WidgetImage` (from `addImage(image)`)
Properties: `image` (`Image`), `resizable` (bool), `imageSize` (`Size`), `imageOpacity` (0–1),
`cornerRadius`, `borderWidth` ✗, `borderColor` ✗, `tintColor` ✗, `url` ✗.

Methods: `applyFittingContentMode()`, `applyFillingContentMode()`, `leftAlignImage()`,
`centerAlignImage()`, `rightAlignImage()`.

### `WidgetSpacer` (from `addSpacer(length?)`)
Property: `length` — fixed size in points; a zero/negative length expands to fill available space.

### `LinearGradient` (constructor: `new LinearGradient()`)
Properties: `colors` (`[Color]`), `locations` (`[number]`, 0–1 per color), `startPoint` (`Point`,
default `(0.5, 0)`), `endPoint` (`Point`, default `(0.5, 1)`).

Assign to `widget.backgroundGradient`. Gradients with matching locations render correctly.

## Value classes

### `Color`
- `new Color(hex, alpha?)` — hex `#RRGGBB` or `#RRGGBBAA`; optional explicit alpha.
- `new Color(red, green, blue, alpha?)` — components 0–1.
- Statics: `Color.red()`, `green()`, `blue()`, `white()`, `black()`, `gray()`, `darkGray()`,
  `lightGray()`, `cyan()`, `yellow()`, `magenta()`, `orange()`, `purple()`, `brown()`, `clear()`.
- `Color.dynamic(light, dark)` — **not functional**; returns gray.

### `Font`
- `new Font(name, size)` — named system/custom font. Use a PostScript-ish name.
- Statics: `Font.systemFont(size)`, weighted `ultraLightSystemFont` … `blackSystemFont`,
  `italicSystemFont(size)`, `*MonospacedSystemFont(size)`, `*RoundedSystemFont(size)`
  (e.g. `Font.boldRoundedSystemFont(30)`).

### `Image`
- `Image.fromFile(path)` / `Image.fromData(data)` — construct an image for `addImage` or
  `backgroundImage`.
- Property `size`.

### `Data`
- Statics: `Data.fromString`, `fromBase64String`, `fromFile`, `fromBytes`, `fromJPEG`, `fromPNG`.
- Methods: `toRawString()`, `toBase64String()`, `getBytes()`.

### `Point`, `Size`, `Rect`
Simple value objects with `x`/`y`, `width`/`height`, and the four rect coordinates.

## Networking

### `Request` (constructor: `new Request(url)`)
Properties: `url`, `method` (default `GET`), `headers` (object), `body`, `timeoutInterval`
(seconds, default 60), `response` (`RequestResponse`).

Methods (async): `load()` → `Data`, `loadString()` → string, `loadJSON()` → object,
`loadImage()` → `Image`. Multipart helpers exist (`addParameterToMultipart`,
`addFileDataToMultipart`, `addFileToMultipart`, `addImageToMultipart`).

`RequestResponse`: `statusCode`, `headers`. Invalid JSON rejects `loadJSON()`.

## Other implemented types

`SFSymbol.named(name)` (empty-image approximation), `Device` statics (`name`, `systemName`,
`systemVersion`, `model`, `isPhone`, `isPad`, `screenSize`, `batteryLevel`, …), `DateFormatter`
(with `use*Style()` methods), `RelativeDateTimeFormatter` (`useNamedDateTimeStyle` /
`useNumericDateTimeStyle`), `Timer` (intervals are **milliseconds**), `FileManager` (`local` /
`iCloud`, directory + read/write APIs, sizes in kilobytes), `Keychain`, `Pasteboard`, `UUID.string()`,
`Path` (no-op). `QuickLook.present`, `Safari.open`, `Alert`, `UITable`/`UITableRow`/`UITableCell`,
`Notification` exist for in-app use but are irrelevant to widgets.

## Absent — never use in widget scripts

`Calendar`, `CalendarEvent`, `CallbackURL`, `Contact`, `ContactsContainer`, `ContactsGroup`,
`DatePicker`, `Dictation`, `DocumentPicker`, `DrawContext`, `Location`, `Mail`, `Message`, `Photos`,
`RecurrenceRule`, `Reminder`, `ShareSheet`, `Speech`, `TextField`, `URLScheme`, `WebView`,
`XMLParser`. Referencing one fails at runtime.

## Validation checklist

Before handing over a widget:

1. Script builds exactly one `ListWidget` and calls `Script.setWidget(widget)` when
   `config.runsInWidget`.
2. `Script.complete()` is always reached (including error paths).
3. Async data fetches are awaited and wrapped so failures degrade gracefully.
4. Only members in this reference are used; no absent types.
5. The script is valid JavaScript (the app re-validates on agent edits; syntax errors reject).
6. The `.widget` envelope has a unique `name` and correct JSON escaping — prefer
   `scripts/make_widget.mjs` to avoid escaping bugs.