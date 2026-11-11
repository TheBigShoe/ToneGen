# Audio Engine

Everything about the DSP path. If you're touching `Engine/`, read this first.

## Engine Setup

```swift
final class ToneEngine {
    private var engine: AVAudioEngine
    private var sourceNode: AVAudioSourceNode
    private let renderer: ToneRenderer       // one instance for the app's lifetime
    private var format: AVAudioFormat        // stereo float32 at the hardware rate
    private(set) var sampleRate: Double

    private static func attachSource(renderer: ToneRenderer,
                                     format: AVAudioFormat,
                                     to engine: AVAudioEngine) -> AVAudioSourceNode {
        let node = AVAudioSourceNode(format: format) { silence, _, frameCount, abl in
            renderer.render(frames: Int(frameCount), buffers: abl, silence: silence)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        return node
    }
}
```

The closure captures `renderer` strongly (it's a class, owned solely by
`ToneEngine`, which outlives the closure). Do not capture `self` in the render
closure.

## Sample Rate

The generator runs at the **hardware output rate**, not a fixed 48 kHz.
Otherwise the main mixer would resample a precision test tone whenever the
route runs at 44.1 kHz (Bluetooth) or 96 kHz (USB interface).

The rate is resolved by `ToneEngine.resolveSampleRate`:
`engine.outputNode.outputFormat(forBus: 0).sampleRate`, else
`AVAudioSession.sampleRate`, else 48 kHz (either can report 0 before the
hardware is configured). It is re-read in `startHardware()` immediately before
every `engine.start()`, which covers launch, the restart after an
`AVAudioEngineConfigurationChange`, a start after the route changed while
stopped, and `rebuild()` after a media-services reset. If it differs from
`ToneEngine.sampleRate`, `followHardwareRate()`:

1. calls `engine.stop()` (synchronous — when it returns no render callback is
   running, and none can start before the `engine.start()` that follows on the
   same main thread);
2. detaches the old source node (its render format is fixed at creation);
3. calls `ToneRenderer.setSampleRate(_:)`;
4. attaches a new source node at the new rate, sharing the same renderer;
5. publishes the rate through `onSampleRateChange` (the header label).

Because the renderer is only mutated while no callback can run, the render
path gains no lock, atomic or flag. `ToneRenderer.setSampleRate` is not
thread-safe and must never be called with the engine running.

**What carries over:** every smoother's current value and target (frequency,
amplitude, channel mute gates, phase offset, master gain), both phase
accumulators, crossfade progress (its remaining length is rescaled), noise
generator state, the last parameter snapshot, the `ParamsBridge`, and the
`scopeL`/`scopeR` ring buffers the meters captured at launch.

**What is retuned:** oscillator increments (`freq / sampleRate`), every
smoother coefficient (time constants stay fixed in milliseconds), and the
5 ms waveform crossfade length. PolyBLEP/BLAMP use `dt = freq / sampleRate`
per sample, so they follow automatically.

**What resets:** only the mute envelope's current value, to 0. The hardware
was stopped under a live signal; restarting at full level would step from
silence to mid-waveform, so the output fades back in over 5 ms instead.

**Not retuned:** the pink-noise filter (see Noise). The session's preferred
rate (48 kHz) stays as a preference only; the hardware decides.

