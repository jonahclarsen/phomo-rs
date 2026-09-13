#!/usr/bin/env bash
# Combine the CI-built macOS universal and Windows x64 phomo CLI into one ZIP.
# Usage: package-release.sh <cli-version> [require-notarized]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$1"
require_notarized="${2:-false}"
stage="build/package/phomo-cli_v${version}"
rm -rf build/package release-dist
mkdir -p "$stage/Mac" "$stage/Windows" release-dist
ditto -xk dist/phomo-macos.zip "$stage/Mac"
ditto -xk dist/phomo-windows.zip "$stage/Windows"
cp LICENSE README.md "$stage/"
cp -R phomo-cli/completions "$stage/completions"
test -x "$stage/Mac/phomo"
test -f "$stage/Windows/phomo.exe"
xcrun lipo "$stage/Mac/phomo" -verify_arch arm64 x86_64
"$stage/Mac/phomo" --version | grep -Fx "phomo-cli $version"
if [[ "$require_notarized" == true ]]; then
    codesign --verify --strict --check-notarization -R='notarized' --verbose=2 "$stage/Mac/phomo"
    codesign -dv "$stage/Mac/phomo" 2>&1 | grep -F 'Authority=Developer ID Application: Gabgren 2000 Inc. (9TJ9D565BJ)'
fi
archive="release-dist/phomo-cli_v${version}.zip"
ditto -c -k --keepParent "$stage" "$archive"
python3 - "$archive" "$version" <<'PY'
import sys, zipfile, hashlib, pathlib
archive, version = pathlib.Path(sys.argv[1]), sys.argv[2]
root = f'phomo-cli_v{version}/'
with zipfile.ZipFile(archive) as z:
    names = set(z.namelist())
    for required in ('Mac/phomo', 'Windows/phomo.exe', 'LICENSE', 'README.md', 'completions/_phomo'):
        assert root + required in names, required
    assert all(n.startswith(root) for n in names), names
    mode = z.getinfo(root + 'Mac/phomo').external_attr >> 16
    assert mode & 0o111, 'macOS binary lost its executable bit'
    assert z.read(root + 'LICENSE') == pathlib.Path('LICENSE').read_bytes()
pathlib.Path('release-dist/SHA256SUMS.txt').write_text(
    hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
print('Verified combined package layout:', archive)
PY
