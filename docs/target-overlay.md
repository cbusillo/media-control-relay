# Target Volume Overlay

The target volume overlay is a fixed-size, noninteractive native macOS HUD.
It reflects only the `MediaTargetPresentationState` that has already passed
through the app's route and target-session guards; it never reads device state,
stores identifiers, or sends commands itself.

## Placement Ladder

`MediaControlCore` resolves a screen without AppKit. The app converts the
resolved descriptor into a borderless panel frame anchored near the top-right
of that screen's visible frame. The resolver uses this order:

1. A unique route-display stable identifier match.
2. A unique route-display name match when the route has no stable identifier.
3. The only live screen.
4. The screen containing the pointer.
5. The main screen.
6. The first live screen.

Audio-only activation rules skip route-display matching and start at the
fallback ladder, because display identity is not part of their activation
contract.

No live screen, a hidden/suspended/route-lost presentation state, or a missing
activation rule orders the panel out.

The panel uses the visible frame for both axes, so menu bars and Docks reduce
the usable bounds before placement. Geometry remains contained for negative
screen origins, fractional backing scales, invalid insets, and panels larger
than the visible frame.

## Visual State Matrix

The visible HUD uses a native-style two-row Liquid Glass capsule. The current
audio output name occupies the native widget's title position. It is rendered
only in the local transient HUD and is never added to diagnostics or public
evidence. A lower row brackets the level track with compact minimum- and
maximum-volume speaker glyphs and adds the native 17-mark scale beneath the
knobless track; mute and failure replace only the leading glyph so the layout
remains stable.

- **`pendingCold`:** Output title, speaker glyph, and empty level track.
- **`pendingBaseline`:** Output title, speaker glyph, and last confirmed level
  held and de-emphasized.
- **`confirmed`:** Output title, speaker glyph, and confirmed level.
- **`rail`:** Output title, speaker glyph, and retained endpoint level.
- **`muted`:** Output title, `speaker.slash.fill`, and retained level
  desaturated.
- **`failed` with a value:** Output title, warning glyph, and last value held as
  frozen.
- **`failed` without a value:** Output title, warning glyph, and empty track.
- **`hidden`, `suspended`, `routeLost`:** Panel remains ordered out.

The visual mapper bounds a defensive normalized level to `0...1` before it
reaches the track or speaker-glyph selection. It owns no animation; pending
state uses a static presentation so Reduce Motion needs no alternate spinner.

## Accessibility

The overlay and its hosting view are excluded from the accessibility tree.
The app does not post unsolicited VoiceOver announcements from the HUD. A
background-only, nonactivating app has no focused accessibility context that can
reliably own those announcements without moving the VoiceOver cursor or
activating the app. Instead, `RelayAppModel` publishes the latest confirmed
target status to the accessible menu-bar item and menu window, where VoiceOver
users can inspect it and use explicit volume controls whenever the configured
target is active. Disabled controls explain that active-target requirement.
The menu-bar actions carry explicit accessibility labels, and the setup and
Settings surfaces expose explicit heading and action descriptions so macOS does
not have to infer them from SwiftUI link or form-button presentation.

The panel observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
while it exists. Reduce Transparency chooses an opaque
`windowBackgroundColor` surface before any OS-version material selection.
Otherwise, macOS 26 and later use AppKit's public `NSGlassEffectView` with
regular style, no tint, a `20`-point corner radius, and noninteractive behavior
on macOS 27. The SwiftUI host is assigned through the glass view's supported
`contentView` property. macOS 15–25 use regular material in the same visual
bounds. Increase Contrast strengthens the panel and track borders and increases
title/glyph/track/tick contrast through system colors. The `NSPanel` shadow is
always disabled because its hard contour obscures the native glass edge; an
8-point transparent window margin leaves room for the system material to render
without clipping. All colors are system colors.

## Tuning Constants

- `TargetOverlayMetrics.panelSize`: `294 × 64` points.
- `TargetOverlayMetrics.surfaceMargin`: `8` transparent points around the
  visual HUD; the backing window is `310 × 80` points.
- `TargetOverlayMetrics.nativeHUDTopInset`: `10` points from the visible frame
  top.
- `TargetOverlayMetrics.nativeHUDTrailingInset`: `16` points from the visible
  frame trailing edge.
- `TargetOverlayMetrics.cornerRadius`: `20` points.
- `TargetOverlayMetrics.horizontalPadding`: `16` points.
- `TargetOverlayMetrics.topPadding`: `10.5` points.
- `TargetOverlayMetrics.rowSpacing`: `9` points.
- `TargetOverlayMetrics.trackRowSpacing`: `8` points.
- `TargetOverlayMetrics.captionPointSize`: `13` points.
- `TargetOverlayMetrics.glyphPointSize`: `12` points.
- `TargetOverlayMetrics.trackHeight`: `4` points.
- `TargetOverlayMetrics.tickTopGap`: `3` points.
- `TargetOverlayMetrics.tickDiameter`: `2` points.
- `TargetOverlayMetrics.tickEndInset`: `4` points.
- `TargetOverlayMetrics.nativeHUDTickCount`: `17` marks.

## Manual #41 Qualification Checklist

- Verify top-right placement on the matched display, then each placement
  fallback, with different display scaling and menu-bar/Dock positions.
- Verify the fixed `294 × 64` point HUD stays inside the target visible frame
  in full screen, across Spaces, and on a secondary display.
- Exercise every state in the matrix, including muted at minimum volume, a
  pending request with a retained baseline, and a failure both with and without
  a retained value.
- Confirm the visible title matches the current audio output, and keep any
  screenshot containing that title local or redact it before public evidence.
- With VoiceOver enabled, confirm the overlay remains absent from the
  accessibility tree, never moves the VoiceOver cursor, and never activates the
  app. Confirm the menu-bar item exposes the latest confirmed target status and
  the menu window's Volume Down, Mute, and Volume Up controls operate the target
  while the relay is active. In inactive states, confirm the controls are
  disabled and explain that an active configured target is required.
- Toggle Reduce Transparency and Increase Contrast while the HUD is visible;
  confirm the surface, borders, and track/title contrast update without a new
  command and no hard window-shadow contour appears.
- Toggle Reduce Motion and confirm that no spinning or authored motion appears.
- Confirm the HUD cannot take focus, receive pointer events, enter the Windows
  menu, move, or interrupt the active app.
