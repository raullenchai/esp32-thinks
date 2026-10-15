# Third-party notices

The repository's own scripts and documentation use the [MIT license](LICENSE).

`patches/muse-brain.patch` modifies and includes context from Meta's **muse-gadget-sdk**, pinned to commit `812c46f`. The SDK is licensed under **Apache-2.0**, and its source copyright/license headers remain in place. New firmware helpers marked `SPDX-License-Identifier: Apache-2.0` retain that license as well. A copy is provided in [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt).

Upstream source and license: [facebookincubator/muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk/tree/812c46f).

ESP-IDF, ESP-SR, ESP-DL, LVGL and other dependencies are fetched by the SDK build. Their licenses and notices remain in their respective packages; this repository does not relicense them. Public certificate files in `files/` are trust anchors, not private keys.