## Audio Session

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [])
try session.setPreferredSampleRate(48_000)
try session.setPreferredIOBufferDuration(0.005)   // ~256 samples @ 48 kHz
try session.setActive(true)
```

The preferred rate is a request the hardware may ignore (AirPods run at
44.1 kHz or lower); the engine generates at whatever rate is granted — see
§ Sample Rate.

`.playback`, not `.playAndRecord` — this is a generator. Recording category
takes the input path and burns more battery for nothing.

## Threading — The Hard Rules

The render closure runs on a real-time audio thread. **Do not** in the render
path:

- Allocate (`Array`, `String`, `Data`, anything boxed)
- Take a lock that can block (`NSLock`, `os_unfair_lock` without `_trylock`)
- Call Objective-C runtime (`NSObject` methods, KVO, NotificationCenter)
- Access Swift dynamic dispatch hot paths (protocol witness tables on cold
  types are fine; chains of `any P` are not)
- Touch ARC-managed objects in tight loops (capture as `Unmanaged` if needed)
- Call `print`, `os_log`, or any I/O
- Do file I/O, networking, or anything that can take more than a few µs

**Do** in the render path:

- Read pre-allocated buffers
- Use `OSAllocatedUnfairLock.withLockIfAvailable` (returns `nil` on contention)
- Float math, integer math, simple branching
- Call non-virtual methods on `final` classes / structs

The whole render call must complete in well under one buffer's worth of time.
At 48 kHz with a 256-frame buffer that's 5.3 ms of headroom — but in practice
you want to finish in under 1 ms to leave room for everything else iOS does.

## Phase Accumulator

Per channel:

```swift
struct PhaseOscillator {
    var phase: Float = 0           // [0, 1)
    var sampleRate: Float

    @inline(__always)
    mutating func step(frequency: Float) -> Float {
        let inc = frequency / sampleRate
        phase += inc
        while phase >= 1 { phase -= 1 }
        while phase < 0  { phase += 1 }
        return phase
    }
}
```

Why `[0, 1)` instead of `[0, 2π)`? It keeps the math identical for all
waveforms and avoids one multiply in the inner loop for non-sine waveforms.
For sine, multiply by `2π` once at the call site.

**Do not** wrap with `truncatingRemainder` / `fmod` — they're slower and can
return negative values. The two-while-loop wrap is exact and branch-predictor
friendly because in steady state we wrap exactly once per cycle.

## User-Facing Phase Knob

The `phase` parameter the user sees is an *output offset*, not a write to the
accumulator. This means changing the phase knob doesn't disrupt continuity:

```swift
let p = osc.step(frequency: smoothedFreq)
let offset = phaseSmoother.next()              // [0, 1)
let pOffset = p + offset >= 1 ? p + offset - 1 : p + offset
let sample = waveform(pOffset)
```

The phase parameter is also smoothed. Without smoothing, dragging the phase
slider produces audible zipper noise.

The offset lives on a circle (1 ≡ 0), so it uses `PhaseSmoother`, not the
plain `Smoother`. A linear smoother would take 0.95 → 0.05 as a −0.9 move and
sweep through 0.5 — briefly putting the channel in anti-phase. `PhaseSmoother`
computes the signed shortest distance (`delta -= delta.rounded()`, so it is in
[−0.5, 0.5]), steps along it, and re-wraps its state into [0, 1) every sample
so it cannot drift unbounded. The UI range stays 0…1.

## Waveform Algorithms

All take `t ∈ [0, 1)` and return a value in `[-1, 1]`.

### Sine

```swift
@inline(__always)
func sine(_ t: Float) -> Float {
    return sinf(2 * .pi * t)
}
```

If `sinf` shows up as a hot spot in Time Profiler, swap to a small lookup
table with linear interpolation (1024 entries is plenty for 90 dB SNR). For
v1, `sinf` is fast enough on every device we target.

### Square (naive)

```swift
@inline(__always)
func squareNaive(_ t: Float) -> Float {
    return t < 0.5 ? 1 : -1
}
```

This aliases badly above ~3 kHz. Use `squareBLEP` in production (below).

### Saw (naive)

```swift
@inline(__always)
func sawNaive(_ t: Float) -> Float {
    return 2 * t - 1
}
```

Same aliasing problem.

### Triangle

```swift
@inline(__always)
func triangle(_ t: Float) -> Float {
    return t < 0.5 ? (4 * t - 1) : (3 - 4 * t)
}
```

That is the naive shape (−1 at t=0, +1 at t=0.5). Its aliasing is milder than
square's (harmonics fall off as 1/n²) but still clearly audible above a few
kHz, so production uses `triangleBLAMP` (see below).

### Noise

White via xorshift32 — fast, no allocation, no Swift overhead:

```swift
struct WhiteNoise {
    var state: UInt32 = 0x1234_5678
    @inline(__always) mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        // map UInt32 → Float in [-1, 1)
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}
```

Pink via Paul Kellet's economy filter (six biquads added together — close
enough to true 1/f for instrument use):

```swift
struct PinkNoise {
    var b0: Float = 0, b1: Float = 0, b2: Float = 0
    var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    var white = WhiteNoise()

