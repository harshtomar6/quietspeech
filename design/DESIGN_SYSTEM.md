# QuietSpeech — Interface System

One product, three surfaces: settings, onboarding, and the dictation overlay.
They share one accent palette, one type scale, one surface language, and one motion
vocabulary. Native macOS structure first; brand second.

Reference implementation: `design/quietspeech-system.html` (open directly, or add
`?theme=light|dark&palette=cyan|indigo&view=foundation|settings|onboarding|overlay`).
Tokens: `design/tokens.css`

## Principles

1. **One accent per palette.** Cyan (`#0E8FA3` / `#5CE1E6`) is the default;
   Indigo (`#4F46E5` / `#818CF8`) is the alternate. The accent means "QuietSpeech"
   and "active". Green, amber, and red are status only, never decoration.
2. **Native bones.** A hidden title bar with traffic lights, a translucent
   sidebar, 13px body text, 28–34px controls, and standard focus rings. The app
   should read as a Mac app before it reads as a landing page.
3. **One surface language.** Opaque cards, 1px borders, 10–14px radii, and
   restrained single-layer shadows. Materials are reserved for the sidebar and
   the overlay.
4. **Quiet hierarchy.** 13px body, 11px secondary, 10px section labels. Headings
   earn size; supporting copy does not.
5. **Motion explains change.** 130–180ms for controls, 220–260ms for panes and
   steps, 220ms fade for the overlay. No bounce except the overlay entrance.

## Brand

- **App icon: “voice ribbon.”** A glossy cyan ribbon forms one tall central
  crest with two lower waves, on a deep navy squircle. No letter, microphone,
  speech bubble, or caret. The production master is `icons/PlainVoice-1024.png`;
  `icons/PlainVoice.icns` is copied to `Resources/AppIcon.icns`.
- **Use the supplied artwork.** `icons/` is the source of truth. Do not redraw
  or hand-trace the ribbon. `build-app.sh` and `package.sh` copy
  `Resources/AppIcon.icns` and the `Resources/MenuBarIcon*.png` template reps
  into the app bundle.
- **Menu bar mark.** The supplied line-art `MenuBarIcon-Outline` template,
  optically thickened on its 30×20pt canvas so the ribbon stays legible at
  status-bar size. It inherits the menu bar tint and warms to system red while
  dictation is active; macOS’s microphone privacy indicator may cover it.
- **One artwork, three sizes.** `Sources/QuietSpeech/BrandMark.swift` loads the
  template and scales it for 30×20pt (menu bar), 21pt (Settings sidebar), and
  31pt (onboarding tile) widths. The menu bar uses the template directly;
  sidebar and onboarding place it in on-accent on an accent-filled tile.
- **Clear space.** Respect the padding built into the supplied artwork. Let the
  icon breathe on the Dock; do not add labels or badges to the app icon.

## Tokens

| Category | Values |
| --- | --- |
| Accent | `#0E8FA3` / `#5CE1E6`; soft 10–12%; ring 24–28% |
| Accent fill | `#0B7F92` / `#5CE1E6`; filled controls only (4.9:1 with white) |
| Status | success `#159C63` / `#3DDC94`; warning `#CF8410` / `#E0A63A`; danger `#D9463F` / `#FF6B62` |
| Window | `#FBFBFD` / `#0A141B` |
| Sidebar | `#F3F4F8` at 88% / `#0B1820` at 90% |
| Card | `#FFFFFF` / `#121F27` |
| Field | `#FFFFFF` / `#0C181F` |
| Text | `#151A21` / `#E9EDF3`; secondary `#59616F` / `#A2ACBA`; tertiary `#8B93A1` / `#79828F` |
| Type | 10 / 11 / 12 / 13 / 15 / 17 / 20 / 24 / 30px; titles `-0.02em`; caps `+0.08em` |
| Weight | 400 regular, 500 medium, 600 semibold, 700 bold |
| Space | 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32 / 40 / 48 |
| Radius | 4 keycap, 6 control, 8 field, 10 tile, 12 card, 14 window, 999 capsule |
| Controls | 26 small, 30 regular, 34 large |
| Motion | 130ms hover, 180ms base, 260ms surface change, `cubic-bezier(.2,.7,.3,1)` |

## Palettes

Two complete palettes ship with the prototype. Structure, type, spacing, and
status roles stay fixed; only the accent and neutral temperature change.

| Token | Cyan (default) | Indigo |
| --- | --- | --- |
| Accent | `#0E8FA3` / `#5CE1E6` | `#4F46E5` / `#818CF8` |
| Accent fill | `#0B7F92` / `#2BB8C9` | `#4338CA` / `#818CF8` |
| Accent text | `#0A7182` / `#7AEEF2` | `#4338CA` / `#A5B4FC` |
| On accent | `#FFFFFF` / `#052A33` | `#FFFFFF` / `#15123A` |
| Page | `#E9EBF1` / `#0A0C10` | `#E7EAF4` / `#080910` |
| Window | `#FBFBFD` / `#16191F` | `#FBFBFE` / `#141622` |
| Card | `#FFFFFF` / `#1C2027` | `#FFFFFF` / `#1B1D2B` |
| Text | `#151A21` / `#E9EDF3` | `#171829` / `#ECEEF8` |

