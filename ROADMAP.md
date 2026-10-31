# Roadmap

## Next (needs a real hand in front of the camera)

- **Tune defaults from real recordings.** Record a few 20 s sessions (pointing, clicking,
  dragging, scrolling, swipes, typing with hands in view, talking with hands) and add
  them as replay tests next to `dark-room-ghosts.jsonl`. The thresholds were derived from
  hand anatomy and synthetic hands, not yet from your hand.
- **Measure latency in normal light** (`--bench 10`). Tonight's measurement was in a dark
  room, where camera delivery is at its slowest.
- **Verify palm-orientation sign and chirality** on real hands in the preview window.
  Flip detection self-calibrates, but the preferred-hand filter trusts Vision's chirality.

## Speed

- **Region-of-interest tracking:** once a hand is locked, run Vision on a crop around it
  and fall back to the full frame when it is lost. Should cut Vision time further.
- **Continuity Camera at 60 fps** as a recommended setup; detect and suggest it.
- **Short-horizon prediction** (~15 ms) on the pointer to hide part of the camera delay,
  gated on smooth motion so it never overshoots on stops.
- **Idle power:** drop to 15 fps after 10 s with no hand; jump back to 30 on detection.

## Interaction

- **Snap to targets:** use the Accessibility API to pull the cursor gently toward the
  nearest button/link when in precision mode.
- **Per-app gesture maps** (e.g. flick = next slide in Keynote, pinch-rotate = volume).
- **Media gestures:** thumbs-up = play/pause, two-finger twist = volume.
- **Two-hand gestures:** pinch-zoom with both hands.
- **Dwell click** as an accessibility option for people who can't pinch.
- **Keyboard:** swipe typing (trace through letters), word suggestions, emoji layer,
  auto-show when a text field gets focus.

## Product

- Launch at login, onboarding flow with a live "try it" calibration (measures your
  pinch distance and sets thresholds per user).
- Settings sync of per-user calibration.
- Notarized build + Sparkle updates.
- License and contribution guide before going public.
