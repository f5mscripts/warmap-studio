# WarMap Studio

**Historical War Map Creator** — a private iOS app for making the animated
historical war-map videos that do well on TikTok and YouTube Shorts.

Pick a map and a period, define countries and factions, script or simulate a war,
watch borders creep and frontlines move, and export straight to 1080 × 1920.

This is a personal, sideloaded app. It is not on the App Store, has no accounts, no
analytics, no advertising and no tracking, and works entirely offline.

---

## What it does

| | |
|---|---|
| **Map engine** | 184 territory units from Natural Earth at three levels of detail, Mercator and equirectangular projections, pan/zoom/rotate, and political borders that disappear where both sides share an owner |
| **Territory animation** | Advancing colour sweeps with a real compass bearing, so an invasion comes from the side it actually came from |
| **Pixel-art mode** | A retro-game style: the whole frame rendered into a ~200-pixel buffer on a 24-colour palette and blown up without smoothing, with sprite unit counters and battle markers |
| **Countries** | Empires, kingdoms, republics, colonies, puppets and occupied zones, with lifetimes — extinct polities vanish from the picker outside their own era |
| **Flags** | Drawn procedurally, resolved by date: Germany flies a different flag in 1914, 1925 and 1940 |
| **Timeline** | Eight tracks, draggable clips, a BC-capable date ruler, playback with speed control and looping |
| **Simulation** | Front-based attrition with morale, supply, multi-front penalties and capitulation, driven by a seeded generator so a war replays identically |
| **Units** | 31 formation types — riflemen to jet fighters, light tanks to carriers — drawn as pixel sprites with the owner's flag, offered only in the periods they existed, and placeable at sea if they fly or float |
| **Coalitions** | Pick every country on both sides by hand, watch each side's pooled strength as you build it, and let a per-war luck roll give the underdog a real chance — about one war in four |
| **Export** | H.264/HEVC MP4 at TikTok/Shorts 9:16, YouTube 16:9, square, or custom, with mixed audio |
| **Projects** | `.warmap` packages with autosave, undo/redo, duplication, import/export, and alternate-history branching |

Preset scenarios: **WW2 Europe** (the demo, seeded on first launch), **World War I**,
**Napoleonic Wars**, **Roman Expansion**, **Cold War**.

---

## Building it

### Requirements

* macOS with **Xcode 16.4** or newer
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
* An Apple Developer account to sign for a real device

### Local build

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open WarMapStudio.xcodeproj
```

`WarMapStudio.xcodeproj` is generated and **not** committed — `project.yml` is the
source of truth. Regenerate it after adding files.

Run the tests:

```bash
xcodebuild test -project WarMapStudio.xcodeproj -scheme WarMapStudio \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Regenerating the map data

The contents of `Resources/MapData/` are generated. To rebuild them:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install shapely pillow
python3 Tools/prepare_map_data.py     # fetches Natural Earth, writes the resources
python3 Tools/preview_reference.py    # renders PNG previews to Tools/out/ to eyeball
python3 Tools/make_app_icon.py        # regenerates the app icon
```

---

## Connecting the repo to Codemagic

1. Sign in at [codemagic.io](https://codemagic.io) with GitHub.
2. **Add application** → **GitHub** → pick `f5mscripts/warmap-studio`.
3. Choose **"I have a codemagic.yaml"** when asked how to configure it. The file at
   the repo root defines two workflows:
   * `ios-ci` — build and test, no credentials needed. Runs on every push.
   * `ios-release` — the signed IPA. Runs on tags.
4. Push a tag when you want an IPA:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```
5. The IPA appears under the build's **Artifacts**.

### Setting up signing

`ios-release` reads three values from a Codemagic **environment group** named
`warmap_signing`. Create it under **Settings → Environment variables**, mark every
variable **Secure**, and add it to the group `warmap_signing`.

Nothing below ever goes in the repository.

**1. Register the App ID.** In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list),
create an App ID with the bundle identifier `com.f5mscripts.warmapstudio`.

**2. Register your iPhone.** Devices → add your device's UDID (find it in Finder, or
in Xcode under Window → Devices and Simulators).

**3. Create a provisioning profile.** Profiles → **iOS App Development** (or **Ad
Hoc**), select the App ID, your certificate, and your device. Download the
`.mobileprovision`.

**4. Export your signing certificate.** In Keychain Access, find your *Apple
Development* (or *Apple Distribution*) certificate, right-click → **Export**, save
as `.p12`, and set a password.

