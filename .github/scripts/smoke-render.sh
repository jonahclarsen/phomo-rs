#!/usr/bin/env bash
# Render every CLI golden mode with a shipped phomo binary and compare against phomo-cli/tests/data.
# Uses upstream's mosaic-test tolerance (mean abs diff <= 2) because tile order follows read_dir(),
# which differs between filesystems. Reports all modes before failing.
# Usage: smoke-render.sh "<phomo command>" <output dir>
set -uo pipefail
cd "$(dirname "$0")/../.."
read -r -a exe <<< "$1"
out="$2"
data=phomo-cli/tests/data
tolerance=2
mkdir -p "$out"
modes=(
  "mosaic_cropped_tiles|--crop-tiles"
  "mosaic_resized_tiles|--resize-tiles"
  "mosaic_repeats|--resize-tiles --n-appearances=2"
  "mosaic_greedy|--resize-tiles --solver=greedy"
  "mosaic_auction|--resize-tiles --solver=auction"
  "mosaic_equalized|--resize-tiles --equalize"
  "mosaic_transfer_tiles_to_master|--resize-tiles --transfer-tiles-to-master"
  "mosaic_transfer_master_to_tiles|--resize-tiles --transfer-master-to-tiles"
  "mosaic_10_10|-g 10,10 --resize-tiles"
)
failures=0
for mode in "${modes[@]}"; do
  golden="${mode%%|*}"
  read -r -a flags <<< "${mode#*|}"
  if ! "${exe[@]}" "$data/master.png" "$data/faces" "$out/$golden.png" "${flags[@]}"; then
    echo "FAIL render $golden"; failures=$((failures + 1)); continue
  fi
  python3 .github/scripts/png-rgb-equal.py "$out/$golden.png" "$data/$golden.png" --tolerance "$tolerance" \
    || failures=$((failures + 1))
done
echo "$failures of ${#modes[@]} modes failed"
exit $((failures > 0))