    @inline(__always) mutating func next() -> Float {
        let w = white.next()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.11      // normalize to roughly [-1, 1]
    }
}
```

The Kellet coefficients are fixed (fitted at 44.1 kHz) and are not retuned on
a rate change. Every pole frequency scales with the rate, so the −3 dB/octave
band's low edge sits near 9 Hz at 44.1 kHz, ~10 Hz at 48 kHz and ~20 Hz at
96 kHz; the upper edge only moves up. 20 Hz–20 kHz stays pink at every rate;
below 20 Hz at 88.2/96 kHz the spectrum flattens slightly. Accepted for v1.

L and R noise generators have **separate seeds** — otherwise the noise is
correlated and stereo-mono behavior gets weird.

### Waveform switching

Changing a channel's waveform mid-playback crossfades linearly from the old
waveform to the new one over 5 ms (`WaveformCrossfade`, one per channel).
During the fade both waveforms are evaluated at the same offset phase and
blended; a change requested mid-fade waits for the current fade to finish and
then starts a new one, so the blend weight never jumps. Both phase
accumulators still step every sample regardless of waveform — a channel that
detours through noise comes back phase-locked to the other.

When the output is fully gated (transport paused or the channel muted) there
is nothing to click, so the change applies immediately.

## Antialiasing — PolyBLEP

For square and saw, subtract a band-limited step (PolyBLEP) at each
discontinuity. Triangle uses the integrated form, PolyBLAMP (below). The function:

```swift
@inline(__always)
func polyBlep(_ t: Float, dt: Float) -> Float {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    } else {
        return 0
    }
}
```

`dt = freq / sampleRate` (i.e. the phase increment).

### Saw with PolyBLEP

```swift
let raw  = 2 * t - 1
let corr = polyBlep(t, dt: dt)
return raw - corr
```

### Square with PolyBLEP

Square has two discontinuities per cycle (at t=0 going up, t=0.5 going down):

```swift
let raw  = t < 0.5 ? Float(1) : -1
var corr = polyBlep(t, dt: dt)
let t2   = t + 0.5 < 1 ? t + 0.5 : t - 0.5    // shifted by half-cycle
corr    -= polyBlep(t2, dt: dt)
return raw + corr
```

Below ~1 kHz, PolyBLEP and naive sound identical. Above 5 kHz, naive square
buzzes audibly; PolyBLEP is clean to Nyquist.

### Triangle with PolyBLAMP

The triangle has no jumps, only corners where the slope flips by ±8 per cycle
(±8·dt per sample). PolyBLAMP — the integral of the PolyBLEP residual, i.e.
the same 2-sample kernel — rounds each corner:

```swift
@inline(__always)
func polyBlamp(_ t: Float, dt: Float) -> Float {
    if t < dt {
        let x = 1 - t / dt
        return x * x * x / 6
    } else if t > 1 - dt {
        let x = 1 + (t - 1) / dt
        return x * x * x / 6
    } else {
        return 0
    }
}

let naive = t < 0.5 ? 4 * t - 1 : 3 - 4 * t
let t2    = t + 0.5 < 1 ? t + 0.5 : t - 0.5
let tri   = (naive + 8 * dt * (polyBlamp(t, dt: dt) - polyBlamp(t2, dt: dt)))
            * blepDroopCompensation(dt: dt)
