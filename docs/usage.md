# Usage and development notes

### Try Swipe

1. Hold an open hand palm-down above the keyboard, then sweep sideways from one side to the other. Each accepted sweep moves one image.
2. Pause before bringing your hand back. The return can still be mistaken for another swipe. If navigation feels backwards, turn on **Reverse directions**.
3. In **Practice here**, try the bundled photos or open your own. In **Other apps**, open an image viewer and click the image first. Keep the app in front; the viewer must support left/right arrow keys. The Previous and Next buttons let you check that navigation works before trying your hand.

### Try Zoom

1. Hold your palm above the keyboard. Push toward the screen to enlarge; pull back toward yourself to return. **Reverse gestures** swaps these directions.
2. In **Practice here**, Yoda enlarges to 150%. In **Other apps**, Sonar sends three zoom-in steps. Keep the app in front with focus outside text fields.
3. Pull back to zoom out again. A faster pull should produce a faster return, but it happens in steps and gesture recognition can miss. Native apps receive the matching zoom-out steps. Browsers finish with a reset to 100%, even if they started at a different zoom level.

## Developer options

Set `SONAR_SIGNING_IDENTITY` to use your own signing certificate. Otherwise the script signs locally without a certificate. Set `SONAR_INSTALL_PATH` to keep an existing installation in its original location. Source files live in `work/Sonar/`, and the executable is named `Sonar`. The existing bundle identifier stays stable to preserve app identity.

`SONAR_PAPER_PATH` optionally replaces the bundled SoundWave paper with a PDF of your choice. `--verify-audio` runs a short microphone/speaker check; `--verify-scroll` checks the practice reader with simulated gestures.

### Other apps

Swipe and Zoom can target the app in front, including Photos, Preview, and browsers. Swipe uses left/right arrow keys. Zoom uses Command-plus/minus, so it works where those shortcuts zoom the current photo or page. Click the content first; Sonar pauses over text fields.

In native apps, pulling back sends the matching zoom-out steps for the zoom-in steps Sonar sent. Zoom limits and manual changes can affect the final view. Browsers keep the existing final reset to 100%. App support depends on its keyboard shortcuts.
