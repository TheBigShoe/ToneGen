# Audio Engine

Everything about the DSP path. If you're touching `Engine/`, read this first.

## Engine Setup

```swift
final class ToneEngine {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat       // 48 kHz, stereo, float32
    private var sourceNode: AVAudioSourceNode!
    private let renderer: ToneRenderer

    init(sampleRate: Double = 48_000) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: sampleRate,
                               channels: 2,
                               interleaved: false)!
        renderer = ToneRenderer(sampleRate: Float(sampleRate))
        sourceNode = AVAudioSourceNode(format: format) { [renderer] silence,
                                                          timestamp,
                                                          frameCount,
                                                          audioBufferList in
            renderer.render(frames: Int(frameCount),
                            buffers: audioBufferList,
                            silence: silence)
            return noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }
}
```

The closure captures `renderer` weakly via `[renderer]` (it's a class — so a
strong capture, but `ToneRenderer` is owned solely by `ToneEngine`, which
outlives the closure). Do not capture `self` in the render closure.

## Audio Session

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [])
try session.setPreferredSampleRate(48_000)
try session.setPreferredIOBufferDuration(0.005)   // ~256 samples @ 48 kHz
try session.setActive(true)
```

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

Triangle aliasing is mild (energy falls off as 1/n²). For v1 we ship the
naive form. If a user complains, integrate PolyBLAMP.

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

L and R noise generators have **separate seeds** — otherwise the noise is
correlated and stereo-mono behavior gets weird.

## Antialiasing — PolyBLEP

For square and saw, subtract a band-limited step (PolyBLEP) at each
discontinuity. The function:

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

## Parameter Smoothing

One-pole lowpass on every user-controllable parameter:

```swift
struct Smoother {
    private var current: Float
    var target: Float
    private let alpha: Float

    /// `timeConstantMs` ≈ 63% of the way to target.
    init(initial: Float, sampleRate: Float, timeConstantMs: Float) {
        current = initial
        target  = initial
        alpha   = 1 - expf(-1000 / (timeConstantMs * sampleRate))
    }

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

In the render block, track per-channel peak per buffer:

```swift
var peakL: Float = 0
var peakR: Float = 0
for n in 0..<frameCount {
    // ... write samples ...
    peakL = max(peakL, abs(sampleL))
    peakR = max(peakR, abs(sampleR))
}
publishedPeakL.store(peakL, order: .relaxed)   // via atomic float
publishedPeakR.store(peakR, order: .relaxed)
```

UI reads these via `CADisplayLink` and applies a peak-hold-with-decay curve
on its end (audio thread doesn't compute the decay; it's a display concern).

For atomic floats, use `OSAllocatedUnfairLock<Float>` is overkill — use
`std::atomic<float>` from `Synchronization` (Swift 5.10+) or a tiny C
shim. If the version constraint is iOS 17.0, the `Synchronization` module
isn't available; `OSAllocatedUnfairLock<Float>` is fine for the meter (the
lock is held for nanoseconds and the meter tolerates contention loss).

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
7. **Sample rate change**: hardware can hand you 44.1 kHz on AirPods. The
   engine should re-init smoothers when the sample rate changes.

## Testing the Engine

Unit-testable pieces (run in `XCTest`, no real audio):

- `Smoother`: feed targets, verify settling time and final value
- `PhaseOscillator`: verify phase continuity, wrap correctness
- `polyBlep`: compare to a reference Python impl on a fixed input
- `WhiteNoise.next()`: histogram across N samples, verify mean ≈ 0, var ≈ 1/3
- Waveform purity: render N samples, FFT, verify expected harmonic structure

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
