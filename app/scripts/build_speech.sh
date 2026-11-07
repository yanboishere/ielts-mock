#!/bin/zsh
# Builds speech.cpp (github.com/nyosegawa/speech.cpp, MIT) at the revision Arion pins (scripts/asr-runtime.json:
# 0.8.11, c4bdcd0e…), for macOS 14+ on Apple silicon with the Metal library embedded, into Vendor/speech/.
#   scripts/build_speech.sh                 clone and build
#   SPEECH_SRC=/path/to/checkout scripts/build_speech.sh   build an existing checkout of that revision
#   CMAKE=/path/to/cmake                    when cmake is not on PATH
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
REV=c4bdcd0e751bd29460cb1353e6d54499828a1d90
OUT="$ROOT/Vendor/speech"
CMAKE=${CMAKE:-cmake}
SRC=${SPEECH_SRC:-$ROOT/build/speech.cpp}
if [[ -z "${SPEECH_SRC:-}" ]]; then
  if [[ ! -d "$SRC/.git" ]]; then git clone https://github.com/nyosegawa/speech.cpp.git "$SRC"; fi
  git -C "$SRC" fetch --quiet origin "$REV" || true
  git -C "$SRC" checkout --quiet "$REV"
  git -C "$SRC" submodule update --init --recursive --quiet
fi
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$REV" ]] || { echo "speech.cpp checkout is not at $REV"; exit 1; }
"$CMAKE" -S "$SRC" -B "$SRC/build-ieltsmock" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON >/dev/null
"$CMAKE" --build "$SRC/build-ieltsmock" -j 8 --target speech-cli >/dev/null
mkdir -p "$OUT"
cp "$SRC/build-ieltsmock/speech" "$OUT/speech"
cp "$SRC/LICENSE" "$OUT/LICENSE-speech.cpp"
cp "$SRC/ggml/LICENSE" "$OUT/LICENSE-ggml"
echo "$REV" > "$OUT/REVISION"
"$OUT/speech" --version