**5. Base64-encode both files:**

```bash
base64 -i Certificates.p12 | pbcopy          # → CM_CERTIFICATE
base64 -i WarMap.mobileprovision | pbcopy    # → CM_PROVISIONING_PROFILE
```

**6. Add the three variables** to the `warmap_signing` group:

| Variable | Value | Secure |
|---|---|---|
| `CM_CERTIFICATE` | base64 of your `.p12` | ✅ |
| `CM_CERTIFICATE_PASSWORD` | the password you set in step 4 | ✅ |
| `CM_PROVISIONING_PROFILE` | base64 of your `.mobileprovision` | ✅ |

---

## Installing the IPA on your iPhone

Download the IPA from the Codemagic build, then use any of:

* **Apple Configurator** (free, Mac) — drag the IPA onto your connected device.
* **Xcode** → Window → Devices and Simulators → your device → **+** under Installed
  Apps → choose the IPA.
* **AltStore** / **Sideloadly** — if you are signing with a free Apple ID rather than
  a paid account.

Notes on signing lifetime:

* A **paid** Apple Developer account (£79/$99 a year) signs for **one year**, and
  supports up to 100 registered devices.
* A **free** Apple ID signs for **seven days**, after which the app must be
  re-signed. `ios-release` works with either; only the profile differs.

On first launch you may need **Settings → General → VPN & Device Management** and
trust your developer certificate.

---

## How it is put together

```
Sources/
  App/            entry point, routing, onboarding, settings, wizard, errors
  DesignSystem/   theme tokens and reusable controls
  Geo/            coordinates, projections, camera, clipping, polyline maths
  MapEngine/      map models, bundle loading, projected-space path cache
  History/        dates, eras, countries, procedural flags, preset scenarios
  Simulation/     armies, frontlines, battles, events, seeded war simulator
  Timeline/       tracks, clips, and the evaluator that turns time into a frame
  Animation/      easing, interpolation, text elements and their animations
  Rendering/      the shared Core Graphics scene renderer, plus the pixel-art pass
  Export/         presets, audio clips, the AVAssetWriter pipeline
  Project/        .warmap format, store, editor state, undo, autosave
  AI/             scenario generator protocol + offline implementation
  Editor/         map canvas, timeline UI, inspector, sheets
```

Three decisions shape everything else:

**Territory units are the atom of ownership.** The map is not images and not whole
countries; it is 184 polygons with stable ids, and world state is a dictionary from
unit to owner. Annexation, partition, collapse, independence and reunification are
all the same operation, which is why each of them is a few lines rather than a
special case.

**Rendering is one code path.** The live editor and the video exporter call the same
`MapSceneRenderer` with the same `WorldSnapshot`. The preview cannot drift from the
export because there is nothing to drift. The pixel style is the same path again, run
into a small offscreen buffer and blown up by a whole-number factor with
interpolation off — so it is real pixels rather than large rectangles, and the
preview is the export at a different size.

**Evaluation is pure.** A frame is a function of `(timeline, time)` — a replay from
the initial state, not incremental mutation. Scrubbing backwards produces exactly
the frame playing forwards would, and the exporter can jump straight to any time.
Simulation randomness comes from a seeded SplitMix64, never the system generator, so
a saved project always replays the same war.

---

## Known limitations

These are real, and stated here rather than buried:

* **Historical borders are approximations.** They are ownership overlays on Natural
  Earth's modern geometry, plus hand-authored cut lines for the cases that matter
  (the 1939 partition of Poland, the Vichy demarcation, Kaliningrad, Karelia,
  northern Transylvania, Crimea). Good enough for the video style; not a historical
  GIS. GeoJSON import exists for when you want exact borders.
* **Flags are vector approximations.** Intricate coats of arms render as their
  background fields. Per-country, per-period image import is supported for anything
  the vocabulary cannot express.
* **The simulator is plausible, not predictive.** It resolves fronts from strengths
  and luck. Historical Mode exists precisely so a scenario can replay recorded events
  instead of pretending a simulation reconstructs history.
* **Long exports take time.** A 42-second 1080 × 1920 project at 30 fps is 1,260
  rendered frames. Keep the app foregrounded.

## Licence and data

Application source: see `LICENSE`. Bundled data provenance and obligations:
see `DATA_LICENSES.md`. Short version — the map is public-domain Natural Earth, the
flags are drawn rather than copied, and no audio ships with the app.
