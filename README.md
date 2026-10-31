<p align="center"><img src="docs/images/wordmark.png" width="460" alt="Sleight"></p>

<p align="center"><b>Gestures that land.</b><br>
Camera hand gestures for macOS: a handful of easy gestures, both hands, no aiming.</p>

---

Sleight watches your hands through the Mac's camera and turns a few natural motions
into the things you do all day: scroll, go back, switch desktops and apps, control
music, show the desktop, take a screenshot. Gestures depend on **what your hand is doing, not where it is**, so you
can raise a hand anywhere in view and flick. When you do need to aim, point and hold to
get a cursor, then make a fist to put it away.

It is a native Swift menu bar app. Apple's Vision hand-pose model runs on the Neural
Engine (~8 ms per frame), events go straight to the window server, and no frame ever
leaves the Mac.

## Gestures

<p align="center"><img src="docs/images/guide.png" width="520" alt="Gesture guide"></p>

The design rules:

- **Grouped by what you're doing.** Reading is ✌️ (scroll, back/forward). Windows are the
  whole hand: ✋ swipes desktops, ✊ grabs the app switcher. Media is 👌, used like a
  remote: tap to play/pause, hold and slide for volume or tracks. No family mixes two jobs.
- **Trackpad muscle memory.** Two fingers scroll and go back/forward; a whole hand
  switches desktops; content follows your hand, with natural scrolling.
- **Flicks, not positions.** A scroll is a flick with momentum, so flick again to go
  further. You never hold your hand at an exact spot.
- **Nothing destructive.** No gesture closes, quits or deletes anything.
- **Aiming is opt-in.** The pointer is a separate mode (☝️ hold), because aiming takes
  concentration and everyday gestures shouldn't.
- **Both hands, either hand.** Every one-hand gesture works with either hand. Both hands
  together are kept for big, rare actions: both hands up to rest/wake, part the
  curtains to show the desktop, frame with both hands for a screenshot.

### Rest and wake

Raise both open hands, palms to the screen and shoulder-width apart, as if saying "hold
on", and keep them still for a second: a ring fills, and Sleight **rests**. The camera
keeps watching, but nothing you do triggers anything except the same gesture, which
wakes it. `⌃⌥S` does the same; turning the camera fully off is a separate menu item.

A double clap can do it too (Settings, experimental, off by default): at the moment of
a clap the hands are edge-on and hide each other, so the camera alone misses many.

### Practice

**Menu → Practice Gestures…** opens a window with the live camera and your hand
skeleton, every gesture explained in plain words, and a counter that lights up each
time one is recognised. Nothing happens on your Mac while it's open. It also records
hand landmarks (positions only, no video) to `recordings/practice-*.jsonl`, so
thresholds can be tuned against real hands.

### Media without false triggers

The media "remote" is an **OK sign** 👌 (thumb and index tips touching, other three
fingers up) that **closes from open fingers**: a relaxed hand that merely looks pinched
never qualifies. Volume and track skip need the pinch held still for a beat first, and
a pinch made while the hand is moving is ignored.

### Always know what's about to happen

<p align="center"><img src="docs/images/chips.png" width="420" alt="Gesture chips"></p>

A small chip at the top of the screen shows what the hand in view will do *before*
you act ("Flick to scroll", "Media: let go = play/pause, ↕ volume, ↔ track"), and
flashes a confirmation when something fires. Turn the hints off in the menu once you
know them; the confirmations stay.

### Pointer mode