```

The correction is symmetric about each corner, so it is zero-phase: the
band-limited triangle keeps the naive triangle's phase exactly (no residual
offset; its fundamental lags the sine by a quarter cycle, as it always has)
and has no DC offset.

**Droop compensation.** PolyBLEP/BLAMP act like convolving the ideal waveform
with a 2-sample triangular kernel, whose response is sinc²(f/fs) — −1.3 dB at
10 kHz and −5.3 dB at 20 kHz (48 kHz). For a test-tone generator the level
must not depend on frequency, so the waveforms are multiplied by
`1 / sinc²(dt)` (`blepDroopCompensation`):

- **Triangle** — fundamental within 0.1 dB of an ideal triangle's (8/π²) from
  20 Hz to 20 kHz at 44.1 and 48 kHz; peaks stay ≤ 1 and settle at
  8/π² ≈ 0.81 once only the fundamental is below Nyquist.
- **Saw** — fundamental within 0.1 dB of an ideal saw's (2/π) across the
  band; peaks stay ≤ 1.
- **Square** — only partly compensated. An ideal square's fundamental is 4/π
  (+2.1 dB) above its ±1 peak, so a level-true square would exceed full scale
  once its harmonics pass Nyquist. The gain is `max(1, π/4 · 1/sinc²(dt))`:
  the fundamental is never left below a full-scale sine. The square is
  therefore up to 2.1 dB under an ideal square in the top octaves (−1.3 dB at
  10 kHz, −2.1 dB from about 13.5 kHz up) instead of −5.3 dB at 20 kHz.

Measured alias suppression versus naive (48 kHz, `PolyBlepTests`): ≈ 48 dB
at 3 kHz from a 5 kHz tone, ≈ 38 dB at 7 kHz from 5 kHz, ≈ 68 dB at 1 kHz
from 7 kHz. Aliases folding from just above Nyquist are suppressed less
(≈ 20 dB for 7 kHz's 5th harmonic folding to 13 kHz) — a limit of the
2-point kernel.

## Parameter Smoothing

One-pole lowpass on every user-controllable parameter:

```swift
struct Smoother {
    private var current: Float
    var target: Float
    private var alpha: Float
    private let timeConstantMs: Float

    /// `timeConstantMs` ≈ 63% of the way to target.
    init(initial: Float, sampleRate: Float, timeConstantMs: Float) {
        current = initial
        target  = initial
        self.timeConstantMs = timeConstantMs
        alpha   = 1 - expf(-1000 / (timeConstantMs * sampleRate))
    }

    /// New rate, same time constant in ms; value and target are kept.
    mutating func setSampleRate(_ sampleRate: Float) { … }

    @inline(__always)
    mutating func next() -> Float {
        let delta = target - current
        let stepped = current + alpha * delta
        // Snap: see below.
        current = (abs(delta) <= 1e-6 || stepped == current) ? target : stepped
        return current
    }
}
```

Time constants:

| Parameter   | Time constant | Why                                            |
|-------------|---------------|------------------------------------------------|
| Frequency   | 20 ms         | Fast enough to feel responsive, slow enough not to chirp |
| Amplitude   | 10 ms (in dB) | Fast; users notice gain lag                    |
| Phase       | 30 ms         | Phase changes can shock; longer = gentler      |
| Master gain | 10 ms (in dB) | Same as channel amplitude                      |
| Channel mute| 10 ms (linear gate) | Even fade, ends in exact silence         |
| Mute env    | 5 ms          | Quick but click-free                           |

The smoother **snaps** onto its target once the remaining distance is ≤ 1e-6
or a step no longer changes the Float value. Without that a one-pole filter
stalls a few ulps short (at −120 one ulp is ≈ 8e-6), so a gate driven to 0
would never output true digital silence.

**Smooth frequency in the log domain.** Linear smoothing of frequency biases
the trajectory toward the lower freq. Smooth `log2(f)` and exponentiate back:

```swift
freqSmoother.target = log2f(targetHz)
let f = exp2f(freqSmoother.next())
let inc = f / sampleRate
```

This is one of the rules people get wrong; copy this pattern.

**Smooth amplitude in dBFS, convert per sample.** Channel amplitude and master
gain smoothers hold dBFS (targets clamped to the −120 dB floor). Each sample
converts the smoothed value to a linear factor:

```swift
ampSmoother.target = max(amplitudeDbfs, -120)
let gain = dbToGain(ampSmoother.next())   // exp2f(dB · log₂10/20) ≡ pow(10, dB/20)
                                          // exactly 0 at or below −120 dB
