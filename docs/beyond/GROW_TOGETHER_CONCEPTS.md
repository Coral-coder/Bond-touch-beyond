# Grow Together: concept directions

**Status: an exploratory sketch. Nothing is built yet, and nothing in `Sources/` changes.**
Background research is in [COUPLE_PULSE_RESEARCH.md](COUPLE_PULSE_RESEARCH.md).

The idea is that every touch a couple exchanges quietly adds to something small and alive
that belongs to them. It should be gently cute but not cheesy. It should feel like a
keepsake, not a game.

---

## 0. Ground rules (from the research)

These rules apply to every direction below. They come straight from what reviewers praise
in Finch and Forest and what they resent in Widgetable, FurTwo and Paired.

1. **Nothing dies, withers, runs away or gets sad.** If nobody touches for a while, the
   living thing rests. Resting looks peaceful and complete, never neglected.
2. **No streaks, no counters of missed days, no "your partner hasn't…".** The app never
   shows which partner contributed less.
3. **No nagging notifications.** Growth never sends a push. The only pushes are the ones
   touches already send.
4. **No paywall, no currency, no ads.** Beyond is open source and free. Every visual
   variation is unlocked by *what you send*, not by what you pay.
5. **Growth shows what was said.** The colour and motion of each touch visibly shape the
   result. You are not filling an XP bar.
6. **A small living element, not a screen of its own.** It sits on the Home pair row or the
   partner card. Tapping it opens a calm detail view where you can inspect and replay touches.
7. **Private by construction.** There is no telemetry. Growth is computed on the device from
   touches the app already syncs, and at most a tiny settings record is shared through
   CloudKit. Nothing new goes to the original Bond backend.
8. **Reduce Motion and VoiceOver are first-class.** There is a still rendering and a spoken
   summary.

---

## 1. What a touch gives us to work with

Each touch already carries the following (see `Sources/Models/TouchMessage.swift`,
[BTM_TOUCH_FORMAT.md](../BTM_TOUCH_FORMAT.md), [DATA_MODEL.md](../DATA_MODEL.md)):

| Primitive | Detail | Growth signal we can derive |
|---|---|---|
| Position trace | Gen-3: one byte per 50 ms, up to 2 fingers, 9 positions (0–8), max 200 samples (10 s). Gen-2 / current Swift model: on/off ms list. | taps (finger-down runs), duration, **path shape** (position over time), net direction (start→end), reversals, two-finger moments |
| Gradient | `colorRGB` → `endColorRGB` | colour of each new leaf, scale or thread, blended along its length |
| Direction | sent by me / received from partner (`senderID`) | which partner's "side" or tint, *without* comparing amounts |
| Bond | one per partner (CloudKit zone or legacy `bondId`); multiple partners supported | one living thing per bond |
| Touch Language | `TouchMeaning` (label, emoji, pattern, gradient) | a recognisable named feature (a flower, a shell, a knot) |
| Heartbeat | latest bpm per partner | a gentle sway/breathing rhythm while a heartbeat is fresh |
| Encounters | per-bond "next time we meet" date | a seasonal moment: buds form as the date nears, bloom on the day |

Derived **touch features**, computed once per touch:

```
TouchFeatures {
  taps: Int              // finger-down runs (1 = single press)
  durationMs: Int        // samples * 50, or the sum of the on/off list
  startPos, endPos: Int  // 0..8 (gen-3 only, else nil)
  pathLength: Int        // Σ|Δposition|: 0 for a still press, large for a slide
  reversals: Int         // direction changes in the slide
  twoFinger: Bool        // any sample with two positions
  shape: [UInt8]         // resampled to 16 positions, the "gesture silhouette"
  start/end colour, sender, sentAt, meaningID?
}
```

---

## 2. Direction A: "Our Tree" (a small shared tree per bond)

**What grows:** a small tree, about bonsai size, that lives next to the two avatars. Every
touch adds to it. Trees suit touch well. They grow slowly and visibly, they never need
"feeding" in a guilt-inducing way, and their branching naturally records history. A slide
literally looks like a twig.

