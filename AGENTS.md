# Sonar — agent guidance

## Scope and identity

- Work on the native **Sonar Lab app** only, unless the user explicitly expands the task.
- GitHub repository: https://github.com/eperez28/sonar.cool
- Default branch: `master`.
- App source: `work/Sonar/`; executable: `Sonar`. Preserve the existing bundle identifier `com.emanuel.sonarlab` for permission continuity. Older installations may use `/Applications/SonarLab.app`; preserve their path when updating. Keep the legacy process-name check in the installer for upgrades.
- User-facing app branding is `Sonar`; the repository is `sonar.cool`.
- Do not include SonarTheremin, the website, Blender projects, renders, or sibling-workspace files in Lab commits. These were previously pushed accidentally; the public-preparation history removes them.

## Before editing or committing

1. Verify the checkout with `git rev-parse --show-toplevel`, `git status --short`, and `git remote -v`.
2. Fetch the remote and compare history before pushing. A development checkout may lag behind commits pushed from another worktree; apparent local changes may already exist upstream.
3. Preserve uncommitted changes. Do not reset, clean, overwrite, or stash other work automatically to resolve divergence.
4. Stage explicit Lab paths and inspect the staged diff. Avoid `git add .` in mixed workspaces.
5. When asked to commit and push, use this repository and its `master` branch unless the user requests another branch. Use a normal fast-forward push, verify the remote commit, and report its hash. Never force-push without explicit authorization.
6. A feature request does not by itself require a commit or push.

## Build and run

- Native Swift/AppKit/SwiftUI app, built with `swiftc`; no Xcode project is required.
- Build and test without installing: `./script/build_and_run.sh --build-only`.
- Running without a flag installs to `~/Applications/Sonar.app` and launches it after tests pass.
- Optional settings: `SONAR_SIGNING_IDENTITY`, `SONAR_INSTALL_PATH`, and `SONAR_PAPER_PATH`. No personal paths or certificate defaults belong in source.
- Use an explicit stable certificate and existing installation path when updating an established installation. Never replace its signature with ad-hoc signing silently.
- New developers can build ad-hoc without a certificate; Accessibility may need granting again after rebuilding.
- Do not commit certificates, private keys, generated bundles, ZIPs, or build output.
- A successful build or synthetic test does not prove live gesture accuracy. Report physical testing separately.

## Permissions and live operation

- Check existing Accessibility trust silently. Never repeatedly prompt when the user already enabled access.
- Preserve the bundle identifier, signing identity, and installed path during branding changes.
- Permission settings are opened only through explicit user action; do not reset TCC as a routine fix.
- Keep an immediate stop available. Sessions run until stopped; do not restore the old time limit.
- Use built-in audio, keep microphone samples local/in memory, and preserve Bluetooth exclusion.
- Rebuilds restart the app. Restore the user's selected mode, target, and direction preference where possible; make calibration state visible before resuming gestures.

## Gesture behavior

### Swipe

- The user's preferred mapping is **right-to-left sweep → Right Arrow / Next**, and **left-to-right sweep → Left Arrow / Previous**.
- This preference is currently enabled through the persisted `galleryWaveReversed` setting. Do not silently reset or double-invert it.
- Other apps sends arrow keys to the foreground app while focus is outside editable fields. Preserve these checks.
- `Previous` / `Next` buttons isolate app delivery from hand recognition. Sending a key successfully is not proof that the image changed; inspect the browser result.
- Prioritize one intentional navigation per sweep. Returning the hand must not immediately undo that navigation.
- Current detector baseline: 40 ms minimum evidence, at least 3 coherent samples, 650 ms cooldown, and 220 ms quiet re-arm. These are implementation thresholds, not guaranteed end-to-end latency.
- A previous attempt to shorten cooldown to 280 ms and quiet re-arm to 120 ms caused return strokes to navigate backward. Do not repeat that tuning without a better return-stroke model and live verification.
- Preserve tests for both directions, ambiguous motion, paused return strokes, and subsequent deliberate gestures.
- No mandatory wave recordings or per-direction training. Doppler sign is radial; it is not verified anatomical left/right tracking.

### Scroll

- Lift the hand to scroll; lower it to reset. Return motion must not reverse the page.
- Two short downward pushes switch the selected scroll direction.
- Keep scrolling smooth across brief uncertain readings while stopping safely on stale input.

## UI and experimental sensing

- Use brief instructions, obvious live state, and a visible countdown whenever calibration requires waiting.
- Preserve guards for empty signal/range arrays; empty-profile rendering previously caused a crash.
- Distance and Position are experimental echo estimates. Do not describe them as exact hand height, proven 3D positioning, or a point cloud.
- Keep synthetic tests separate from real microphone/speaker behavior and real-hand acceptance.
- Do not introduce camera tracking or claim finger-count recognition without an explicit scope change.

## Communication

- Be concise and direct. State what changed, what was checked, and what remains unverified.
- Honor the user's physical test results over synthetic success.
- When a regression follows tuning, identify the change and repair the behavior before adding more features.

## README and public copy

- Write in Emanuel’s voice: plain, conversational, specific, and practical. Use natural explanations and concrete examples. Avoid poetic language, marketing metaphors, forced slang, and filler.
- Use affirmative sentences. Avoid contrastive constructions such as “not X, but Y,” “this isn’t X,” and negation-heavy disclaimers. State the behavior directly and describe remaining work plainly.
- Use the status wording **“This is an experiment in progress.”**
- Preserve factual limits through direct wording such as “accuracy testing is ongoing” or “position estimates remain experimental.” Keep claims grounded in observed behavior.
- Explain the mechanism step by step: speakers emit a steady tone (20 kHz by default); sound reflects off a moving hand; motion toward the audio hardware raises the reflected frequency and motion away lowers it; the microphone receives the reflections; the app detects frequency-change patterns and maps recognized gestures to commands.
- Explain sonar as sensing with sound and echoes, and the Doppler effect as the frequency shift used to detect movement. Describe sideways gestures as inferred from the signal.
- Keep the approved animated diagram at `assets/gesture-sensing.gif` directly beneath the README’s mechanism explanation. Preserve its schematic qualification.
- Keep the brief pets FYI: dogs and cats can hear the default 20 kHz frequency; use Sonar away from pets and stop if they seem uncomfortable. Preserve the hearing-range source and the statement that pet safety and sound levels still need evaluation.
- Credit SoundWave and its researchers in the inspiration section. Preserve separate rights and attribution for bundled media.
- Link “contact Emanuel” to `https://x.com/emanperez28`.

## Bundled demo assets

- The user explicitly approved including the SoundWave PDF and Yoda image. Keep their attribution and separate-license notes; do not describe either as MIT-licensed.
- The build uses `assets/paper/SoundWave.pdf` by default, with `SONAR_PAPER_PATH` as an optional override.
