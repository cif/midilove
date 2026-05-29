#!/usr/bin/env bash
# Fetch the SoundFont assets midilove needs at runtime. Binaries aren't
# committed (too large, licensing varies). Run this once after cloning.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p Sounds

fetch() {
    local dest="$1" url="$2"
    if [[ -f "$dest" ]]; then
        echo "✓ $dest already present ($(du -h "$dest" | cut -f1))"
        return
    fi
    echo "↓ Downloading $dest"
    curl -L --fail -o "$dest" "$url"
    echo "✓ Saved $dest ($(du -h "$dest" | cut -f1))"
}

fetch "Sounds/Steinway.sf2" \
    "https://raw.githubusercontent.com/morashon/morashon/master/score/fluidsynth/Steinway%20Grand%20Piano%201.2.SF2"

fetch "Sounds/GM.sf2" \
    "https://raw.githubusercontent.com/bratpeki/soundfonts/main/SF2/GM/GeneralUser.sf2"

echo ""
echo "Done. Run \`swift run midilove-app\` to launch the synth."
