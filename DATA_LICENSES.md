# Data licences and attribution

WarMap Studio bundles only data that is unambiguously free to redistribute. This
file records what ships, where it came from, and what each licence requires.

## Bundled

### Natural Earth — `Resources/MapData/*.json`

* **Source:** [Natural Earth](https://www.naturalearthdata.com/), 1:110m cultural
  vectors (`ne_110m_admin_0_countries`, `ne_110m_populated_places`), retrieved via
  the [nvkelso/natural-earth-vector](https://github.com/nvkelso/natural-earth-vector)
  mirror.
* **Licence:** Public domain.
  > "All versions of Natural Earth raster and vector map data found on this website
  > are in the public domain. You may use the maps in any manner, including
  > modifying the content and design, electronic dissemination, and offset
  > printing. The primary authors, Tom Patterson and Nathaniel Vaughn Kelso, and
  > all other contributors renounce all financial claim to the maps and invite you
  > to use them for personal, educational, and commercial purposes."
* **Attribution:** not required. Credited here and in the app's Settings screen
  anyway, because the project is better for saying where its map came from.
* **Modifications:** the files in `Resources/MapData/` are *derived* work, not
  copies. `Tools/prepare_map_data.py` simplifies the geometry at three levels of
  detail, cuts several countries into sub-units along explicit lon/lat lines,
  extracts shared borders, computes adjacency, and filters and augments the
  populated-places layer. Re-run that script to regenerate everything.

### Flags — drawn, not bundled

No flag images ship with this app. Flags are described as geometry
(`Sources/History/FlagSpec.swift`) and drawn at runtime with Core Graphics, which
avoids redistributing artwork of uncertain provenance entirely.

Two consequences worth knowing:

* Flags with intricate heraldry are approximations. The vocabulary covers fields,
  stripes, crosses, saltires, cantons, discs, crescents and simple stars; a detailed
  coat of arms is rendered as its background fields.
* The German national flag of 1935–1945 ships as its plain red/white/black fields
  with no central charge. If you need an exact reproduction for a historical video,
  import your own image against that country and date range — the app supports a
  per-country, per-period image override (`HistoricalFlag.importedAssetPath`).

### Fonts

System fonts only (`UIFont.systemFont`, plus the serif design variant). Nothing is
bundled or redistributed.

### Audio

**None.** WarMap Studio ships no music or sound effects. Every audio clip in a
project is a file you imported, copied into that project's `.warmap` package. You
are responsible for having the right to use whatever you import — bear in mind that
TikTok and YouTube will match copyrighted music regardless of what this app does.

## Deliberately *not* bundled

### historical-basemaps (aourednik)

[`aourednik/historical-basemaps`](https://github.com/aourednik/historical-basemaps)
is an excellent GeoJSON dataset of world borders from 2000 BC onwards, and it is the
obvious thing to want for a historical map app. It is licensed **GPL-3.0**.

That is a copyleft licence, and bundling it would carry obligations onto this
project as a whole. So it is not included. If you want it:

```bash
./Tools/fetch_historical_basemaps.sh
```

That clones the dataset into `Tools/.cache/` **for your own local use**. Import the
individual year files through the app's GeoJSON import if you want more precise
historical borders than the built-in era overlays provide. Do not commit the result
to this repository, and if you redistribute anything built from it, honour GPL-3.0.

## Accuracy

The bundled historical borders are **ownership overlays on modern geometry**, plus a
handful of hand-authored cut lines (the Bug line, the Vichy demarcation, Kaliningrad,
Karelia, northern Transylvania, Crimea). They are good enough for the animated
map-video style this app exists to make. They are not a historical GIS, and should
not be cited as one.

## Licence of this project

The application source is covered by `LICENSE`.
