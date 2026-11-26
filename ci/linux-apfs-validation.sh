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

# Debian/Ubuntu's 7zip package installs 7zz; fetch.sh expects the historical `7z` name.
BIN="$RUNNER_TEMP/7z-compat"
mkdir -p "$BIN"
ln -sf "$(command -v 7zz)" "$BIN/7z"
export PATH="$BIN:$PATH"

(
  cd "$SRC/ios165"
  bash ./fetch.sh
) 2>&1 | tee "$WORK/fetch.log"

(
  cd "$SRC/userland"
  PREBUILT=1 CHECK=1 SYSTEM=1 FLASHBOOT=1 bash ./build.sh
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
