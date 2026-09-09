# Sonar

<p align="center"><img src="assets/sonar.png" alt="Sonar’s rainbow analemma logomark" width="240"></p>

Control your Mac by moving your hand above the keyboard. Sonar plays a high-frequency tone through the built-in speakers and listens for changes in its reflection. It uses the audio hardware already in your Mac.

**This is an experiment in progress.**

## What you can try

- **Scroll:** lift your palm to scroll in the selected direction, then lower it to stop. Double-tap the air with two quick downward pushes to switch direction (turn on **Air double-tap**). Works in the practice reader or other apps with Accessibility access.
- **Zoom:** push toward the screen to enlarge a picture or page, then pull back to zoom out. Practice here uses the bundled Yoda image. Other apps sends three zoom-in steps to the foreground app, then reverses them on return. Browsers finish by resetting to 100%. Return speed follows an estimate from your movement; it happens in steps. Experimental, with a reverse-gesture toggle. This controls zoom within the app’s content.
- **Swipe:** sweep sideways to send left/right arrow keys to another app, or browse five bundled photos offline. You can also open your own pictures. Use **Reverse directions** to match your preferred movement. The target app needs to be in front, with an image viewer open that accepts arrow keys. Return strokes can still cause mistakes. Other apps sends arrow keys to the foreground app, including Photos and browsers. The app or site must support arrow-key navigation; compatibility testing is ongoing.
- **Signal:** watch the microphone signal and how it changes as you move. The flowing waves illustrate changes in the signal.
- **Other experiments:** Distance and Position are works in progress. Their spatial estimates still need accuracy testing.

Sonar senses movement toward and away from the audio hardware. Sideways gestures are inferred from that signal. Physical position estimates remain experimental.

## How it works

The speakers play a high-frequency tone. The microphone picks up that tone and its reflections. When your hand moves, the reflected tone shifts slightly in frequency—the Doppler effect. Sonar watches those changes and turns recognized gestures into scrolling, arrow keys, or app zoom shortcuts.

Start with your hands still during the countdown so Sonar can measure the background sound. Then move your palm above the keyboard. In Scroll, **double-tap the air: push down twice quickly to change direction**. The direction arrow updates when the gesture is accepted. This works in both Practice here and Other apps when Air double-tap is enabled.

Signal lets you see the sound changes. Its flowing shapes are an illustration. Distance and Position use a separate chirp-based echo experiment; their position estimates remain experimental. Microphone audio stays on your Mac.

You can also open **How it works** from the app’s sidebar.

### Try Swipe

1. Hold an open hand palm-down above the keyboard, then sweep sideways from one side to the other. Each accepted sweep moves one image.
2. Pause before bringing your hand back. The return can still be mistaken for another swipe. If navigation feels backwards, turn on **Reverse directions**.
3. In **Practice here**, try the bundled photos or open your own. In **Other apps**, open an image viewer and click the image first. Keep the app in front; the viewer must support left/right arrow keys. The Previous and Next buttons let you check that navigation works before trying your hand.

### Try Zoom

1. Hold your palm above the keyboard. Push toward the screen to enlarge; pull back toward yourself to return. **Reverse gestures** swaps these directions.
2. In **Practice here**, Yoda enlarges to 150%. In **Other apps**, Sonar sends three zoom-in steps. Keep the app in front with focus outside text fields.
3. Pull back to zoom out again. A faster pull should produce a faster return, but it happens in steps and gesture recognition can miss. Native apps receive the matching zoom-out steps. Browsers finish with a reset to 100%, even if they started at a different zoom level.

## Build on your Mac

You need macOS 14 or later and Apple's command-line developer tools. Install the tools with `xcode-select --install` if needed.

```sh
git clone https://github.com/eperez28/sonar.cool.git
cd sonar.cool
./script/build_and_run.sh
```

