# Next: pixel-art style + coalition war simulator

Requirements captured directly from the user. Everything below is decided — no
further clarification needed before building.

## 1. Pixel-art / retro game look  (new, biggest item)  — **DONE**

Built in `Sources/Rendering/{PixelPalette,PixelGrid,PixelSprite}.swift` plus the
pixel pass in `MapSceneRenderer`. `MapStyle.pixel` is in the picker, and Settings →
*Default map style* now actually applies to new projects (it previously did nothing),
so "always start in Pixel Art" holds. Preview it without a device with
`python3 Tools/preview_reference.py` → `Tools/out/04_pixel_sprites.png`,
`05_pixel_europe_1939.png`, `06_pixel_invasion.png`.

Section 4 built on this: widening `ArmyIcon` needed art in `PixelSprite.army(_:)`
and nothing else in the renderer.

The original brief follows, for reference.

The reference is TikTok war-map videos in a **pixelated game style**. This is a new
render mode, not a restyle of the existing one.

Add `MapStyle.pixel` and a matching `MapRenderStyle.preset(.pixel)`, plus a
render path in `MapSceneRenderer` that:

* Renders the map into an **offscreen low-resolution buffer** (target ~160–240 px
  on the short edge), then upscales to the output size with
  `CGContext.interpolationQuality = .none` so pixels stay hard-edged. This is the
  core of the effect — do not try to fake it by drawing large rectangles.
* **Snaps geometry to the low-res pixel grid** before filling, so territory edges
  land on pixel boundaries and coastlines look tiled rather than anti-aliased.
* Uses a **restricted palette** — pick ~24 saturated colours and quantise country
  colours to the nearest one, so sides read clearly at low resolution.
* Draws borders as **1–2 low-res pixels** of a dark outline colour.
* Replaces the Core Text label path with a **bitmap-style font**: either a small
  embedded 5×7 glyph atlas drawn as rects, or the system font rendered into the
  low-res buffer before upscale. The second is far less work and should be tried
  first.
* Battle markers and army counters become **pixel sprites** (small rect-based
  glyphs) rather than emoji and NATO boxes.

Keep the existing styles. `pixel` is an additional option in the style picker, and
should become the default for new projects if the user prefers it.

## 2. The other visual gaps (all confirmed)

* **Borders/fills too plain** — bolder saturated fills, thicker borders, and a
  brighter glow along the advancing edge during a capture. `contestedHighlight`
  already exists in `MapRenderStyle`; raise it and widen the leading edge.
* **Missing flags & country cards** — two things:
  * Flag badges drawn beside country labels on the map (`FlagRenderer` already
    draws these; wire it into `drawCountryLabels`).
  * A **"VS" card** before the war starts: both coalitions' flags, names and
    strength bars, held for ~2 s. New `TimelineAction` case, e.g.
    `.showVersusCard(sideA:sideB:)`.
* **Camera too static** — add a constant slow drift/zoom (Ken Burns) between
  keyframes rather than holding still. Simplest implementation: a per-project
  `ambientZoomRate`, applied in `TimelineEvaluator` on top of the interpolated
  camera so it also lands in the export.
* **Pacing / text style** — bigger titles, faster entries, punchier event captions.
  Tune `TextStyle.title` and the entry fractions in `TextAnimator.resolve`.

## 3. Coalition war simulator  (decided: manual picking)  — **DONE**

`SimulatorSheet` is now a two-coalition picker: a searchable country list with flags,
an A/B button per row, and a live pooled-strength bar per side. `WarSimulator` pools
each coalition (mean × `count^0.85`), passes a share of the pooled figure to whoever
is actually on the front (`coalitionSupport`, default 0.45), and draws a per-war
fortune once from the seed (`warFortune` × `randomness`, ±35% at the defaults).

Measured over 200 seeds of a coalition ~29% weaker: **23% upsets** with the fortune
roll, **0%** without it — the per-tick jitter really does average out, exactly as
this section predicted. `testAWeakerCoalitionWinsARespectableShareOfWars` asserts the
15–35% band.

The original brief follows, for reference.

Replace the current one-country-per-side `SimulatorSheet` with:

* **Manual selection of every country on both sides.** A searchable list with
  flags; tap to add to Side A or Side B. No auto-fill of allies — the user picks
  each one explicitly.
* A **live strength bar per coalition** that updates as countries are added, so
  the matchup is visible before simulating.
