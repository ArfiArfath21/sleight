# Roadmap

## Next (needs your hands)

- **Tune from real recordings.** Record sessions (`--record 20`, or Preview → Record) of
  each gesture plus "normal life" (typing, talking with hands, drinking coffee) and add
  them as replay tests. Thresholds come from anatomy and synthetic hands so far.
- **Confirm Spaces switching** works with the synthetic ⌃←/⌃→ on your setup (it needs
  the default Mission Control shortcuts enabled).

## Gestures

- **Per-app profiles:** flick = next slide in Keynote, seek in video players, next tab
  in browsers.
- **Next / previous track** (media keys are already wired in the output layer).
- **Custom bindings** in Settings: map any gesture to any shortcut.
- **Two-hand rotate** (rotate images, scrub timelines).
- **Snap-to-target** in pointer mode via the Accessibility API.

## Speed

- **Region-of-interest Vision** around the tracked hand.
- **Continuity Camera at 60 fps** as the recommended setup; detect and suggest it.
- **Idle power:** drop to 15 fps after 10 s without a hand.

## Keyboard

- Swipe typing, word suggestions, emoji layer, auto-show on text-field focus.

## Product

- Launch at login, onboarding with a live calibration (measures your pinch and flick).
- Notarized build + updates, license, contribution guide.