Hold ☝️ for half a second. The cursor follows your palm (not a fingertip, so pinching
doesn't move it). Pinch to click, pinch twice to double-click, pinch-hold-move to drag,
thumb + middle finger to right-click, ✌️ flick to scroll. Hold a fist to go back. A small
bar appears with big **Keyboard** and **Exit** buttons, and clicking into any text field
**brings the keyboard up by itself** (Sleight asks Accessibility what you clicked).

<p align="center"><img src="docs/images/keyboard.png" width="640" alt="On-screen keyboard"></p>

The keyboard is a full Mac layout with **⌘ ⌥ ⌃ ⇧**: tap a modifier for the next key,
double-tap to lock it, so shortcuts like ⌘C, ⌘⇧T or ⌥← work. It never takes
focus, so keys type into the app you were in. Keys are big hand-pointing targets and
highlight on hover.

| Hotkey | |
|---|---|
| `⌃⌥S` | Rest / wake (camera keeps watching) |
| `⌃⌥P` | Pointer mode on / off |
| `⌃⌥K` | On-screen keyboard |

## Install / build

Requires macOS 15+, Xcode (Swift 6), Apple silicon.

```bash
./scripts/build-app.sh          # builds, renders the icon, signs, installs ~/Applications/Sleight.app
open ~/Applications/Sleight.app
```

The first launch asks for **Camera** and **Accessibility** (to post scroll, key and
click events). The build signs with your Apple Development certificate when there is
one, so the grants survive rebuilds.

```bash
swift test                      # 76 engine tests, no camera needed
```

| Launch flag (`open -n ~/Applications/Sleight.app --args …`) | |
|---|---|
| `--bench 10` | Real camera pipeline for 10 s, no events posted; writes `benchmark.txt` |
| `--record 20` | Record 20 s of hand landmarks (no images) to `recordings/*.jsonl` |
| `--selftest` | Permissions, and that Sleight's own events aren't mistaken for yours |
| `--snapshots DIR` | Render the chips, keyboard, guide and logo to PNGs |

Data lives in `~/Library/Application Support/Sleight/`.

## Speed

Measured on an M4 Pro with the built-in camera, normal light (`--bench`):

| Stage | Cost |
|---|---|
| Camera (exposure + Apple's image pipeline, until the frame reaches the app) | ~72 ms, hardware |
| Vision hand pose, Neural Engine, 640×480 | **7.8 ms** mean, 12 ms p95 |
| Tracking + gesture engine | < 0.1 ms |
| Event posting (own high-priority queue) | < 1 ms |

The software part is ~9 ms. What Sleight does to protect it: 640×480 instead of 1080p
(Vision went from 17.6 to 7.8 ms), frame rate **pinned** at 30 so low light can't halve
it, late frames dropped rather than queued, flicks detected mid-motion (the action
fires while your hand is still moving), and 120 Hz output smoothing between 30 fps
frames. An iPhone via Continuity Camera (60 fps, pick it in the menu) cuts the camera
term.

## What makes it practical

| Problem | What Sleight does |
|---|---|
| Hand **entering the frame** looks like a swipe | Motion only counts if the hand was already in view and settled. |
| **Return stroke** after a flick (hand coming back) | The opposite direction is locked out for 0.6 s; one long motion is one flick. |
| **Hands resting on the keyboard** | The bottom of the frame is ignored, and any real key or trackpad input pauses everything for 1 s. |
| **Talking with your hands** | Slow or wandering motion never fires; flicks need speed, distance and one dominant axis. |
| **Shape flicker** between frames | A new shape must persist before it counts; pinch closes instantly but opens with hysteresis. |
| **⌘ stuck down** in the app switcher | Losing the hand or touching the keyboard mid-switch cancels it cleanly. |
| **Accidental media** | OK sign required, closed from open fingers, held still before sliding. |
| **Flicks near the bottom of the frame** | A flick that starts in view is followed even when it carries the hand into the ignored keyboard zone. |
| **Wrist-snap flicks** | Flicks are measured between the palm and the fingertips, so a snap of the wrist counts. |
| **HUD in your screenshot** | Sleight's own overlay is excluded from screen capture and sharing. |
| **Ghost hands** in dark rooms | Low-confidence detections are rejected (a real dark-room recording is a regression test). |
| **Background people** | Tiny hands are ignored; the hand doing a gesture keeps it even if another appears. |
| **macOS camera effects** | Gesture reactions (✌️ = balloons) and Center Stage are disabled for Sleight's camera. |
| **Distance from the camera** | Everything is measured in hand-lengths. |
| Pointer-mode precision | Palm anchor + One Euro filter + acceleration + precision mode + click rewind + drag deadzone. |
| Lost tracking in pointer mode | Short dropouts bridged; longer ones release held buttons, then exit. |

## Architecture

```
Sources/
  SleightCore/        pure logic, unit tested
    HandPose            per-frame features and the five shapes
    HandTracks          up to two hands across frames: filtering, debounced shape and pinch
    Flick               deliberate-flick detector (settle, dominance, return-stroke lockout)
    CommandEngine       everyday one-hand gestures
    TwoHandGestures     hands up (rest/wake), curtains, frame, double clap
    PointerEngine       pointer mode
    SleightEngine       active/resting, mode switching, real-input override
  Sleight/            the app: camera, Vision, output (glide, momentum, media keys, ⌘-Tab),
                      input monitor, overlay chip + ring + intro, mode bar, keyboard,
                      menu bar, settings, guide, preview & tuning
  SleightBrand/       the logo, drawn in code
Tests/SleightCoreTests  76 tests, including a real dark-room replay
```

## The name and the mark

*Sleight*, as in sleight of hand: quick, deft, a little bit of magic. The mark is a faint
ring (the camera's view, the stage), one pen stroke sweeping around it, and the gold
point where the motion lands: the moment a gesture becomes an action. Ivory and gold on
ink. When Sleight turns on, the stroke sweeps around the ring and lands on the point.

See [ROADMAP.md](ROADMAP.md).