* Both sides become `Faction`s with several `memberCountryIDs`. `War.areEnemies`
  already handles this correctly; the engine change needed is in
  `WarSimulator.combatOdds` and `strongestAttacker`, which currently reason about
  single countries:
  * Combine each coalition's `CountryStrength` into a pooled figure, with
    **diminishing returns** on extra members (sum of `offensivePower`, then scale
    by `count^0.85`) so a 5-v-1 is strong but not five times strong.
  * A country fights with its own strength plus a **coalition support bonus**
    drawn from the pooled figure, so a small ally on the front still benefits from
    a large partner behind it.

### "Fair" means: the underdog can win sometimes  (decided)

Target roughly a **20–30% upset rate** for a moderately weaker coalition.

Implementation: keep outcomes driven by strength, but make `randomness` matter at
the *war* level rather than only per tick. Per-tick jitter averages out over
hundreds of ticks, which is why the current model is nearly deterministic even at
high randomness. Add a per-war **"fortune" roll** drawn once from the seed that
shifts both sides' effective strength by up to ±35%, so some seeds genuinely hand
the war to the weaker side.

**Add a test that runs the same matchup across ~200 seeds and asserts the upset
rate falls in 15–35%.** That is the only way to know this actually works rather
than hoping.

## Notes for whoever picks this up

* CI is green at `34e972b`; run `xcodegen generate --spec project.yml` then
  `xcodebuild test` (see README).
* The unsigned-IPA Codemagic workflow needs no credentials and is the one the user
  uses — eSign re-signs on install.
* The user could not be shown a preview; validate visual changes by extending
  `Tools/preview_reference.py`, which renders the pipeline to PNG without an
  iOS device. For the pixel style this is essential — it is much faster than
  waiting on CI to see whether the look is right.

## 4. Unit sprites: flags, soldiers, planes, tanks  (user request, Arabic)  — **DONE**

`ArmyIcon` now has 31 types across five categories, each with its own 12x12 sprite in
`PixelSprite.army(_:)`, its own `HistoricalInterval` (the picker filters by the
project's date, so no jets in 1914), and a speed that matches what it is. The owner's
flag is drawn beside every counter in both render paths. `MapCanvasView` now reports
open sea as `nil` instead of snapping to whichever country's bounding box covered the
water, so aircraft and ships can be placed at sea while ground units cannot.

The original nine raw values are untouched — renaming `infantry` to `rifleman` would
read better and would break every saved project.

The original brief follows, for reference.

> "لا تنسى تضيف اعلام وجنود و طائرات و جميع انواع الطائرات و الدبابات"
> — don't forget to add flags, soldiers, planes (all types of planes), and tanks.

Armies are currently drawn as a plain NATO-style rectangle with a three-letter
code (`MapSceneRenderer.drawArmy`). Replace that with **pixel sprites**, matching
the pixel-art style above.

* Extend `ArmyIcon` well beyond its current nine cases. Needed at minimum:
  * **Infantry**: rifleman, machine gun, paratrooper, marine, partisan, cavalry
  * **Armour**: light tank, medium tank, heavy tank, tank destroyer, armoured car
  * **Artillery**: field gun, howitzer, rocket artillery, anti-air
  * **Aircraft** (the user asked specifically for *all types*): fighter, bomber,
    dive bomber, heavy/strategic bomber, transport, reconnaissance, helicopter,
    jet fighter
  * **Naval**: destroyer, cruiser, battleship, carrier, submarine, transport ship
* Each icon needs a **pixel sprite** drawn as rectangles on the low-res grid —
  no bundled artwork, same reasoning as the flags (see `DATA_LICENSES.md`).
  Suggested shape: a `SpriteSpec` of `[(x, y, w, h, colorIndex)]` rects on a
  16×16 grid, tinted with the owning country's colour so sides stay readable.
* Sprites must be **era-aware**: a jet fighter must not appear in a 1914 project.
  Give each icon a `HistoricalInterval` and filter the army-type picker by the
  project's date, the same way `Country.flag(on:)` already resolves flags.
* Draw the owner's **flag badge** beside each unit counter, plus the existing
  strength bar underneath.
* Aircraft and naval units should be placeable over sea as well as land — the
  current tap handling only resolves land territories, so `MapCanvasView`'s hit
  test needs a sea fallback rather than snapping to the nearest country.

Keep `ArmyIcon.baseSpeed` meaningful per type (a jet is not a rifleman), since the
simulator already uses it.