**How a touch shapes it:**

| Touch | Becomes |
|---|---|
| A single tap | one leaf |
| N taps | a small cluster of N leaves (capped at 5) |
| A slide | a new **twig whose curve follows the finger's path**. The 16-point silhouette maps position to bend angle over the twig's length, so an up-and-back slide makes an S-curve. |
| A long press | slightly thickens the branch it lands on (a little ring of growth) |
| Two fingers at once | a pair of leaves facing each other, or a blossom |
| Gradient | each leaf is tinted from start colour at its base to end colour at its tip. Twigs carry the same gradient along their length. |
| A Touch Language meaning | a small **flower** whose petal colours are the meaning's gradient. Tapping it shows the meaning's label and emoji. |

**Sent vs. received:** both feed the *same* tree. Leaves don't sort into "my side" and
"your side", so an imbalance never shows. The only hint of who sent what is a faint vein
line in that partner's profile colour, visible up close in the detail view. Branch
placement uses a seeded random choice, so the tree stays balanced regardless of who sends more.

**Showing it:** a 56–72 pt sapling sits between the two avatars in `pairRow`. When a touch
arrives, its new leaf unfurls over about 1 s. Tapping the tree opens a sheet with the full
tree: pinch to zoom, tap a leaf to see the touch replayed with `TouchViz` (when it was sent,
by whom, its meaning), and a "send it back" button.

**Gentle rules:**
- *Growth budget:* the first ~6 touches of a day each add a new element. After that,
  touches only add tiny details (dew, a slightly bigger leaf). This keeps the tree from
  ballooning and removes any reason to spam. It is not a limit anyone can "hit".
- *Seasons follow the real calendar and hemisphere,* not activity. Autumn leaves fall into
  a soft pile at the base (they are kept, not lost). Winter shows bare branches with a few
  evergreen meaning-flowers. Spring buds come from the touches you send.
- *Quiet periods* show the tree resting. When the first touch arrives after a long gap, it
  produces a new bud with no comment.
- *Encounters:* as the meeting date approaches, buds swell. On the day, the tree blooms
  once, and the petals are kept as a little "we met" ring around the pot.
- *Heartbeat:* while a partner's heartbeat is fresh (under a few minutes old), the tree
  sways at that bpm.

**Per partner:** one tree per bond, and both partners see the same tree (see §5). Settings
can show "Your grove", with all of a person's trees side by side.

**Risk:** "growing a tree together" is a well-worn image. That is why the gesture-driven
shapes matter. No two couples' trees look alike, because the trees are made of their actual
touches.

---

## 3. Direction B: "Tide Pool" (a little fish and the reef your touches build)

**What grows:** a round tide pool on the partner card with one small fish (or two). Each
touch leaves a piece of sea glass or a coral polyp, so the reef grows slowly. A fish suits
touch because **it can swim your touches**. When a slide arrives, the fish follows the
path the finger drew, which works as a cute, ambient replay of the gesture.

**How a touch shapes it:** taps drop pebbles of sea glass in the gradient's colours. A
slide makes a current, and the fish swims the trace (position becomes horizontal position,
time becomes distance travelled). Long presses grow coral branches. A Touch Language
meaning places a named shell, and tapping it plays the meaning.

**Sent vs. received:** received touches make the fish swim toward you (up toward the
screen). Sent touches make it swim away, toward the partner. The reef itself is shared.

**Gentle rules:** the fish has **no needs**. It is never hungry and never sick. When the
pool is quiet the fish sleeps among the coral. The tides follow the moon phase, not activity.

**Strengths and risks:** it is the most charming option and the most literal "replay".
But a creature invites pet expectations (feeding, petting, naming, moods), and the line
toward Widgetable-style care loops is easy to cross. It also costs more to animate and
needs more art direction.

---

## 4. Direction C: "Woven Thread" (a ribbon woven on nine threads)

