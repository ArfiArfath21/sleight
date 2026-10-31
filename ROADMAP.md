# Roadmap

## Next (needs your hands)

- **Tune from real recordings.** Record sessions (`--record 20`, or Preview → Record) of
  each gesture plus "normal life" (typing, talking with hands, drinking coffee) and add
  them as replay tests. Thresholds come from anatomy and synthetic hands so far.
- **Confirm Spaces switching and Show Desktop** work with the synthetic ⌃←/⌃→ and F11
  on your setup (they need the default Mission Control shortcuts enabled).
- **Clap detection on real hands.** Claps are fast and hands hide each other, so this is
  the gesture most likely to need tuning. If it's flaky, confirm claps with the
  microphone (the sound is a sharp transient), opt-in.

## Gestures

- **Per-app profiles:** flick = next slide in Keynote, seek in video players, next tab
  in browsers.
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