```

Smoothing the linear factor instead would make a −12 → −48 dB drag spend most
of its time near the top of the range and then collapse at the end.

**Mute is a gate, not a level.** Channel mute does not drive the dB smoother
to the floor: a dB-domain one-pole heading 100+ dB away loses most of the
level in its first millisecond, which ticks. Instead each channel has a
separate linear 0…1 gate smoother (10 ms) multiplied in alongside the gain.
It fades evenly and, because the smoother snaps, ends at exactly 0.

## Click-Free Start / Stop

Don't start/stop the AVAudioEngine on play/pause — that has its own latency
and side effects. Instead:

- Engine runs continuously after the first Play.
- `playing` is a smoothed gate (`muteEnv`) multiplied into the output.
- Pause sets target to 0; resume sets it back.

```swift
muteEnv.target = playing ? 1 : 0
let env = muteEnv.next()
out *= env
```

This produces a 5–10 ms fade and sounds clean.

For first launch, the engine isn't started until the user presses Play — no
need to spin the audio HW until the user has indicated intent.

## Output Metering

The renderer does no metering maths. After its sample loop it copies the
finished block into a per-channel `SampleRingBuffer` (4096 samples) with one
`withLockIfAvailable` per channel per buffer; on contention the samples are
still stored and become visible with the next block.

`MasterSection` reads the latest 512 samples per channel about 60 times a
second **only while playing**, computes their RMS on the main thread, and maps
it to a −60…0 dB bar. After stop the bars fall at 60 dB/s and the loop ends.
The meters show RMS, not peak.

## Glitch Hunt — Checklist

When something glitches, check in this order:

1. **Time Profiler at 1 ms**: any allocation in the render block?
2. **Smoother bypassed**: any parameter set without going through its smoother?
3. **Phase reset**: any code path that writes to `oscillator.phase` outside of
   `step()` and the wrap?
4. **Buffer size assumption**: any constant that assumes 256 frames? (The OS
   can hand you any size — handle 32, 64, 128, 256, 512, 1024.)
5. **Format mismatch**: source node, mixer, output node all on the same
   format? Run `engine.outputNode.outputFormat(forBus: 0)` and confirm.
6. **Route change**: did the user plug in headphones during playback? Engine
   needs to handle the route change notification.
7. **Sample rate change**: hardware can hand you 44.1 kHz on AirPods. Check
   `ToneEngine.sampleRate` (and the header label) against
   `engine.outputNode.outputFormat(forBus: 0).sampleRate`; they must match
   after every start. See § Sample Rate.

## Testing the Engine

Unit-testable pieces (run in `XCTest`, no real audio):

- `Smoother`: feed targets, verify settling time and final value
- `PhaseOscillator`: verify phase continuity, wrap correctness
- `polyBlep`: compare to a reference Python impl on a fixed input
- `WhiteNoise.next()`: histogram across N samples, verify mean ≈ 0, var ≈ 1/3
- Waveform purity: render N samples, FFT, verify expected harmonic structure
- Rate changes (`SampleRateChangeTests`): move a renderer 48 → 44.1 / 96 kHz,
  check frequency by zero crossings, carry-over of smoothed values, and
  smoother time constants at the new rate. The engine-side rate switch needs
  real hardware that changes rate; the simulator reports one rate only.

Render-block testing — drive the renderer directly with a fixed param
snapshot and inspect the output buffer. No `AVAudioEngine` involved. This is
the only way to test deterministically; doing it through the engine
introduces real-time noise.

## When to Reach for vDSP / Accelerate

Don't, for v1. Accelerate gets useful when:

- You need FFTs (e.g. spectrum view in v2)
- You're filtering long buffers (we're not)
- You're doing matrix math (we're not)

For per-sample work in stereo at 48 kHz, hand-written Swift with `@inline(__always)`
is plenty fast on every device we target. Profile first, optimize second.
