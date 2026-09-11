# Sonar

Control your Mac with a wave of your hand. Sonar uses your Mac’s built-in speakers and microphone to detect movement.

**This is an experiment in progress.** Requires macOS 14 or later.

[Website](https://sonar.cool) · [Contact Emanuel](https://x.com/emanperez28)

## Download

[Download Sonar v0.1.2 for Apple silicon](https://github.com/eperez28/sonar.cool/releases/download/v0.1.2/Sonar-0.1.2-arm64.dmg). Open the DMG and drag Sonar into Applications. Requires macOS 14 or later. This is an experimental pre-release; testing across MacBook models is ongoing.

## Run from source

Install Apple’s command-line developer tools with `xcode-select --install`, then:

```sh
git clone https://github.com/eperez28/sonar.cool.git
cd sonar.cool
./script/build_and_run.sh
```

The script builds and tests Sonar, installs it to `~/Applications/Sonar.app`, and opens it. Source files live in `work/Sonar/`. Try the gestures on your Mac to see how they respond to your setup.

## Before you start

Allow microphone access and Accessibility access for controlling other apps. Choose a mode, press Start, and keep your hands still during the countdown. Stop the session from the menu bar or with Control–Option–Command–Space.

Use the built-in speakers and microphone. Stop if the tone is audible or uncomfortable.

**FYI for pets:** The default tone is 20 kHz. [Dogs and cats can hear this frequency](https://www.lsu.edu/vetmed/deafness/hearingrange.php). Use Sonar away from pets and stop if they seem uncomfortable. Pet safety and sound levels across Mac models still need evaluation.

## Gestures

- **Scroll:** Lift your hand up and down to scroll. Do a double tap (in the air!) to reverse directions.
- **Change scroll direction:** enable **Air double-tap**, then push down twice quickly.
- **Swipe:** sweep sideways to browse photos or navigate apps that accept arrow keys; pause before returning your hand.
- **Zoom:** push toward the screen to zoom in and pull back to zoom out; browser zoom returns to 100%.
- **Signal:** watch an illustration of the sound changes as you move.

Use **Practice here** to try the bundled demos. For **Other apps**, bring the target app forward and click its content. Direction controls let you reverse Swipe and Zoom. [More about gestures and app compatibility](docs/usage.md).

### Lift your hand to scroll

Lift your hand up and down to scroll. Do a double tap (in the air!) to reverse directions.

![Hand gesture controlling scrolling](assets/zoom/scroll.gif)

### Sweep your hand to swipe

Sweep your hand sideways to change photos. Pause before returning your hand.

![Hand gesture controlling photo navigation](assets/zoom/swipe.gif)

### Push and pull to zoom

Push toward the screen to zoom in. Pull back toward yourself to zoom out.

![Push and pull hand gesture controlling zoom](assets/zoom/push-pull.gif)

## How it works

Your Mac’s speakers play a steady, high-frequency tone, set to 20 kHz by default. Some of that sound bounces off your hand and returns to the microphone.

As your hand moves toward the speakers and microphone, the reflected sound shifts slightly higher in frequency. Moving away shifts it lower. This is the **Doppler effect**, the same effect that changes the pitch of a passing siren.

Sonar compares the reflected sound with the tone it’s playing. It looks for patterns in those frequency changes, then turns a recognized gesture into a scroll, swipe, or zoom command. The microphone also picks up reflections from your desk, room, and other movement. Separating those reflections from your hand’s movement is part of the experiment.

**Sonar** describes using sound and echoes to sense something. The **Doppler effect** is the frequency change this app uses to detect movement.

![Animation showing a steady tone traveling from a Mac speaker to a moving hand, reflected sound returning to the microphone, and the app detecting its frequency shift.](assets/gesture-sensing.gif)

## Status

Scrolling and Swipe have worked on the development Mac. Sideways gestures are inferred from movement toward and away from the audio hardware. Return strokes can trigger extra swipes, and Zoom recognition still needs testing across setups. Distance and Position are ongoing experiments.

Power and battery testing is ongoing. [Measurement notes](docs/power.md).

Reports from other Mac models and pull requests are welcome. Include your Mac model, macOS version, mode, and what happened.

## Privacy

Microphone audio is processed locally in memory and discarded after processing. Recent motion readings and optional verification reports are saved locally in `~/Library/Caches/Sonar/` for debugging.

## Credit and license

Inspired by [SoundWave: Using the Doppler Effect to Sense Gestures](https://www.microsoft.com/en-us/research/project/soundwave-using-the-doppler-effect-to-sense-gestures/), by Sidhant Gupta, Dan Morris, Shwetak Patel, and Desney Tan (CHI 2012). Their research demonstrated gesture sensing with existing speakers and microphones. Sonar is Emanuel Perez’s independent implementation.

Thanks also to Daniel Rapp for [Doppler](https://github.com/DanielRapp/doppler), his browser implementation of SoundWave. We studied his sensing code and demos as a reference while building Sonar.

Sonar's source is available under the [MIT license](LICENSE). The bundled SoundWave paper retains its original copyright and separate terms.

If you’re enjoying Sonar, you can [buy me a coffee](https://buymeacoffee.com/emanuelperez).

Swipe photo sources and their separate license are listed in [photo credits](assets/gallery/CREDITS.md).

The Yoda practice image was supplied for this demo and retains its separate rights. For concerns about either bundled item, [contact Emanuel](https://x.com/emanperez28).

## Troubleshooting report (development build)

If Sonar says Active but nothing happens—or it scrolls while your hand is still—open **Run diagnostics…** in the sidebar. The test pauses gesture control, checks the microphone and speaker signal, and asks you to move your palm. It measures calibration variation and runs the scroll rules without controlling your apps to check for unwanted scrolling. After it finishes, optional frequency and longer stillness checks add to the same report. You can also send one timed test scroll to another app and tell Sonar whether it worked.

Choose **Save report…** to save a readable `.txt` file with the result first and technical details below. The report includes your Mac model, macOS and app versions, permission status, session-local audio route numbers, volume/mute values, audio callback errors, and summary signal measurements. It contains no recorded audio, screenshots, window titles, device names, serial numbers, or file paths. Nothing is uploaded automatically.

The checks help narrow down a problem; they cannot identify every source of interference. Frequency checks do not change your normal settings. This feature is currently in the diagnostic development build, not the published 0.1.2 installer.
