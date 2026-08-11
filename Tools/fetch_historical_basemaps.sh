#!/usr/bin/env bash
#
# Fetches aourednik/historical-basemaps for LOCAL use.
#
# This dataset is GPL-3.0. It is deliberately NOT bundled with WarMap Studio, and
# nothing this script downloads should be committed to this repository — see
# DATA_LICENSES.md. Import the year files you want through the app's GeoJSON import
# if you need more precise historical borders than the built-in era overlays give.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/.cache/historical-basemaps"

if [ -d "$TARGET/.git" ]; then
  echo "Updating $TARGET …"
  git -C "$TARGET" pull --ff-only
else
  echo "Cloning historical-basemaps into $TARGET …"
  mkdir -p "$(dirname "$TARGET")"
  git clone --depth 1 https://github.com/aourednik/historical-basemaps.git "$TARGET"
fi

echo
echo "Done. GeoJSON year files are in:"
echo "  $TARGET/geojson"
echo
echo "Reminder: this data is GPL-3.0. Keep it out of the repository, and honour the"
echo "licence if you redistribute anything derived from it."
