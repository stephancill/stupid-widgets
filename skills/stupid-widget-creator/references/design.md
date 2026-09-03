# Widget Design Guide

## Home Screen family sizes (points)

WidgetKit family dimensions (device-independent points):

| Family | Size |
|---|---|
| small | 155 × 155 |
| medium | 329 × 155 |
| large | 329 × 345 |
| extraLarge (iPad) | 345 × 345 |

The renderer applies ~14 pt of default padding unless `setPadding` is called; content must fit inside
the padded area. On small widgets that is roughly 127 × 127 pt of usable content.

## Layout guidance

- **Small** = one idea. A big number, a short label, maybe a stack row. Keep to ~3 elements.
- **Medium** = two columns or a value + context row (e.g. two metrics side by side with a title).
- **Large** = room for a header, a few data rows, and a footer; go straight down or use 2 columns.
- Default `ListWidget` layout is vertical; an `addStack()` is horizontal by default. Call
  `layoutVertically()` / `layoutHorizontally()` explicitly for clarity.
- Use `widget.addSpacer()` (expanding) to push content apart, or `addSpacer(n)` for a fixed gap.
- Set `lineLimit` + `minimumScaleFactor` on titles so long strings shrink instead of clipping.
- Prefer `backgroundGradient` over flat `backgroundColor` for depth; the canonical style is a dark
  gradient (`#0b1220 → #1e293b`) with a light accent title and muted label text.

## Refresh strategy

- `widget.refreshAfterDate` hints the next render. The OS ultimately decides cadence and can coalesce
  or defer refreshes; treat it as a hint, not a guarantee.
- Keep network fetches fast (single request where possible, short `timeoutInterval`).
- Cache aggressively if you can; widget runs are memory- and time-limited.

## Graceful degradation pattern

Always settle fetches so one failure doesn't blank the widget:

```javascript
function settle(promise) {
  return promise.then((value) => ({ ok: true, value })).catch((reason) => ({ ok: false, reason }));
}

const [search, rpc] = await Promise.all([
  settle(fetchSearch()),
  settle(fetchRpc()),
]);
```

Render what succeeded, and show a muted error line for what failed (or a compact title-only state
when everything fails). Every branch must end in `Script.setWidget` + `Script.complete`.

## Complete example (small, resilient, data-driven)

See `stupid-counter-widget.txt` at the repository root for the canonical implemented example —
a small widget fetching live stats from two endpoints with a dark gradient, significant-digit
formatting, partial-update handling, and a refresh hint. Pattern to reuse:

```javascript
async function fetchJSON(url) {
  const req = new Request(url);
  req.timeoutInterval = 10;
  return await req.loadJSON();
}

function smallWidget({ a, b, error }) {
  const w = new ListWidget();
  const grad = new LinearGradient();
  grad.colors = [new Color("#0b1220"), new Color("#1e293b")];
  w.backgroundGradient = grad;
  w.setPadding(12, 12, 12, 12);

  const title = w.addText("stupid");
  title.font = Font.semiboldSystemFont(12);
  title.textColor = new Color("#93c5fd");
  w.addSpacer(6);
  // ... metrics ...
  return w;
}

let widget;
try {
  const results = await Promise.all([settle(fetchSearch()), settle(fetchRpc())]);
  widget = smallWidget({ a: results[0].value, b: results[1].value, error: null });
} catch (e) {
  widget = smallWidget({ a: null, b: null, error: e.message });
}

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentSmall();
}
Script.complete();
```

## Verification

1. **App preview (fastest):** create/import the `.widget` in the app; open its detail which reruns the
   script in widget context, or tap a family chip (Small/Medium/Large) to preview that aspect ratio.
2. **Simulator full flow** (per repository AGENTS.md, after app-affecting changes only if you changed
   the app, not just a widget script):
   `stupid-app run --simulator --udid 6552DF1D-95CE-48E3-801F-8F80F0AA8D29`
3. **Home Screen:** after installing, add the widget family and use Edit Widget → Script to pick the
   new script. Multiple instances can each select a different script.

Typical breakage symptoms and causes:

- Widget shows "The selected script did not set a widget" — `Script.setWidget` was not reached
  (error thrown earlier, or the async path wasn't awaited).
- Blank/empty widget — all fetches failed and the error branch didn't render anything visible.
- Autocomplete/agent keeps touching `url` or shadows — registered but no-op; harmless stylistically.
- ExtraLarge/accessory previews look off — extension only registers small/medium/large on the
  Home Screen; accessories are preview-only.