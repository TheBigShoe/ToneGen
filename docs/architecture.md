# Architecture

## System Overview

Three layers, one direction of data flow for parameter changes, one direction
for visualization data:

```
   ┌──────────────────────────────────────────────────────────┐
   │                          UI                              │
   │   SwiftUI views observe TonegenStore via @Observable     │
   │   User gestures → setters on TonegenStore                │
   └────────────────────┬─────────────────────────────────────┘
                        │  param targets (write through lock)
                        ▼
   ┌──────────────────────────────────────────────────────────┐
   │                       State                              │
   │   TonegenStore (main actor, @Observable)                 │
   │     ├─ master: MasterState                               │
   │     ├─ channels: (L: ChannelState, R: ChannelState)      │
   │     └─ link: Bool                                        │
   │   EngineParams (POD, lock-protected snapshot)            │
   └────────────────────┬─────────────────────────────────────┘
                        │  atomic snapshot read at buffer start
                        ▼
   ┌──────────────────────────────────────────────────────────┐
   │                      Engine                              │
   │   ToneEngine: AVAudioEngine + AVSourceNode               │
   │   ToneRenderer: per-sample DSP                           │
   │     ├─ PhaseOscillator × 2 (L, R)                        │
   │     ├─ Smoothers for freq, amp, phase, master            │
   │     └─ Output peak meter (atomic write back to UI)       │
   └────────────────────┬─────────────────────────────────────┘
                        │  ring buffer of recent samples
                        ▼
   ┌──────────────────────────────────────────────────────────┐
   │                 Visualization                            │
   │   OscilloscopeView reads ring buffer on CADisplayLink    │
   └──────────────────────────────────────────────────────────┘
```

## State Model

### `TonegenStore` (`State/TonegenStore.swift`)

The single owner of UI-visible state. `@Observable`, `@MainActor`. Views never
hold their own audio state.

```swift
@MainActor @Observable
final class TonegenStore {
    var master: MasterState
    var channels: (L: ChannelState, R: ChannelState)
    var link: Bool
    var activeChannel: ChannelID  // .L or .R

    // Computed convenience
    var activeState: ChannelState { ... }

    // Mutators (the only way state changes)
    func setFrequency(_ hz: Double, channel: ChannelID)
    func setAmplitude(_ dbfs: Double, channel: ChannelID)
    func setPhase(_ degrees: Double, channel: ChannelID)
    func setWaveform(_ wave: Waveform, channel: ChannelID)
    func setMute(_ muted: Bool, channel: ChannelID)
    func setMasterGain(_ dbfs: Double)
    func setLink(_ on: Bool)
    func togglePlaying()
    // ...
}
```

When `link == true`, mutators write to *both* channels. The store is the only
place this branching logic lives — views just call `setFrequency(_:channel:)`
on the active tab.

### `ChannelState` (`State/ChannelState.swift`)

Plain value type. dBFS in, dBFS out — no linear gains here.

```swift
struct ChannelState: Equatable {
    var waveform: Waveform        // .sine | .square | .triangle | .saw | .noise
    var frequency: Double         // Hz, [20, 20_000]
    var amplitude: Double         // dBFS, [-120, 0]
    var phase: Double             // degrees, [-180, 180]
    var muted: Bool
}

enum Waveform: String, CaseIterable, Sendable {
    case sine, square, triangle, saw, noise
}

enum ChannelID: Sendable { case L, R }
```

### `EngineParams` (`State/EngineParams.swift`)

The UI ↔ engine boundary. Plain old data, `Sendable`, fits in one cache line
where possible. This is the *snapshot* shape the renderer reads.

```swift
struct EngineParams: Sendable {
    var L: ChannelParams
    var R: ChannelParams
    var masterGainDb: Float        // dBFS
    var playing: Bool
}

struct ChannelParams: Sendable {
    var waveform: Waveform         // sample-and-hold; takes effect at next zero crossing where reasonable
    var frequencyHz: Float
    var amplitudeDb: Float
    var phaseDegrees: Float
    var muted: Bool
}
```

The store mirrors changes into `EngineParams` through the lock immediately on
every mutation. The renderer reads at the start of each render call.

## UI ↔ Engine Boundary