Switch with the topbar palette control, or `?palette=cyan|indigo`. Components
consume tokens only, so nothing is restyled per palette.

## Surfaces

### Settings

- Window: `942 × 704`, hidden title bar, traffic lights over the sidebar.
- Sidebar: 216–224px, controlled translucency, 30px nav rows, 13px labels.
  Selection is a filled accent row, not a soft tinted nav chip.
- Content: 28px horizontal padding, 18px top padding.
- Groups: one 10px grouped surface with hairline separators; the section label
  sits outside. No independent cards, metric tiles, or dashboard grids.
- Rows: 44–48px; 13px medium label, 11.5px secondary, and a trailing native
  control, keycap group, status, or disclosure chevron.
- Header: 22px title, 13px functional description, small dot-plus-label status.
  No marketing hero, gradient banner, or decorative arcs.

### Onboarding

- Window: `620 × 580`, same hidden title bar, traffic lights, and typography.
- Progress: five 4px segments; completed and current use the accent.
- Content: one 52px icon tile, 23–24px title, 13px supporting copy, one card.
- Steps use the same card, row, keycap, and button components as Settings.
- Footer: 30–34px controls, primary action on the right, one accent button.

### Overlay

- One floating material surface, 1px light border, 16px shadow, no heavy glow.
- Capsule: `380 × 54`, radius 27. Card: `360 × 102`, radius 16.
- The accent follows the selected palette. The target-app icon anchors it in the
  real world.
- State: listening = accent pulse; processing = amber; done/inserted = success
  green; error = danger red.
- Live text 14px, secondary metadata 11.5px, timer 11px monospaced.
- Enter with 300ms spring (scale 0.985 → 1, y 5 → 0); exit with 220ms fade.

## Components

- **Buttons.** Primary: accent fill (`#0B7F92` in light so white text clears
  4.5:1), white text, 7px radius, 30px height. Secondary: neutral fill, 1px
  border. Tertiary: borderless, text link.
- **Fields.** 30px height, 8px radius, field surface, 1px border; focus adds a
  3px accent ring.
- **Groups.** Opaque surface, 1px border, 10px radius, hairline row separators;
  group headers sit outside the surface. Reserve standalone cards for onboarding
  and the overlay preview.
- **Rows.** 13px medium title, 11.5px secondary subtitle, trailing native
  control or chevron, 44–48px minimum height.
- **Section labels.** Sidebar groups: 10px semibold uppercase. Settings group
  headers: 11px semibold sentence case, secondary.
- **Status pills.** 20px height, capsule, 10.5px medium; dot plus label.
- **Keycaps.** 18px height, 4–5px radius, sunken surface, 1px strong border,
  10px semibold.
- **Segmented control.** 26px track, 8px radius, sliding card surface, no system
  blue tint.
- **Toggles.** Use the native switch shape and accent; label left, switch right.
- **Pop-up menus.** 22px high, 5px radius, native bezel and down chevron.

## Native settings treats

- Prefer grouped lists over hero cards, metric grids, and marketing copy.
- A sidebar selection is an accent-filled row with on-accent text.
- Use native trailing patterns: switch, pop-up menu, disclosure chevron, small
  status label. Avoid custom pills when the platform has a control.
- Keep labels literal and descriptions to one line.
- Put actions in the row they affect, or in a toolbar/header. Do not add a
  dashboard CTA.
- Keep content dense but breathable: 13px body, 11.5px secondary, 10px section
  labels, 28–30px controls.

## macOS checklist

- Hidden title bar; traffic lights stay top-left, inset 14–16px.
- Sidebar uses translucency and a single hairline divider.
- 13px body text, semantic text colors, SF Pro, no custom display face.
- Controls are 28–34px high; hit targets at least 28px.
- Keyboard focus is always visible: 3px accent ring at 22–28% opacity.
- Respect Reduce Motion: remove pulse/scale, keep opacity fades.
- Dark mode is a real theme, not an inverted light theme.

## SwiftUI mapping (next pass)

- Replace `SettingsColor` + `Theme` + `OverlayPalette` with one `UITheme`.
- Expose the selected palette as `UITheme.Palette`; every component reads
  `theme.accent` / `theme.accentFill`. Remove the overlay's green accent.
- Build Settings panes with `Form` + `.formStyle(.grouped)` (or a shared
  `SettingsGroup` / `SettingsRow`), not custom card grids.
- Use `Toggle`, `Picker(.menu)`, `.buttonStyle(.bordered/.borderedProminent)`,
  and the system sidebar selection instead of bespoke controls.
- Move onboarding onto `SettingsCard`, `SettingsRow`, `SettingsIconTile`, and
  the shared button styles.
- Share type roles (`UITheme.TextStyle`) rather than scattered point sizes.
- Use the same 12/14px radii and hairline borders across all three surfaces.