This builds and tests the app, installs it to `~/Applications/Sonar.app`, then opens it. Local signing is included in the build process. The SoundWave paper is bundled in the practice reader.

To build without installing or opening anything:

```sh
./script/build_and_run.sh --build-only
```

The app and ZIP are written to `outputs/`. Automated tests check the code. Try the gestures on your Mac to check how they respond to your hands and setup.

## First run

Allow microphone access. Allow Accessibility if you want to control other apps. Choose a mode, press Start, and keep still during the startup countdown. Sessions run until you stop them. Stop is always available from the menu bar; Control–Option–Command–Space also stops the session.

Use the built-in speakers and microphone. Bluetooth audio is excluded. Some people can hear the tone: stop if it is audible or uncomfortable.

**FYI for pets:** Sonar defaults to a 20 kHz tone. [Dogs and cats can hear frequencies in this range](https://www.lsu.edu/vetmed/deafness/hearingrange.php). Use it away from pets and stop if they seem uncomfortable. Pet safety and sound levels across Mac models still need evaluation.

If macOS stops recognizing Accessibility access after a rebuild, remove the old entry and add the current app again. For repeated development, signing with the same certificate helps preserve access.

## Privacy

Microphone audio is processed locally in memory and discarded after processing. Recent motion readings are saved locally in `~/Library/Caches/Sonar/` for debugging when a scrolling session stops. Optional verification runs also write reports there.

## Power use

Power draw and battery impact still need measurement. Brief checks on September 9, 2026 showed 24–49% of one CPU core and about 169 MB of memory. The app version and sensing state during those samples remain unknown. The Signal screen later showed **Stopped**.

The first power comparison was inconclusive: the Mac was charging, system telemetry stopped updating, and detailed sampling required administrator access. Battery estimates require direct power measurements.

A repeatable measurement still needs a recorded app version and Mac model, consistent display brightness and background activity, and repeated equal-length stopped/active runs after calibration. Measure both with the window visible and with it hidden to distinguish visualization overhead. Report the additional average watts and measurement variability before making battery-life claims.

## Developer options

Set `SONAR_SIGNING_IDENTITY` to use your own signing certificate. Otherwise the script signs locally without a certificate. Set `SONAR_INSTALL_PATH` to keep an existing installation in its original location. The internal executable and bundle identifier retain the old SonarLab name to preserve app identity.

`SONAR_PAPER_PATH` optionally replaces the bundled SoundWave paper with a PDF of your choice. `--verify-audio` runs a short microphone/speaker check; `--verify-scroll` checks the practice reader with simulated gestures.

## Credit and license

Inspired by [SoundWave: Using the Doppler Effect to Sense Gestures](https://www.microsoft.com/en-us/research/project/soundwave-using-the-doppler-effect-to-sense-gestures/), by Sidhant Gupta, Dan Morris, Shwetak Patel, and Desney Tan (CHI 2012). Their research demonstrated gesture sensing with existing speakers and microphones. Sonar is Emanuel Perez’s independent implementation.

Sonar's source is available under the [MIT license](LICENSE). The bundled SoundWave paper retains its original copyright and separate terms.

If you’re enjoying Sonar, you can [buy me a coffee](https://buymeacoffee.com/emanuelperez).

Swipe photo sources and their separate license are listed in [photo credits](assets/gallery/CREDITS.md).

The Yoda practice image was supplied for this demo and retains its separate rights. For concerns about either bundled item, [contact Emanuel](https://x.com/emanperez28).

### Other apps

Swipe and Zoom can target the app in front, including Photos, Preview, and browsers. Swipe uses left/right arrow keys. Zoom uses Command-plus/minus, so it works where those shortcuts zoom the current photo or page. Click the content first; Sonar pauses over text fields.

In native apps, pulling back sends the matching zoom-out steps for the zoom-in steps Sonar sent. Zoom limits and manual changes can affect the final view. Browsers keep the existing final reset to 100%. App support depends on its keyboard shortcuts.
