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

- **Custom shortcut** as an action: record any key combination and assign it.
- **Per-app assignments** (a gesture does X in Keynote, Y elsewhere).
- **Two-hand rotate** (rotate images, scrub timelines).
- **Snap-to-target** in pointer mode via the Accessibility API.

## Voice

- **SpeechAnalyzer** (macOS 26+) instead of `SFSpeechRecognizer`: newer on-device model,
  likely better at the name and at short commands.
- **Own wake-word model** so the recogniser only runs after "hey Sleight" (less power).
- **Voice + hand:** point at something and say "click", "open this", "close that".
- **Custom phrases** per action, and spoken custom shortcuts (Apple Shortcuts already work).
- **On-screen words:** "click Submit" via the Accessibility tree of the front window
  (buttons and links), the reliable cousin of screen OCR.
- Skip listening while a call app (Zoom, Meet, FaceTime) has the mic.

## Speed

- **Region-of-interest Vision** around the tracked hand.
- **Continuity Camera at 60 fps** as the recommended setup; detect and suggest it.
- **Idle power:** drop to 15 fps after 10 s without a hand.

## Keyboard

- Swipe typing, word suggestions, emoji layer, auto-show on text-field focus.

## Product

- Launch at login, onboarding with a live calibration (measures your pinch and flick).
- Notarized build + updates, license, contribution guide.