**What grows:** a narrow woven ribbon. The bar's **9 positions map to 9 warp threads**.
Each touch weaves one band: the finger's position over time becomes the weft's path across
the threads, coloured by the touch's gradient. The ribbon grows longer with every touch. A
short recent stretch wraps around the avatar ring (`AvatarRing`) like a bracelet, which
echoes the hardware itself.

**Sent vs. received:** both weave into the same ribbon. Each partner's profile colour forms
one selvedge edge.

**Gentle rules:** a ribbon cannot fray or decay. It only gets longer. Encounters add a
little knot or bead. Meanings weave a repeating motif.

**Strengths and risks:** this is the most faithful to the data (it is lossless: the ribbon
*is* the touch history) and the least cheesy. It is also the cheapest to render. But it is
"crafty" rather than cute, and it reads less obviously as something *alive*.

---

## 5. Recommendation: Direction A, "Our Tree"

A tree is the most legible "we grow something" image. It never implies needs, and a slide
maps naturally onto a twig and a gradient onto a leaf. Its seasons give quiet periods and
encounters an honest, non-punishing shape. It is a **pure function of the touch history**,
so it needs almost no new sync surface and stays private. Two elements are worth borrowing:
B's idea of *replaying a touch through the living thing* (a leaf shimmers along the
gesture's path when tapped), and C's ribbon as the compact, Reduce-Motion fallback.

### 5.1 Determinism: derive it, don't sync it

The tree is never stored as a structure. It is regenerated from:

```
tree = TreeGenerator.grow(seed: hash(bond.id), events: ledger.sorted(by: (sentAt, touchID)))
```

Both phones hold the same touches in the shared CloudKit zone, so they grow **the same
tree**, with no merge conflicts and no tree data on any server. Generation is incremental:
a new event only adds nodes. Every random choice comes from a seeded PRNG keyed by
`(bondSeed, touchID)`, so a late-arriving touch reshapes only its own leaf.

Touches may be pruned from `history` over time, so each device keeps a compact **growth
ledger** (about 40 bytes per touch). That keeps a tree from years of touches intact.

### 5.2 Data model sketch

```swift
/// One entry per touch that has fed the tree. Derived from TouchMessage on arrival.
struct GrowthEvent: Codable, Hashable {
    let touchID: UUID
    let bondID: String
    let fromMe: Bool            // stored relative to this device; regenerated from senderID
    let sentAt: Date
    let startRGB: Int, endRGB: Int
    let taps: UInt8
    let durationMs: UInt16
    let pathLength: UInt8
    let reversals: UInt8
    let twoFinger: Bool
    let shape: [UInt8]          // 16-point silhouette, 0..8 (empty for gen-2 touches)
    let meaningID: UUID?
}

/// Per-bond settings shared by both partners (tiny; last-writer-wins per field).
struct GardenSettings: Codable, Equatable {
    var bondID: String
    var plantedAt: Date         // first touch, or when the feature was turned on
    var species: Species        // .maple, .cherry, .olive, .pine… (all free)
    var hemisphere: Hemisphere  // for seasons; defaults from locale/location if shared
    var showOnHome: Bool        // either partner can hide it on their own device too
}

/// Device-local only.
struct GardenLocalState: Codable {
    var lastSeenTouchID: UUID?  // new leaves since last look get a soft shimmer
    var enabled: Bool           // off switch, per device
}
```

**Where it lives:**

| Data | iCloud bond (CloudKit zone) | Legacy bond (original Bond backend) |
|---|---|---|
| Touches (source of truth) | existing `Touch` records in the shared zone | existing backend touch sync (unchanged) |
| `GrowthEvent` ledger | `LocalStore`, plus a backup in the user's **private** DB as monthly chunk records (`GrowthLedger-2026-10`, array field) | same: local plus a private CloudKit backup. **Nothing new is sent to `api.bond-touch.com`.** |
| `GardenSettings` | one new record type `Garden`, recordName `garden`, in the bond zone, so both partners see the same species | local only. The original app's partner has no tree, so only the Beyond user sees it. |
| `GardenLocalState` | `LocalStore` / `UserDefaults` | same |

There is no telemetry and no analytics event. The tree's existence is never reported anywhere.

