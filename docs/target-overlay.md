# Target Volume Overlay

The target volume overlay is a fixed-size, noninteractive native macOS HUD.
It reflects only the `MediaTargetPresentationState` that has already passed
through the app's route and target-session guards; it never reads device state,
stores identifiers, or sends commands itself.

## Placement Ladder

`MediaControlCore` resolves a screen without AppKit. The app converts the
resolved descriptor into a borderless panel frame centered near the bottom of
that screen's visible frame. The resolver uses this order:

1. A unique route-display stable identifier match.
2. A unique route-display name match when the route has no stable identifier.
3. The only live screen.
4. The screen containing the pointer.
5. The main screen.
6. The first live screen.

No live screen, a hidden/suspended/route-lost presentation state, or a missing
activation rule orders the panel out.

## Visual State Matrix

- **`pendingCold`:** Speaker glyph, empty level track, and `Adjusting volume`.
- **`pendingBaseline`:** Speaker glyph, last confirmed level held and
  de-emphasized, and `Adjusting volume`.
- **`confirmed`:** Speaker glyph, confirmed level, and a locale-formatted
  percentage.
- **`rail`:** Speaker glyph, retained endpoint level, and a locale-formatted
  percentage.
- **`muted`:** `speaker.slash.fill`, retained level desaturated, and `Muted`.
- **`failed` with a value:** Warning glyph, last value held as frozen, and
  `Unavailable`.
- **`failed` without a value:** Warning glyph, empty track, and `Unavailable`.
- **`hidden`, `suspended`, `routeLost`:** Panel remains ordered out.

The visual mapper bounds a defensive normalized level to `0...1` before it
reaches the track or percentage formatter. It owns no animation; pending state
uses a static presentation so Reduce Motion needs no alternate spinner.

## Accessibility

The overlay and its hosting view are excluded from the accessibility tree.
`RelayAppModel` remains the single owner of throttled VoiceOver announcements,
so the visible HUD cannot duplicate them.

The panel observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
while it exists. Reduce Transparency chooses an opaque
`windowBackgroundColor` surface before any OS-version material selection.
Otherwise, macOS 26 and later use SwiftUI's public glass effect and macOS
15–25 use regular material. Increase Contrast strengthens the panel and track
borders, increases caption/track contrast through system colors, and removes
the panel shadow live. All colors are system colors.

## Tuning Constants

- `TargetOverlayMetrics.panelSize`: `224 × 76` points.
- `TargetOverlayMetrics.nativeHUDBottomInset`: `124` points from the visible
  frame bottom. This is intentionally named for future #38/#41 device-HUD
  tuning.
- `TargetOverlayMetrics.cornerRadius`: `18` points.
- `TargetOverlayMetrics.horizontalPadding`: `16` points.
- `TargetOverlayMetrics.verticalPadding`: `14` points.
- `TargetOverlayMetrics.trackHeight`: `6` points.

## Manual #41 Qualification Checklist

- Verify placement on the matched display, then each placement fallback, with
  different display scaling and menu-bar/dock positions.
- Verify the fixed `224 × 76` point HUD stays inside the target visible frame
  in full screen, across Spaces, and on a secondary display.
- Exercise every state in the matrix, including muted at minimum volume, a
  pending request with a retained baseline, and a failure both with and without
  a retained value.
- With VoiceOver enabled, confirm only the app-model announcement is spoken;
  navigating the accessibility tree must not expose the overlay.
- Toggle Reduce Transparency and Increase Contrast while the HUD is visible;
  confirm the surface, borders, track/caption contrast, and shadow update
  without a new command.
- Toggle Reduce Motion and confirm that no spinning or authored motion appears.
- Confirm the HUD cannot take focus, receive pointer events, enter the Windows
  menu, move, or interrupt the active app.
