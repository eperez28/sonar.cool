# Per-Mac setup: local test build

1. Test one frequency at a time: 10-second sound check, user-prompted movement, then stopping. Offer 19/18 kHz after a failed 20 kHz trial, rather than making the user wait through every frequency first.
2. Reject weak signals, clipped input, missing audio, volume/route changes, or unwanted Scroll/Swipe/Zoom decisions while still. Keep detector thresholds unchanged.
3. Ask the user to lift/lower their palm, then stop. Keep the same analyzer and simulated detectors running across this transition; do not hide a failure with recalibration.
4. Save the selected frequency only after stillness, movement, and stopping pass. Preserve an aggregate-only, manually exported setup report, including failed candidates.
5. Offer setup on first launch and Recalibrate later. Cancellation, failure, or closing must stop audio and never save a success.
6. Test the rejection rules, lifecycle, preferences, signed build, and visible UI locally. Maxwell and Emanuel must physically test before a public release.

This measures basic acoustic sensing and simulated detector decisions. It does not prove every gesture or delivery to another app. Passing thresholds are provisional. Failure is a useful result, not evidence that a Mac is unsupported.

## Local implementation status

- Implemented and installed as 0.1.4 (9), signed with the existing identity. No release published.
- Regression checks reject the aggregate weak-tone and phantom-scrolling cases from the supplied reports. Existing gesture tests pass.
- First-launch presentation, postponing setup, Start requiring setup, live stillness instructions, and cancellation checked in the app.
- The move/stop hand trial and Maxwell's device trial remain physical acceptance checks. A passing build does not establish that his issue is fixed.

UX correction: A weak/unstable initial signal still proceeds to the movement and stopping prompts. Evaluate the entire trial afterward; never save a failed trial. Only audio/permission/route failures interrupt early.
