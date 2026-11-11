# ToneGen

A precision stereo test-tone generator for iOS. Independent L/R control over
waveform (sine, square, triangle, saw, noise), frequency (20 Hz – 20 kHz, log
scale), amplitude (dBFS), and phase. Built for audio engineers who want a
clean, fast bench tool on the device already in their pocket.

## Highlights

- Native SwiftUI + `AVAudioEngine` — no third-party DSP libs
- Click-free parameter changes via per-sample smoothing in the render block
- Sample-accurate phase relationship between L and R
- Background audio: keeps generating with the screen off, with play/pause on
  the lock screen and in Control Center
- Settings are remembered between launches; the app always starts silent

## Getting Started

Open `Tonegen.xcodeproj` in Xcode 26 or later and run on an iPhone or iPad
(iOS 17+). To run on a device, create `Config/Local.xcconfig` containing your
Apple team ID:

```
DEVELOPMENT_TEAM = YOURTEAMID
```

The project file is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); run `make generate` after
changing it. `make test` runs the unit tests.

## Using ToneGen

- Press the round button to start and stop generation.
- Choose **CH·L**, **CH·R**, or the link tab to edit one channel or both. On
  iPad the two channels sit side by side with a LINK / SPLIT switch.
- Pick a waveform, set the frequency with the slider, the step buttons or a
  preset, then set level and phase.
- Start with the volume low: sustained tones at high level can damage hearing
  and loudspeakers.

## Documentation

- `docs/architecture.md` — system architecture and data flow
- `docs/audio-engine.md` — DSP design (oscillators, antialiasing, smoothing)

## Support

Questions and bug reports: [open an issue](https://github.com/TheBigShoe/ToneGen/issues).

## License

MIT — see [LICENSE](LICENSE).
