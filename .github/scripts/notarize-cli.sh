#!/usr/bin/env bash
# Developer ID sign + notarize a bare macOS command line executable.
# Apple cannot staple a ticket to a plain Mach-O (or to a ZIP), so the ticket
# lives only on Apple's servers; Gatekeeper fetches it online on first launch.
set -euo pipefail
binary="$1"
: "${SIGNING_CERTIFICATE_P12:?Missing SIGNING_CERTIFICATE_P12}"
: "${P12_PASSWORD:?Missing P12_PASSWORD}"
: "${NOTARY_API_KEY_P8:?Missing NOTARY_API_KEY_P8}"
: "${NOTARY_KEY_ID:?Missing NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Missing NOTARY_ISSUER_ID}"
identity='Developer ID Application: Gabgren 2000 Inc. (9TJ9D565BJ)'
task_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/phomo-signing.XXXXXX")"
keychain="$task_dir/signing.keychain-db"
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$task_dir"
}
trap cleanup EXIT
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
printf '%s' "$SIGNING_CERTIFICATE_P12" | base64 --decode > "$task_dir/certificate.p12"
security import "$task_dir/certificate.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity" "$binary"
codesign --verify --strict --verbose=2 "$binary"
printf '%s' "$NOTARY_API_KEY_P8" | base64 --decode > "$task_dir/AuthKey.p8"
auth=(--key "$task_dir/AuthKey.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
ditto -c -k --keepParent "$binary" "$task_dir/submit.zip"
xcrun notarytool submit "$task_dir/submit.zip" "${auth[@]}" --wait --timeout 20m --output-format json > "$task_dir/result.json"
submission="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("id","")); print("Notarization:", r.get("status"), "submission:", r.get("id"), file=sys.stderr)' "$task_dir/result.json")"
xcrun notarytool log "$submission" "${auth[@]}" || true
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status") == "Accepted" else "Apple did not accept this build")' "$task_dir/result.json"
# No staple possible for a bare executable: confirm Apple's online ticket instead.
for attempt in 1 2 3 4 5 6; do
    if codesign --verify --strict --check-notarization -R='notarized' --verbose=2 "$binary"; then
        echo "Online notarization ticket confirmed"
        exit 0
    fi
    sleep 20
done
echo "Notarization ticket was not visible online" >&2
exit 1
