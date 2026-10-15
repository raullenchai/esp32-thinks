#!/usr/bin/env bash
# esp32-thinks: apply the brain patch to a muse-gadget-sdk checkout and write your provider config.
#
# Usage: ./apply.sh /path/to/muse-gadget-sdk [--preset openai|quicksilver|custom]
#
# The brain patch gives the device its own STT + chat + TTS against any
# OpenAI-compatible servers. Each of the three endpoints is independent: they
# can be the same provider or three different ones.
set -euo pipefail

SDK=${1:?usage: ./apply.sh /path/to/muse-gadget-sdk [--preset openai|quicksilver|custom]}
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PRESET="openai"
if [ "${2:-}" = "--preset" ]; then
    PRESET=${3:-openai}
elif [ -n "${2:-}" ]; then
    echo "unknown option: $2 (usage: ./apply.sh <sdk> [--preset openai|quicksilver|custom])"; exit 1
fi

test -d "$SDK/esp32/components/muse" || { echo "not a muse-gadget-sdk checkout: $SDK"; exit 1; }
cd "$SDK"
echo "== muse-gadget-sdk @ $(git rev-parse --short HEAD) (recipe tested against 812c46f)"

# 1) Pinned root CAs (both public): Google Trust Services R4 for api.openai.com,
#    Root YE + ISRG Root X1 for Let's Encrypt hosts (QuickSilver and others).
cp "$REPO_DIR/files/openai_root_ca.pem" esp32/components/muse/openai_root_ca.pem
cp "$REPO_DIR/files/qs_root_ca.pem"     esp32/components/muse/qs_root_ca.pem

# 2) The patch.
git apply --check "$REPO_DIR/patches/muse-brain.patch" || {
    echo "patch does not apply cleanly — is it already applied, or is your SDK a different revision?"; exit 1; }
git apply "$REPO_DIR/patches/muse-brain.patch"
echo "== patch applied: patches/muse-brain.patch"

# 3) Provider config. Defaults below; presets override them.
TTS_URL="https://api.openai.com/v1/audio/speech"
TTS_MODEL="tts-1";            TTS_VOICE="nova"
TTS_MODEL_CJK=""              # optional second voice model for Chinese turns
TTS_KEY=""
STT_URL="https://api.openai.com/v1/audio/transcriptions"
STT_MODEL="whisper-1"
STT_ADPCM=0                                    # opt in only with a verified WAV decoder
STT_LANG="zh"                                   # pin Whisper's language ("auto" = let it guess)
STT_PROMPT="以下是普通话的句子。"                    # prompt nudge in that language
CHAT_URL="https://api.openai.com/v1"
CHAT_KEY=""
CHAT_MODEL="gpt-4o-mini"
CHAT_EXTRA=""                 # JSON merged into the chat body (provider quirks)
CHAT_SYSTEM="You are a terse question-answering device. NEVER output a greeting, salutation or wake phrase. NEVER say Hi ESP, High ESP or Hey ESP. If the input is only a greeting or wake phrase (hi, hello, hey, 你好, Hi ESP), respond with exactly Please ask. and nothing else. Otherwise answer directly in the user's language in ONE short sentence of at most 15 characters. No introduction. No greeting. No wake phrase. You cannot take actions or set reminders."
TTS_CA="OPENAI_CA"; BRAIN_CA="OPENAI_CA"

case "$PRESET" in
  openai)
    echo "== preset: OpenAI for all three endpoints"
    read -r -p "OpenAI API key (sk-proj-...): " KEY
    case "$KEY" in sk-*) ;; *) echo "that doesn't look like an OpenAI key"; exit 1 ;; esac
    TTS_KEY="$KEY"; CHAT_KEY="$KEY"
    ;;
  quicksilver)
    echo "== preset: QuickSilver (qwen flash chat, whisper STT, chatterbox/qwen3 TTS)"
    TTS_URL="https://api.quicksilverpro.io/v1/audio/speech"
    TTS_MODEL="chatterbox-turbo"; TTS_VOICE=""
    TTS_MODEL_CJK="qwen3-tts"     # Chinese turns; chatterbox is English-first
    STT_URL="https://api.quicksilverpro.io/v1/audio/transcriptions"
    STT_MODEL="whisper-large-v3-turbo"
    STT_ADPCM=1                                # IMA ADPCM WAV: ~4x less upload data
    CHAT_URL="https://api.quicksilverpro.io/v1"
    CHAT_MODEL="qwen3.7-flash"
    # escaped for embedding in the C string: {"reasoning":{"exclude":true}}
    CHAT_EXTRA='{\"reasoning\":{\"exclude\":true}}'   # skip its thinking phase
    TTS_CA="ISRG_CA"; BRAIN_CA="ISRG_CA"
    read -r -p "QuickSilver API key: " KEY
    TTS_KEY="$KEY"; CHAT_KEY="$KEY"
    ;;
  custom)
    echo "== preset: custom — enter each endpoint (return = keep the OpenAI default shown)"
    ask() { read -r -p "$1 [$2]: " V; echo "${V:-$2}"; }
    TTS_URL=$(ask "Speech URL" "$TTS_URL")
    TTS_MODEL=$(ask "Speech model" "$TTS_MODEL")
    TTS_VOICE=$(ask "Speech voice" "$TTS_VOICE")
    STT_URL=$(ask "Transcription URL" "$STT_URL")
    STT_MODEL=$(ask "Transcription model" "$STT_MODEL")
    CHAT_URL=$(ask "Chat base URL" "$CHAT_URL")
    CHAT_MODEL=$(ask "Chat model" "$CHAT_MODEL")
    read -r -p "Speech API key: " TTS_KEY
    read -r -p "Chat + transcription API key [same as speech]: " K
    CHAT_KEY=${K:-$TTS_KEY}
    ;;
  *) echo "unknown preset: $PRESET (openai | quicksilver | custom)"; exit 1 ;;
