# Brand

The logo is an attitude indicator inside a black box. It's the instrument
behind the `ATTITUDE` messages this project records, inside the box that
records them.

## Files

| File | Use |
|---|---|
| `logo-light.svg`, `logo-dark.svg` | The full logo, for light and dark backgrounds |
| `mark-light.svg`, `mark-dark.svg` | The mark alone, where space is tight or the name is already nearby |
| `favicon.svg` | The browser tab icon. It switches theme itself |
| `social-preview.png` | The 1280 × 640 link preview, uploaded in the repo's settings |

The wordmark is JetBrains Mono SemiBold converted to outlines, so it looks the
same everywhere and needs no font installed. The files are plain SVG and open
in Figma, Penpot or Inkscape.

## Using it

Show the version that matches the reader's theme. On GitHub and the docs site
that means a `<picture>` element:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/logo-dark.svg">
  <img alt="telemetry-blackbox" src="docs/brand/logo-light.svg" width="440">
</picture>
```

- **Minimum size:** 16 px for the mark, 160 px wide for the full logo.
- **Clear space:** half the mark's height on every side.
- **Don't** recolour, stretch or rotate it, set the wordmark in another font,
  or put the light version on a dark background.

| Colour | Hex | Where |
|---|---|---|
| Orange | `#f2662b` | The sky, "blackbox" and accents |
| Ink | `#0f1720` | The box and the wordmark on light backgrounds |
| Box (dark) | `#1c2330` | The box on dark backgrounds, with a `#4a5866` edge |
| Ground | `#2a3442` | Below the horizon |
| Light text | `#eaecef` | The wordmark on dark backgrounds |

## Where it appears

| Place | When | Issue |
|---|---|---|
| The README header | Now | |
| The repo's social preview | Day 4 | #29 |
| The demo's opening and closing cards | Day 4 | #29 |
| The Grafana home dashboard | Day 4 | #28 |
| The docs site header and favicon | Stretch | #35 |
| The public Grafana dashboard | Stretch | #36 |