### 5.3 Implementation outline (SwiftUI)

```
Sources/Grow/                       (new folder, later)
  TouchFeatures.swift               extract features from TouchMessage (gen-2 on/off and gen-3 samples)
  GrowthLedger.swift                @MainActor ObservableObject; appends on send/receive; persists; private-DB backup
  SeededRNG.swift                   SplitMix64 keyed by (bondSeed, touchID)
  TreeGenerator.swift               pure: (seed, [GrowthEvent], date) -> TreeModel
  TreeModel.swift                   nodes: branch segments (Bezier, width, gradient), leaves, flowers, fallen-leaf pile
  Seasons.swift                     date + hemisphere -> palette shift, leaf-fall fraction
  TreeCanvas.swift                  SwiftUI Canvas renderer; TimelineView(.animation) for sway only when visible
  GardenBadge.swift                 small 64 pt tree for HomeView.pairRow / partner card
  GardenDetailView.swift            sheet: zoomable tree, tap leaf -> TouchViz replay + "send back"
```

Integration points in the current code:

- **`AppModel`:** after a touch is sent (`CloudRelay.sendTouch` / legacy send) or received
  (CloudKit zone change / `TOUCH_SYNC`), call `growthLedger.record(touch, bond:)`.
  Recording is idempotent on `touchID`.
- **`HomeView.pairRow`:** insert `GardenBadge(bondID: model.selectedPartnerID)` between the
  avatars, then `.sheet` to `GardenDetailView`.
- **`TouchViz`:** reuse it in the leaf inspector. Optionally add a 2D trace mode for gen-3
  samples.
- **`CloudRelay`:** add `recordTypeGarden`, plus `saveGardenSettings` and
  `fetchGardenSettings` in the bond zone. Add `GrowthLedger` chunk upload and download in
  the private DB.
- **`EncountersView` / `LocalStore.nextMeeting`:** a read-only input to `Seasons` for the
  bud and bloom moment.
- **`HeartView` / heart-rate updates:** a read-only input for the sway rhythm (the bpm, and
  how fresh it is).
- **Settings:** a "Grow together" toggle (on by default after a one-time explainer), species
  picker, hemisphere, and "show on Home".

Rendering notes:

- Canvas plus cached `Path`s, rebuilt only when the ledger changes. Above about 300 leaves,
  merge older growth into a rasterised layer (`ImageRenderer`) and animate only the newest
  few.
- `@Environment(\.accessibilityReduceMotion)` turns sway off and swaps the leaf-unfurl
  animation for a fade.
- VoiceOver gives a summary, for example: "Your tree with Sam: 48 leaves, 3 flowers. Newest
  leaf yesterday from Sam, coral to violet." Each leaf is an accessibility element in the
  detail view.
- A WidgetKit widget can come later: render the tree snapshot with `ImageRenderer` into the
  app group and refresh it on touch arrival.

### 5.4 Phasing

1. **Prototype (Debug menu only):** `TouchFeatures` + `TreeGenerator` + `TreeCanvas`, fed
   from the existing `model.history`. Unit-test that generation is deterministic (same
   events in any arrival order give the same tree).
2. **Home badge + detail sheet:** add the ledger and local persistence.
3. **Meanings → flowers, Encounters → bloom, heartbeat sway, seasons.**
4. **Shared `Garden` settings record and private-DB ledger backup.**
5. **Widget.**

### 5.5 Open questions

- Should the tree be optional *per bond*? (Probably yes. Some bonds are family or friends.)
- If a bond is deleted, keep the tree as a read-only memory, or delete it with the bond?
  (Default: delete with the bond, with an "export as image" option first.)
- The current Swift `TouchMessage` stores gen-2 on/off timing, but gen-3 sends position
  samples ([BTM_TOUCH_FORMAT.md](../BTM_TOUCH_FORMAT.md)). Twig shapes need the gen-3
  samples kept on the model. Until then, slides render as straight twigs.
- Do we need art direction (a small set of hand-tuned leaf and species shapes) to stay "cute,
  not clip-art"? Probably a little.
