# Sonar

<p align="center"><img src="assets/sonar.png" alt="Sonar’s rainbow analemma logomark" width="240"></p>

Control your Mac by moving your hand above the keyboard. Sonar plays a high-frequency tone through the built-in speakers and listens for changes in its reflection. No camera or wearable required.

**Experimental.** Scrolling and Swipe navigation have worked on the development Mac. Accuracy varies with your hand movement, Mac, and room. This isn't a finished replacement for your trackpad.

## What you can try

- **Scroll:** lift your palm to scroll in the selected direction, then lower it to stop. Double-tap the air with two quick downward pushes to switch direction (turn on **Air double-tap**). Works in the practice reader or other apps with Accessibility access.
- **Zoom:** push toward the screen to enlarge a picture or page, then pull back to zoom out. Practice here uses the bundled Yoda image. Other apps sends three zoom-in steps to the foreground app, then reverses them on return. Browsers finish by resetting to 100%. Return speed follows an estimate from your movement; it happens in steps. Experimental, with a reverse-gesture toggle. This changes the app’s content zoom, not macOS screen magnification.
- **Swipe:** sweep sideways to send left/right arrow keys to another app, or browse five bundled photos offline. You can also open your own pictures. Use **Reverse directions** to match your preferred movement. The target app needs to be in front, with an image viewer open that accepts arrow keys. Return strokes can still cause mistakes. Other apps sends arrow keys to the foreground app, including Photos and browsers. The app or site must support arrow-key navigation; compatibility has not been tested in every app.
- **Signal:** watch the microphone signal and how it changes as you move. The flowing waves are an illustration driven by the signal, not a picture of your hand.
- **Other experiments:** Distance and Position are works in progress. Distance and Position do not provide dependable hand height, 3D tracking, or a spatial point cloud.

Sonar senses movement toward and away from the audio hardware. Sideways gestures are inferred from that signal; it doesn't recognize fingers or reliably know your hand's physical position.

## How it works

The speakers play a high-frequency tone. The microphone picks up that tone and its reflections. When your hand moves, the reflected tone shifts slightly in frequency—the Doppler effect. Sonar watches those changes and turns recognized gestures into scrolling, arrow keys, or app zoom shortcuts.

Start with your hands still during the countdown so Sonar can measure the background sound. Then move your palm above the keyboard. In Scroll, **double-tap the air: push down twice quickly to change direction**. The direction arrow updates when the gesture is accepted. This works in both Practice here and Other apps when Air double-tap is enabled.

Signal lets you see the sound changes. Its flowing shapes are an illustration. Distance and Position use a separate chirp-based echo experiment; they do not reliably measure your hand’s physical position. No camera is involved, and microphone audio stays on your Mac.

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

This builds and tests the app, installs it to `~/Applications/Sonar.app`, then opens it. No paid developer account or separate paper download is needed. The SoundWave paper is bundled in the practice reader.

To build without installing or opening anything:

```sh
./script/build_and_run.sh --build-only
```

The app and ZIP are written to `outputs/`. Automated tests check the code; they don't prove that gestures work on your hardware. Another Mac still needs a real hand test.

## First run

Allow microphone access. Allow Accessibility if you want to control other apps. Choose a mode, press Start, and keep still during the startup countdown. Sessions run until you stop them. Stop is always available from the menu bar; Control–Option–Command–Space also stops the session.

Use the built-in speakers and microphone. Bluetooth audio is excluded. Some people can hear the tone: stop if it is audible or uncomfortable. We haven't established safety for pets or measured sound levels across Macs.

If macOS stops recognizing Accessibility access after a rebuild, remove the old entry and add the current app again. For repeated development, signing with the same certificate helps preserve access.

## Privacy

Microphone audio stays in memory and isn't saved or uploaded. Recent motion readings are saved locally in `~/Library/Caches/Sonar/` for debugging when a scrolling session stops. Optional verification runs also write reports there.

## Power use

**Power draw and battery impact have not been established.** During brief checks on September 9, 2026, the installed development app used 24–49% of one CPU core and about 169 MB of memory. These are process snapshots, not a benchmark of the current source: the installed build revision wasn't recorded, and active sensing wasn't verified during the CPU samples. The Signal screen subsequently showed **Stopped**.

An attempted Signal stopped/active comparison produced no usable wattage result. The Mac was plugged in and charging, whole-system power telemetry stopped updating, and detailed power sampling required administrator access. CPU percentages and macOS energy-impact scores are not watts and cannot establish battery drain per hour.

A repeatable measurement still needs a recorded app version and Mac model, consistent display brightness and background activity, and repeated equal-length stopped/active runs after calibration. Measure both with the window visible and with it hidden to distinguish visualization overhead. Report the additional average watts and measurement variability before making battery-life claims.

## Developer options

Set `SONAR_SIGNING_IDENTITY` to use your own signing certificate. Otherwise the script signs locally without a certificate. Set `SONAR_INSTALL_PATH` to keep an existing installation in its original location. The internal executable and bundle identifier retain the old SonarLab name to preserve app identity.

`SONAR_PAPER_PATH` optionally replaces the bundled SoundWave paper with a PDF of your choice. `--verify-audio` runs a short microphone/speaker check; `--verify-scroll` checks the practice reader with simulated gestures.

## Credit and license

Inspired by [SoundWave: Using the Doppler Effect to Sense Gestures](https://www.microsoft.com/en-us/research/project/soundwave-using-the-doppler-effect-to-sense-gestures/), by Sidhant Gupta, Dan Morris, Shwetak Patel, and Desney Tan (CHI 2012). Their research demonstrated gesture sensing with existing speakers and microphones. Sonar is a separate experimental implementation, not an official Microsoft product.

Sonar's source is available under the [MIT license](LICENSE). That license does not cover the bundled SoundWave paper, which retains its original copyright notice. No Apple 3D models are included.

If you’re enjoying Sonar, you can [buy me a coffee](https://buymeacoffee.com/emanuelperez).

Swipe photo sources and their separate license are listed in [photo credits](assets/gallery/CREDITS.md).

The Yoda practice image was supplied for this demo and is not covered by the MIT code license. For concerns about either bundled item, [contact Emanuel](https://github.com/eperez28/sonar.cool/issues).

### Other apps

Swipe and Zoom can target the app in front, including Photos, Preview, and browsers. Swipe uses left/right arrow keys. Zoom uses Command-plus/minus, so it works where those shortcuts zoom the current photo or page. Click the content first; Sonar pauses over text fields.

In native apps, pulling back sends the matching zoom-out steps for the zoom-in steps Sonar sent. This does not guarantee the exact original view if the app hits a zoom limit or you also change zoom manually. Browsers keep the existing final reset to 100%. App support depends on its shortcuts; arbitrary apps do not automatically gain gesture support.
