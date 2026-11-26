#!/usr/bin/env bash
# Run Apple's IPSW-derived inputs only on the ephemeral GitHub Actions runner.
# No IPSW, extracted firmware, or generated APFS image is uploaded as an artifact.
set -euo pipefail

: "${GITHUB_WORKSPACE:?run this script from GitHub Actions}"
WORK="$GITHUB_WORKSPACE/ci-results"
SRC="$RUNNER_TEMP/SLNeko-XNU"
mkdir -p "$WORK"
printf 'utc_started=%s\n' "$(date -u +%FT%TZ)" > "$WORK/metadata.txt"

git clone --no-checkout https://github.com/ShuiLan114514/SLNeko-XNU.git "$SRC"
git -C "$SRC" checkout --detach 13745bc916fa8f992b2468eb8db3595575abde6d
printf 'source_commit=%s\n' "$(git -C "$SRC" rev-parse HEAD)" >> "$WORK/metadata.txt"
PATCH="$GITHUB_WORKSPACE/ci/spaceman-v1.patch"
git -C "$SRC" apply --check "$PATCH"
git -C "$SRC" apply "$PATCH"
sha256sum "$PATCH" >> "$WORK/metadata.txt"

# Ubuntu 7zip packages expose different executable names; fetch.sh expects `7z`.
SEVEN_ZIP="$(command -v 7zz || command -v 7z || command -v 7zzs || true)"
if [[ -z "$SEVEN_ZIP" ]]; then
  echo 'No 7-Zip executable found after installing Ubuntu package 7zip.' >&2
  dpkg -L 7zip >&2 || true
  exit 1
fi
BIN="$RUNNER_TEMP/7z-compat"
mkdir -p "$BIN"
ln -sf "$SEVEN_ZIP" "$BIN/7z"
export PATH="$BIN:$PATH"

(
  cd "$SRC/ios165"
  bash ./fetch.sh
) 2>&1 | tee "$WORK/fetch.log"

(
  cd "$SRC/userland"
  # This job validates APFS layout/content; optional dynamic test binaries require Apple's iOS SDK.
  PREBUILT=1 SKIP_DYN=1 CHECK=1 SYSTEM=1 FLASHBOOT=1 bash ./build.sh
) 2>&1 | tee "$WORK/build-and-check.log"

{
  for f in root.apfs system.apfs flashboot.apfs; do
    if [[ -f "$SRC/userland/$f" ]]; then
      shasum -a 256 "$SRC/userland/$f"
      stat -c '%n bytes=%s' "$SRC/userland/$f"
    else
      printf 'missing=%s\n' "$f"
      exit 1
    fi
  done
  printf 'utc_finished=%s\n' "$(date -u +%FT%TZ)"
} >> "$WORK/metadata.txt"

echo 'Linux APFS validation completed. Images and all Apple-derived files remain on the ephemeral runner.'