Use `OSAllocatedUnfairLock<EngineParams>` (iOS 16+). Two patterns:

**UI write (cheap, can block briefly):**
```swift
paramsLock.withLock { $0.L.frequencyHz = Float(newHz) }
```

**Renderer read (must not block):**
```swift
guard let snapshot = paramsLock.withLockIfAvailable({ $0 }) else {
    return lastSnapshot   // fall back; UI just lost a frame's worth of update
}
lastSnapshot = snapshot
```

The fallback is the key. UI contention is microseconds; the worst case is one
buffer (~5 ms) of stale parameters, which is inaudible.

> Do **not** introduce `swift-atomics` or any other dependency for this. The
> unfair lock pattern is sufficient for a tone generator and is the simplest
> correct option.

## Threading Model

| Thread / actor              | Lives                                     |
|-----------------------------|-------------------------------------------|
| MainActor                   | `TonegenStore`, all SwiftUI views         |
| Audio I/O thread            | `AVSourceNode` render block               |
| CADisplayLink               | Oscilloscope rendering (60/120 Hz)        |
| Background task             | (none in v1)                              |

Never call into the store from the audio thread. Never block on the audio
thread. Never `await` from the audio thread (it's not an async context).

## Audio Engine Graph

```
  ToneRenderer (AVSourceNode)
        │
        ▼
  [stereo float32, 48 kHz]
        │
        ▼
  AVAudioEngine.mainMixerNode
        │
        ▼
  AVAudioEngine.outputNode
```

Single source node, stereo output, no taps in production (a tap is added on
`outputNode` in debug builds for the scope ring buffer; see Visualization).
No mixer between source and main mixer — we do our own gain in the renderer
to keep parameter smoothing cohesive.

## Per-Sample Render Loop

Inside `ToneRenderer.render(...)`, per buffer:

1. Snapshot params (lock-or-fallback).
2. Push new targets into smoothers (freq, amp, phase, master).
3. For each sample `n` in `0..<frameCount`:
   - Advance both phase accumulators by their *currently smoothed* `phaseInc`.
   - Sample each waveform at `(phase + phaseOffset)`.
   - Apply per-channel amplitude (smoothed dBFS → linear).
   - Apply master gain (smoothed).
   - Apply mute (instantaneous, but multiplied by smoothed mute envelope to avoid clicks; see audio-engine.md).
   - Write L, R to the audio buffer.
4. Update peak meters; publish via atomic write back to UI.
5. Push the same samples into the scope ring buffer.

## Visualization Data Flow

The scope shows the *actual* generated signal, not a re-synthesis from
parameters. This way the user sees exactly what's coming out — including any
mute envelope, smoothing transient, or eventual antialiasing artifact.

The renderer writes into a `SampleRingBuffer` (lock-free SPSC, fixed size,
~50 ms of samples at 48 kHz = 2400 frames per channel = ~20 KB). The
`OscilloscopeView` reads from a `CADisplayLink` callback on the main thread,
copies the latest window into a local buffer, and draws.

If the scope draws stale frames during heavy UI churn — that's fine. It's a
display, not a measurement instrument.

## Lifecycle

| Event                       | What happens                                         |
|-----------------------------|------------------------------------------------------|
| App launch                  | Audio session configured; engine prepared but stopped |
| User taps Play              | `engine.start()`; `EngineParams.playing = true`      |
| User taps Pause             | `playing = false`; engine continues running, mute env ramps to 0 |
| App backgrounded (playing)  | Continues — background audio entitlement             |
| App backgrounded (stopped)  | Engine left running but silent; no battery cost beyond idle |
| Interruption (call, alarm)  | `engine.pause()`, restart on resume                  |
| Route change (headphones)   | Engine resumes automatically; UI reflects new device |
| App terminate               | `engine.stop()`, session deactivated                 |

Audio session configuration is **once** at launch. Don't reconfigure on play.

## What Lives Where — Decision Heuristic

When you're not sure where a piece of code belongs:

- Does it produce or transform audio samples? → `Engine/`
- Does the user see or interact with it? → `UI/`
- Is it the canonical value of something? → `State/`
- Is it a pure math function? → `Helpers/`

If a piece of logic feels like it belongs in two places, it's almost always a
sign that a small helper in `Helpers/` should be extracted.
