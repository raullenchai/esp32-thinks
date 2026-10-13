#!/usr/bin/env bash
# esp32-thinks: apply the TTS patch to a muse-gadget-sdk checkout and write your keys in.
#
# Usage: ./apply.sh /path/to/muse-gadget-sdk
set -euo pipefail

SDK=${1:?usage: ./apply.sh /path/to/muse-gadget-sdk}
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

test -d "$SDK/esp32/components/muse" || { echo "not a muse-gadget-sdk checkout: $SDK"; exit 1; }
cd "$SDK"
echo "== muse-gadget-sdk @ $(git rev-parse --short HEAD) (recipe tested against 812c46f)"

# 1) Provider + model. The URL and root CA must match.
read -r -p "TTS provider [quicksilver/openai]: " TTS_PROVIDER
TTS_PROVIDER=${TTS_PROVIDER:-quicksilver}
TTS_VOICE=alloy
case "$TTS_PROVIDER" in
    quicksilver)
        TTS_URL=https://api.quicksilverpro.io/v1/audio/speech
        TTS_CA=isrg-root-x1.pem
        read -r -p "Reply language [en/zh]: " TTS_LANGUAGE
        case "${TTS_LANGUAGE:-en}" in
            en) TTS_MODEL=chatterbox-turbo ;;
            zh) TTS_MODEL=qwen3-tts ;;
            *) echo "choose en (English) or zh (Chinese / mixed)"; exit 1 ;;
        esac ;;
    openai)
        TTS_URL=https://api.openai.com/v1/audio/speech
        TTS_CA=openai_root_ca.pem
        read -r -p "TTS model [tts-1]: " TTS_MODEL
        TTS_MODEL=${TTS_MODEL:-tts-1}
        read -r -p "TTS voice [alloy]: " TTS_VOICE
        TTS_VOICE=${TTS_VOICE:-alloy} ;;
    *) echo "choose quicksilver or openai"; exit 1 ;;
esac
case "$TTS_MODEL:$TTS_VOICE" in
    *[!a-zA-Z0-9._:-]*) echo "use model / voice names with letters, digits, dots, underscores or hyphens"; exit 1 ;;
esac

# 2) Keys. Read and validate inputs before changing the tree.
case "$TTS_PROVIDER" in
    quicksilver) read -r -p "QuickSilver Pro API key (get one: https://quicksilverpro.io/dashboard/?intent=speech): " TTS_KEY ;;
    openai)
        read -r -p "OpenAI API key (sk-proj-...): " TTS_KEY
        case "$TTS_KEY" in sk-*) ;; *) echo "that doesn't look like an OpenAI key"; exit 1 ;; esac ;;
esac
case "$TTS_KEY" in
    ''|*[![:graph:]]*|*\"*|*\\*) echo "use a non-empty API key without whitespace, quotes or backslashes"; exit 1 ;;
esac
read -r -p "Muse gadget token (mgst_..., from https://gadgets.muse.ai): " MUSE_TOKEN
case "$MUSE_TOKEN" in mgst_*) ;; *) echo "that doesn't look like a Muse gadget token"; exit 1 ;; esac
read -r -p "Enable Chinese (CJK) captions? [y/N]: " CJK

# 3) The patch. On a rerun, check a temporary copy with the defaults restored;
#    configured defines must not prevent the reverse check.
if git apply --check "$REPO_DIR/patches/muse-tts.patch" 2>/dev/null; then
    git apply "$REPO_DIR/patches/muse-tts.patch"
    echo "== patch applied: patches/muse-tts.patch"
else
    CHECK_DIR=$(mktemp -d)
    trap 'rm -rf "$CHECK_DIR"' EXIT
    mkdir -p "$CHECK_DIR/esp32/components/muse"
    for FILE in CMakeLists.txt muse_chat_session.cpp muse_voice.c; do
        cp "esp32/components/muse/$FILE" "$CHECK_DIR/esp32/components/muse/$FILE"
    done
    sed -i.bak \
        -e 's|^#define TTS_API_KEY .*|#define TTS_API_KEY "REPLACE-WITH-YOURS"|' \
        -e 's|^#define TTS_URL .*|#define TTS_URL "https://api.quicksilverpro.io/v1/audio/speech"|' \
        -e 's|^#define TTS_MODEL .*|#define TTS_MODEL "chatterbox-turbo"|' \
        -e 's|^#define TTS_VOICE .*|#define TTS_VOICE "alloy"|' \
        "$CHECK_DIR/esp32/components/muse/muse_chat_session.cpp"
    (cd "$CHECK_DIR"; git apply --reverse --check "$REPO_DIR/patches/muse-tts.patch") || {
        echo "patch does not apply cleanly — is your SDK a different revision or patch version?"; exit 1; }
    rm -rf "$CHECK_DIR"
    trap - EXIT
    echo "== patch already applied: patches/muse-tts.patch"
fi

# 4) Configuration.
cp "$REPO_DIR/files/$TTS_CA" esp32/components/muse/tts_root_ca.pem
# Escape sed replacement characters; the key's prefix is provider-specific.
TTS_KEY_SED=$(printf '%s' "$TTS_KEY" | sed 's/[&|]/\\&/g')
sed -i.bak \
    -e "s|^#define TTS_API_KEY .*|#define TTS_API_KEY \"$TTS_KEY_SED\"|" \
    -e "s|^#define TTS_URL .*|#define TTS_URL \"$TTS_URL\"|" \
    -e "s|^#define TTS_MODEL .*|#define TTS_MODEL \"$TTS_MODEL\"|" \
    -e "s|^#define TTS_VOICE .*|#define TTS_VOICE \"$TTS_VOICE\"|" \
    esp32/components/muse/muse_chat_session.cpp
rm -f esp32/components/muse/muse_chat_session.cpp.bak
echo "== TTS: $TTS_PROVIDER / $TTS_MODEL / $TTS_VOICE (root: $TTS_CA)"

cat > esp32/sdkconfig.token.local <<EOF
# Written by esp32-thinks apply.sh
CONFIG_GADGET_SDK_TOKEN="$MUSE_TOKEN"
EOF
case "$CJK" in y|Y) echo "CONFIG_MUSE_CJK_FONT=y" >> esp32/sdkconfig.token.local
    echo "== CJK font on (adds ~6.8 MB to the firmware)" ;; esac

echo
echo "done. next:"
echo "  ./scripts/backup-nvs.sh $SDK   # once, before the first flash"
echo "  python3 scripts/tts_probe.py $SDK --preflight"
echo "  ./build-and-flash.sh   $SDK"
