# mac_tap_detector

A Flutter plugin for **macOS only** that detects physical tap / impact events on the MacBook chassis by analysing built-in microphone input in native Swift.

This is **not** a speech recognition feature. It specifically targets short, impulsive, percussive events (chassis tap, desk knock) while filtering out speech, keyboard typing, ambient noise, fan hum, and sustained sounds.

---

## Features

- Real-time microphone analysis via `AVAudioEngine`
- Multi-condition impulse detection:
  - Adaptive noise floor (rolling baseline)
  - Sudden attack detection
  - Fast decay check
  - Spectral / frequency analysis (FFT-based)
  - Speech-like continuity rejection
  - Cooldown guard
- Clean Dart API with `Stream<TapDetectionEvent>`
- Configurable with sensible defaults
- Sound playback from bundled assets

---

## Installation

```yaml
dependencies:
  mac_tap_detector:
    path: ../mac_tap_detector   # adjust to your path / git reference
```

### Microphone permission (required)

Add to your macOS `Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Used to detect physical taps on the device chassis.</string>
```

---

## Quick start

```dart
import 'package:mac_tap_detector/mac_tap_detector.dart';

// 1. Ask for permission
final status = await MacTapDetector.requestMicrophonePermission();
if (status != MicrophonePermissionStatus.granted) return;

// 2. Start listening with default config
await MacTapDetector.startListening();

// 3. React to events
MacTapDetector.events.listen((event) {
  print('Tap! amplitude=${event.amplitude}');
});

// 4. Stop when done
await MacTapDetector.stopListening();
```

---

## API reference

### `MacTapDetector`

| Method | Description |
|--------|-------------|
| `startListening([TapDetectorConfig?])` | Start the audio engine. Throws `PlatformException` if permission not granted. |
| `stopListening()` | Stop detection and release audio resources. |
| `updateConfig(TapDetectorConfig)` | Hot-update config while running. |
| `requestMicrophonePermission()` | Prompt for microphone access. |
| `getPermissionStatus()` | Query current permission without prompting. |
| `events` | `Stream<TapDetectionEvent>` broadcast stream. |
| `playSound(assetPath, {loop, volume})` | Play a bundled audio asset. |
| `stopSound()` | Stop currently playing sound. |

### `TapDetectionEvent`

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Always `"tap"` |
| `amplitude` | `double` | Peak RMS amplitude (0–1) |
| `peakToBaselineRatio` | `double` | Peak / noise floor ratio |
| `attackTimeMs` | `double` | Time from onset to peak (ms) |
| `decayTimeMs` | `double` | Time from peak to decay threshold (ms) |
| `eventDurationMs` | `double` | Total energetic duration (ms) |
| `highFreqRatio` | `double` | Fraction of energy in upper spectrum |
| `speechContinuityScore` | `double` | Speech-band energy ratio (higher = more speech-like) |
| `timestamp` | `int` | Unix timestamp in ms |

---

## Configuration

All parameters have sensible defaults. Pass a `TapDetectorConfig` to `startListening` or `updateConfig`.

```dart
final config = TapDetectorConfig(
  threshold: 0.05,
  cooldownMs: 300,
  adaptiveNoiseFloorEnabled: true,
  baselineMultiplier: 4.0,
  minimumAbsoluteThreshold: 0.03,
  attackMsMax: 15,
  minPeakToBaselineRatio: 3.0,
  decayMsMax: 80,
  minHighFreqRatio: 0.25,
  maxSpeechContinuityScore: 0.35,
  continuityRejectionEnabled: true,
  enableDebugLogs: false,
);
```

