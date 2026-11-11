# ToneGen

A precision stereo test-tone generator for iOS. Independent L/R control over
waveform (sine, square, triangle, saw, noise), frequency (20 Hz – 20 kHz, log
scale), amplitude (dBFS), and phase. Built for audio engineers who want a
clean, fast bench tool on the device already in their pocket.

> Status: preparing for App Store release. See `docs/app-store-readiness.md`.

## Highlights

- Native SwiftUI + `AVAudioEngine` — no third-party DSP libs
- Click-free parameter changes via per-sample smoothing in the render block
- Sample-accurate phase relationship between L and R
- Background audio: keeps generating with the screen off

## Getting Started

Open `Tonegen.xcodeproj` in Xcode 26 or later and run on an iPhone or iPad
(iOS 17+). For development specifics, build commands, and conventions, see
`CLAUDE.md`.

## Documentation

- `CLAUDE.md` — entry point, critical rules, file layout
- `docs/architecture.md` — system architecture and data flow
- `docs/audio-engine.md` — DSP design (oscillators, antialiasing, smoothing)
- `docs/ui-design.md` — design system and component spec
- `docs/work-plan.md` — 18-package work breakdown
- `docs/conventions.md` — Swift style and repo conventions
- `mockup/ToneGenMockup.jsx` — interactive visual reference (React)

## Support

Questions and bug reports: [open an issue](https://github.com/TheBigShoe/ToneGen/issues).

## License

MIT — see [LICENSE](LICENSE).
