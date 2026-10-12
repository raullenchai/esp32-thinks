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

# 1) The pinned root CA for api.openai.com (public Google Trust Services cert).
cp "$REPO_DIR/files/openai_root_ca.pem" esp32/components/muse/openai_root_ca.pem

# 2) The patch.
git apply --check "$REPO_DIR/patches/muse-tts.patch" || {
    echo "patch does not apply cleanly — is it already applied, or is your SDK a different revision?"; exit 1; }
git apply "$REPO_DIR/patches/muse-tts.patch"
echo "== patch applied: patches/muse-tts.patch"

# 3) Keys.
read -r -p "OpenAI API key (sk-proj-...): " OPENAI_KEY
case "$OPENAI_KEY" in sk-*) ;; *) echo "that doesn't look like an OpenAI key"; exit 1 ;; esac
sed -i.bak "s/sk-proj-REPLACE-WITH-YOURS/$OPENAI_KEY/" esp32/components/muse/muse_chat_session.cpp
rm -f esp32/components/muse/muse_chat_session.cpp.bak

read -r -p "Muse gadget token (mgst_..., from https://gadgets.muse.ai): " MUSE_TOKEN
case "$MUSE_TOKEN" in mgst_*) ;; *) echo "that doesn't look like a Muse gadget token"; exit 1 ;; esac
cat > esp32/sdkconfig.token.local <<EOF
# Written by esp32-thinks apply.sh
CONFIG_GADGET_SDK_TOKEN="$MUSE_TOKEN"
EOF
read -r -p "Enable Chinese (CJK) captions? [y/N]: " CJK
case "$CJK" in y|Y) echo "CONFIG_MUSE_CJK_FONT=y" >> esp32/sdkconfig.token.local
    echo "== CJK font on (adds ~6.8 MB to the firmware)" ;; esac

echo
echo "done. next:"
echo "  ./scripts/backup-nvs.sh $SDK   # once, before the first flash"
echo "  ./build-and-flash.sh   $SDK"
