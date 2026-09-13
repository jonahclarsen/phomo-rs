# Fork CLI builds (jonahclarsen/phomo-rs)

This fork adds `.github/workflows/fork-binaries.yml`, which builds the `phomo` CLI for macOS and Windows.
Upstream's `ci.yml` (release-please, crates.io, npm, readme bot) is unchanged and is gated to `loiccoyle`.

## What CI does

- On `macos-14` and `windows-2022` it runs `cargo test --locked --release` for `phomo` (with `parallel,progress_bar`) and for `phomo-cli`.
- macOS: builds `aarch64-apple-darwin` and `x86_64-apple-darwin` with `MACOSX_DEPLOYMENT_TARGET=11.0`, then `lipo`s them into one universal `phomo`.
- Windows: builds `x86_64-pc-windows-msvc` with `+crt-static`, so no VC++ redistributable is needed.
- The shipped binaries render the CLI golden mosaics, and their pixels are compared with the files in `phomo-cli/tests/data`.
- `workflow_dispatch` with `notarize=true`:
  - signs the macOS binary with Developer ID, hardened runtime and a timestamp;
  - notarizes it with `notarytool`;
  - checks Apple's online ticket.
- The `package` job builds the `release-package` artifact: `phomo-cli_v<version>.zip` plus `SHA256SUMS.txt`. The ZIP holds `Mac/phomo`, `Windows/phomo.exe`, `LICENSE`, `README.md` and `completions/`.

## Commands

```sh
git push origin main                                  # unsigned build + tests
gh workflow run fork-binaries.yml -f notarize=true    # signed + notarized package
gh run list --workflow fork-binaries.yml -L 3 --json databaseId,headSha,status
gh run watch <id> --exit-status
gh run download <id> -n release-package
```

## Lessons

- Apple cannot staple a plain Mach-O executable or a ZIP. The notarization ticket lives only on Apple's servers, and Gatekeeper fetches it online on first launch.
  - Check a download with `codesign --verify --strict --check-notarization -R=notarized Mac/phomo`.
- `phomo-cli/tests/data/faces` is a git symlink. Windows checkouts turn it into a text file, so CI copies the directory first.
- Two upstream palette-matching golden tests fail the same way on macOS and Windows. The fork build skips only these two:
  - `color_match::tests::test_match_palette_with_real_images` (golden `phomo/tests/data/match/matched.png`). Upstream's own `ci.yml` at c3ecff1 also fails it on Linux, while the other 31 unit tests pass.
  - `build_mosaic_match_master_to_tiles` in `phomo/tests/mosaic.rs` (final mosaic vs `mosaic_16_16_match_master_to_tiles.png`). The other 8 mosaic tests pass.
  - The non-blocking `linux-parity` job runs upstream's full test command without skips, for comparison.
  - Don't regenerate the goldens here; that's an upstream decision.
- `read_images_from_dir*` loads tiles in `read_dir()` order, which differs between filesystems (ext4, APFS, NTFS).
  - Upstream's 8 exact-pixel CLI golden tests (`build_mosaic_cropped`, `_resized`, `_repeats`, `_greedy`, `_auction`, `_equalized`, `_transfer_*`) fail on macOS and Windows. Upstream's `ci.yml` never ran them ("cli tests don't run").
  - The fork skips those 8. `.github/scripts/smoke-render.sh` instead renders all 9 CLI modes with the shipped binaries, using upstream's mosaic-test tolerance (mean abs diff ≤ 2).
  - The package job prints macOS vs Windows render differences for information.
- `phomo-cli/build.rs` regenerates `phomo-cli/completions/` on every build.
- Secrets (`SIGNING_CERTIFICATE_P12`, `P12_PASSWORD`, `NOTARY_API_KEY_P8` as base64, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`) are repository Actions secrets. Signing only runs on `workflow_dispatch`, never for pull requests.
- The fork is public: never commit Adobe SDK or proprietary licensing files here. The CLI needs neither.
- Versions differ per crate (`phomo`, `phomo-cli`, `phomo-wasm`). The package uses the `phomo-cli` version.
- After `git push`, confirm the dispatch run's `headSha` before trusting it.