### Full parameter reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `threshold` | `0.05` | Static minimum RMS threshold (hard floor) |
| `cooldownMs` | `300` | Quiet period after a trigger (ms) |
| `bufferSize` | `1024` | Audio tap buffer size in samples |
| `enableDebugLogs` | `false` | Print verbose native logs to console |
| `adaptiveNoiseFloorEnabled` | `true` | Track rolling baseline instead of static threshold |
| `noiseFloorWindowMs` | `300` | Rolling baseline window size (ms) |
| `baselineMultiplier` | `4.0` | Dynamic threshold = baseline × multiplier |
| `minimumAbsoluteThreshold` | `0.03` | Absolute lower bound for dynamic threshold |
| `attackMsMax` | `15` | Max time from onset to peak (ms). Slower → rejected |
| `minAttackDelta` | `0.02` | Minimum amplitude rise at onset |
| `minPeakToBaselineRatio` | `3.0` | Peak must be this many × above baseline |
| `decayMsMax` | `80` | Max time from peak to decay point (ms) |
| `maxEventDurationMs` | `120` | Hard event duration cutoff (ms) |
| `peakDropRatio` | `0.3` | Fraction of peak that defines "decayed" |
| `speechBandWeight` | `1.0` | Weight on speech-band energy in scoring |
| `highFrequencyWeight` | `1.0` | Weight on high-frequency energy |
| `minHighFreqRatio` | `0.25` | Minimum high-freq / total energy ratio |
| `speechContinuityWindowMs` | `200` | Window for consecutive-hot-frame counting (ms) |
| `maxConsecutiveHotFrames` | `4` | Max back-to-back hot frames before rejection |
| `maxSpeechContinuityScore` | `0.35` | Max speech-band score before rejection (0–1) |
| `continuityRejectionEnabled` | `true` | Enable/disable continuity rejection stage |

---

## Tuning guide

### Fewer false positives (stricter)

These changes reduce triggers but may miss softer taps:

```
minimumAbsoluteThreshold  ↑  (e.g. 0.03 → 0.06)
minPeakToBaselineRatio    ↑  (e.g. 3.0  → 5.0)
attackMsMax               ↓  (e.g. 15   → 8)
decayMsMax                ↓  (e.g. 80   → 40)
minHighFreqRatio          ↑  (e.g. 0.25 → 0.40)
maxSpeechContinuityScore  ↓  (e.g. 0.35 → 0.20)
maxConsecutiveHotFrames   ↓  (e.g. 4    → 2)
cooldownMs                ↑  (e.g. 300  → 600)
```

### Higher sensitivity (more permissive)

These changes catch softer taps but may increase false positives:

```
minimumAbsoluteThreshold  ↓  (e.g. 0.03 → 0.015)
baselineMultiplier        ↓  (e.g. 4.0  → 2.5)
minPeakToBaselineRatio    ↓  (e.g. 3.0  → 2.0)
attackMsMax               ↑  (e.g. 15   → 25)
decayMsMax                ↑  (e.g. 80   → 120)
minHighFreqRatio          ↓  (e.g. 0.25 → 0.15)
cooldownMs                ↓  (e.g. 300  → 150)
```

### Suppress speech triggers specifically

```
maxSpeechContinuityScore  ↓  (stricter speech rejection)
continuityRejectionEnabled = true
maxConsecutiveHotFrames   ↓
speechBandWeight          ↑  (penalise speech band energy more)
```

---

## Sound playback

Place `.wav` or `.mp3` files in your Flutter `assets/sounds/` folder and declare them in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/sounds/
```

Then play on detection:

```dart
MacTapDetector.events.listen((event) async {
  await MacTapDetector.playSound('assets/sounds/tap.wav', volume: 0.8);
});
```

---

## Detection design summary

```
Audio buffer
    │
    ▼
RMS per frame
    │
    ▼
Update rolling noise floor (25th-percentile of recent history)
    │
    ▼
Dynamic threshold = max(baseline × multiplier, minimumAbsoluteThreshold)
    │
    ├─ below threshold → IDLE
    │
    └─ above threshold → state machine: RISING → PEAK → DECAYING
                              │
                              ▼ (on decay complete)
                         Evaluate candidate:
                           • attack speed check
                           • decay speed check
                           • duration check
                           • FFT high-freq ratio check
                           • speech continuity score check
                           • consecutive hot frames check
                           • cooldown check
                              │
                         All pass → emit TapDetectionEvent
```

---

## File structure

```
mac_tap_detector/
├── lib/
│   └── mac_tap_detector.dart          ← Dart API
├── macos/
│   ├── Classes/
│   │   └── MacTapDetectorPlugin.swift ← Native Swift implementation
│   └── mac_tap_detector.podspec
├── example/
│   ├── lib/
│   │   └── main.dart                  ← Example app
│   ├── macos/
│   │   └── Runner/
│   │       └── Info.plist             ← NSMicrophoneUsageDescription
│   ├── assets/sounds/                 ← Put .wav/.mp3 files here
│   └── pubspec.yaml
├── pubspec.yaml
└── README.md
```

---

## Platform support

| Platform | Support |
|----------|---------|
| macOS    | ✅ |
| iOS      | ✗ |
| Android  | ✗ |
| Windows  | ✗ |
| Linux    | ✗ |
| Web      | ✗ |