esac

if [[ "$TTS_URL" != *api.openai.com* && "$TTS_CA" == OPENAI_CA ]]; then TTS_CA="ISRG_CA"; fi
if [[ "$CHAT_URL" != *api.openai.com* && "$BRAIN_CA" == OPENAI_CA ]]; then BRAIN_CA="ISRG_CA"; fi

# 4) Optional: headless provisioning (skip the BLE phone-setup flow entirely).
read -r -p "Wi-Fi SSID for headless provisioning [skip]: " DEV_SSID || true
DEV_SSID=${DEV_SSID:-}
DEV_PASS=""
if [ -n "$DEV_SSID" ]; then
    read -r -s -p "Wi-Fi password: " DEV_PASS; echo
fi

# 5) Muse gadget token is now OPTIONAL: leave it empty to run fully on your own
#    brain. With a token the stock Muse cloud agent still handles anything the
#    brain doesn't (e.g. messages typed from the Muse phone app).
read -r -p "Muse gadget token (mgst_..., empty to skip): " MUSE_TOKEN || MUSE_TOKEN=""
case "$MUSE_TOKEN" in mgst_*|"") ;; *) echo "that doesn't look like a Muse gadget token"; exit 1 ;; esac

cat > esp32/sdkconfig.token.local <<EOF
# Written by esp32-thinks apply.sh
CONFIG_GADGET_SDK_TOKEN="$MUSE_TOKEN"
EOF
read -r -p "Enable Chinese (CJK) captions? [y/N]: " CJK || true
case "${CJK:-}" in y|Y) echo "CONFIG_MUSE_CJK_FONT=y" >> esp32/sdkconfig.token.local
    echo "== CJK font on (adds ~6.8 MB to the firmware)" ;; esac

# 5b) Voice wake word: say "Hi ESP" (WakeNet10, esp-sr) or press the button --
#     both start a turn. Needs a `model` flash partition for the wake model.
read -r -p "Enable the \"Hi ESP\" voice wake word (button PTT still works)? [Y/n]: " WAKE || true
case "${WAKE:-y}" in n|N) WAKE_WORD=0; echo "== wake word off (button PTT only)" ;;
    *) WAKE_WORD=1; echo "== wake word on: say \"Hi ESP\", or hold the button" ;; esac

# 6) Write the config the patch reads.
cat > esp32/components/muse/provider_config.h <<EOF
/*
 * provider_config.h -- which OpenAI-compatible servers this gadget talks to.
 * Written by esp32-thinks apply.sh. All three endpoints are independent.
 *
 * Keys are compiled into the firmware -- see Security in docs/REFERENCE.md.
 * To use another provider, drop its root PEM into components/muse/, add it to
 * EMBED_TXTFILES in CMakeLists.txt, declare it here, and point TTS_CA /
 * BRAIN_CA at it.
 */

/* --- Speech (text -> MP3) --- */
#define TTS_URL       "$TTS_URL"
#define TTS_MODEL     "$TTS_MODEL"
#define TTS_VOICE     "$TTS_VOICE"
#define TTS_MODEL_CJK "$TTS_MODEL_CJK"
#define TTS_API_KEY   "$TTS_KEY"
#define TTS_CA        $TTS_CA

/* --- Transcription (voice note -> text) --- */
#define BRAIN_STT_URL   "$STT_URL"
#define BRAIN_STT_MODEL "$STT_MODEL"
/* 1: 4-bit IMA ADPCM WAV; 0: 16-bit PCM WAV for maximum compatibility. */
#define BRAIN_STT_WAV_ADPCM $STT_ADPCM
/* Whisper hallucinates a language on short notes; pin it (ISO 639-1) and
 * nudge it with a prompt in that language. "auto" sends neither field. */
#define BRAIN_STT_LANG   "$STT_LANG"
#define BRAIN_STT_PROMPT "$STT_PROMPT"

/* --- Chat (text -> reply text) --- */
#define BRAIN_CHAT_URL  "$CHAT_URL"
#define BRAIN_CHAT_KEY  "$CHAT_KEY"
#define BRAIN_MODEL     "$CHAT_MODEL"
/* Optional extra JSON merged into the chat request body (provider quirks). */
#define BRAIN_CHAT_EXTRA "$CHAT_EXTRA"
#define BRAIN_SYSTEM    "$CHAT_SYSTEM"

/* --- Which root each of the above chains to --- */
#define BRAIN_CA      $BRAIN_CA

/* Leave BRAIN_CHAT_URL empty ("") to skip the brain and use the Muse cloud
 * agent as before (TTS still applies to its replies). */

/* --- Headless provisioning (optional) ---
 * When set, a board with no saved Wi-Fi writes these on boot instead of
 * requiring the BLE phone-setup flow. Leave the SSID empty for normal
 * behavior. */
#define DEV_WIFI_SSID "$DEV_SSID"
#define DEV_WIFI_PASS "$DEV_PASS"

/* --- Voice wake word ("Hi ESP", esp-sr WakeNet10) ---
 * 1 = wake word + button both start a turn; 0 = button only. The wake model
 * lives in the model flash partition (partitions_muse.csv, flashed as
 * srmodels.bin). WAKE_VAD_DB ends a wake-word turn after this many dBFS of
 * silence (raise toward -35 if it keeps recording after you stop). */
#define WAKE_WORD $WAKE_WORD
#define WAKE_VAD_DB (-45.0f)
EOF
echo "== provider_config.h written ($PRESET preset)"

echo
echo "done. next:"
echo "  ./scripts/backup-nvs.sh $SDK   # once, before the first flash"
echo "  ./build-and-flash.sh   $SDK"
