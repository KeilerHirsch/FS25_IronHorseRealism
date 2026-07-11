#!/usr/bin/env bash
#
# Build the shippable FS25 mod zip.
# modDesc.xml MUST sit at the ROOT of the zip (FS25 requirement). We zip the
# individual mod files, never the containing folder.
#
set -euo pipefail
cd "$(dirname "$0")"

OUT="FS25_IronHorseRealism.zip"
rm -f "$OUT"

zip -r "$OUT" \
    modDesc.xml \
    scripts/ \
    icon_ironHorseRealism.dds \
    LICENSE \
    -x "*/.*"

echo
echo "Built $OUT:"
unzip -l "$OUT"
