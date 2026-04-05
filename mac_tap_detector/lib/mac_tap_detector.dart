import 'dart:async';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────
// Config model
// ─────────────────────────────────────────────────────────────

/// Full configuration for the tap detector.
///
/// All time values are in milliseconds unless noted.
class TapDetectorConfig {
  // ── Basic ──────────────────────────────────────────────────
  /// Static minimum RMS threshold (0.0 – 1.0). Acts as a hard floor even when
  /// adaptive noise floor is enabled.
  final double threshold;

  /// Minimum quiet period after a tap event fires. Prevents double-triggers.
  final int cooldownMs;

  /// Audio tap buffer size in samples (power of 2, e.g. 1024, 2048).
  final int bufferSize;

  /// Print verbose native logs.
  final bool enableDebugLogs;

  // ── Adaptive noise floor ───────────────────────────────────
  /// When true, the detector tracks a rolling baseline instead of using only
  /// the static [threshold].
  final bool adaptiveNoiseFloorEnabled;

  /// Duration of the rolling window used to estimate the noise floor.
  final int noiseFloorWindowMs;

  /// Dynamic threshold = baseline × [baselineMultiplier].
  final double baselineMultiplier;

  /// Absolute lower bound for the dynamic threshold even if the baseline is
  /// very low (quiet room).
  final double minimumAbsoluteThreshold;

  // ── Attack detection ───────────────────────────────────────
  /// Maximum time (ms) from onset to peak — events with a slower rise are
  /// rejected (speech-like).
  final int attackMsMax;

  /// Minimum RMS increase from the pre-attack baseline to the peak.
  final double minAttackDelta;

  /// Peak / baseline ratio required to count as an impulse.
  final double minPeakToBaselineRatio;

  // ── Decay detection ────────────────────────────────────────
  /// Maximum time (ms) from peak to energy dropping below [peakDropRatio]×peak.
  final int decayMsMax;

  /// Maximum total duration of the energetic region of an event.
  final int maxEventDurationMs;

  /// Fraction of peak at which the event is considered "over" for decay timing.
  final double peakDropRatio;

  // ── Spectral filtering ────────────────────────────────────
  /// Weight given to speech-band energy when scoring speech likelihood.
  final double speechBandWeight;

  /// Weight given to high-frequency energy when scoring transient likelihood.
  final double highFrequencyWeight;

  /// Minimum ratio of high-freq energy to total energy required to pass.
  final double minHighFreqRatio;

  // ── Continuity rejection ──────────────────────────────────
  /// Window over which "consecutive hot frames" are counted.
  final int speechContinuityWindowMs;

  /// Maximum number of back-to-back hot frames before the event is rejected.
  final int maxConsecutiveHotFrames;

  /// Score (0–1) above which the event is classified as speech-like and
  /// rejected.
  final double maxSpeechContinuityScore;

  /// Enable/disable the continuity rejection stage entirely.
  final bool continuityRejectionEnabled;

  const TapDetectorConfig({
    this.threshold = 0.05,
    this.cooldownMs = 300,
    this.bufferSize = 1024,
    this.enableDebugLogs = false,
    this.adaptiveNoiseFloorEnabled = true,
    this.noiseFloorWindowMs = 300,
    this.baselineMultiplier = 4.0,
    this.minimumAbsoluteThreshold = 0.03,
    this.attackMsMax = 15,
    this.minAttackDelta = 0.0,
    this.minPeakToBaselineRatio = 3.0,
    this.decayMsMax = 80,
    this.maxEventDurationMs = 120,
    this.peakDropRatio = 0.3,
    this.speechBandWeight = 1.0,
    this.highFrequencyWeight = 1.0,
    this.minHighFreqRatio = 0.0,
    this.speechContinuityWindowMs = 200,
    this.maxConsecutiveHotFrames = 4,
    this.maxSpeechContinuityScore = 0.30,
    this.continuityRejectionEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'threshold': threshold,
        'cooldownMs': cooldownMs,
        'bufferSize': bufferSize,
        'enableDebugLogs': enableDebugLogs,
        'adaptiveNoiseFloorEnabled': adaptiveNoiseFloorEnabled,
        'noiseFloorWindowMs': noiseFloorWindowMs,
        'baselineMultiplier': baselineMultiplier,
        'minimumAbsoluteThreshold': minimumAbsoluteThreshold,
        'attackMsMax': attackMsMax,
        'minAttackDelta': minAttackDelta,
        'minPeakToBaselineRatio': minPeakToBaselineRatio,
        'decayMsMax': decayMsMax,
        'maxEventDurationMs': maxEventDurationMs,
        'peakDropRatio': peakDropRatio,
        'speechBandWeight': speechBandWeight,
        'highFrequencyWeight': highFrequencyWeight,
        'minHighFreqRatio': minHighFreqRatio,
        'speechContinuityWindowMs': speechContinuityWindowMs,
        'maxConsecutiveHotFrames': maxConsecutiveHotFrames,
        'maxSpeechContinuityScore': maxSpeechContinuityScore,
        'continuityRejectionEnabled': continuityRejectionEnabled,
      };
}

// ─────────────────────────────────────────────────────────────
// Event model
// ─────────────────────────────────────────────────────────────

/// A tap / impact detection event emitted by the native layer.
class TapDetectionEvent {
  final String type;
  final double amplitude;
  final double peakToBaselineRatio;
  final double attackTimeMs;
  final double decayTimeMs;
  final double eventDurationMs;
  final double highFreqRatio;
  final double speechContinuityScore;
  final int timestamp;

  const TapDetectionEvent({
    required this.type,
    required this.amplitude,
    required this.peakToBaselineRatio,
    required this.attackTimeMs,
    required this.decayTimeMs,
    required this.eventDurationMs,
    required this.highFreqRatio,
    required this.speechContinuityScore,
    required this.timestamp,
  });

  factory TapDetectionEvent.fromMap(Map<dynamic, dynamic> map) {
    return TapDetectionEvent(
      type: map['type'] as String? ?? 'tap',
      amplitude: (map['amplitude'] as num?)?.toDouble() ?? 0.0,
      peakToBaselineRatio:
          (map['peakToBaselineRatio'] as num?)?.toDouble() ?? 0.0,
      attackTimeMs: (map['attackTimeMs'] as num?)?.toDouble() ?? 0.0,
      decayTimeMs: (map['decayTimeMs'] as num?)?.toDouble() ?? 0.0,
      eventDurationMs: (map['eventDurationMs'] as num?)?.toDouble() ?? 0.0,
      highFreqRatio: (map['highFreqRatio'] as num?)?.toDouble() ?? 0.0,
      speechContinuityScore:
          (map['speechContinuityScore'] as num?)?.toDouble() ?? 0.0,
      timestamp: (map['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  String toString() =>
      'TapDetectionEvent(amp=${amplitude.toStringAsFixed(3)}, '
      'p2b=${peakToBaselineRatio.toStringAsFixed(2)}, '
      'attack=${attackTimeMs.toStringAsFixed(1)}ms, '
      'decay=${decayTimeMs.toStringAsFixed(1)}ms, '
      'dur=${eventDurationMs.toStringAsFixed(1)}ms, '
      'hfr=${highFreqRatio.toStringAsFixed(2)}, '
      'scs=${speechContinuityScore.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────────────────────
// Permission status
// ─────────────────────────────────────────────────────────────

enum MicrophonePermissionStatus {
  granted,
  denied,
  notDetermined,
  restricted,
  unknown,
}

MicrophonePermissionStatus _parsePermission(String raw) {
  switch (raw) {
    case 'granted':
      return MicrophonePermissionStatus.granted;
    case 'denied':
      return MicrophonePermissionStatus.denied;
    case 'notDetermined':
      return MicrophonePermissionStatus.notDetermined;
    case 'restricted':
      return MicrophonePermissionStatus.restricted;
    default:
      return MicrophonePermissionStatus.unknown;
  }
}

// ─────────────────────────────────────────────────────────────
// Main API
// ─────────────────────────────────────────────────────────────

/// Flutter API for the macOS tap/impact detector plugin.
///
/// ```dart
/// await MacTapDetector.requestMicrophonePermission();
/// await MacTapDetector.startListening();
///
/// MacTapDetector.events.listen((event) {
///   print('Tap detected: $event');
/// });
///
/// // Later…
/// await MacTapDetector.stopListening();
/// ```
class MacTapDetector {
  MacTapDetector._();

  static const MethodChannel _method =
      MethodChannel('mac_tap_detector/methods');
  static const EventChannel _events =
      EventChannel('mac_tap_detector/events');

  static Stream<TapDetectionEvent>? _eventStream;

  /// Stream of [TapDetectionEvent]s emitted whenever a tap is detected.
  static Stream<TapDetectionEvent> get events {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((dynamic raw) =>
            TapDetectionEvent.fromMap(raw as Map<dynamic, dynamic>));
    return _eventStream!;
  }

  // ── Lifecycle ──────────────────────────────────────────────

  /// Start the audio engine and begin detecting taps.
  ///
  /// Throws a [PlatformException] if microphone permission has not been granted.
  static Future<void> startListening([TapDetectorConfig? config]) async {
    await _method.invokeMethod<void>(
      'startListening',
      config?.toMap(),
    );
  }

  /// Stop detection and release the audio engine.
  static Future<void> stopListening() async {
    await _method.invokeMethod<void>('stopListening');
  }

  /// Update the detection configuration while running.
  ///
  /// Call [startListening] first; parameters take effect immediately.
  static Future<void> updateConfig(TapDetectorConfig config) async {
    await _method.invokeMethod<void>('updateConfig', config.toMap());
  }

  // ── Permissions ───────────────────────────────────────────

  /// Prompt the user for microphone permission.
  ///
  /// Returns the resulting [MicrophonePermissionStatus].
  static Future<MicrophonePermissionStatus>
      requestMicrophonePermission() async {
    final result =
        await _method.invokeMethod<String>('requestMicrophonePermission');
    return _parsePermission(result ?? 'unknown');
  }

  /// Return the current microphone permission without prompting.
  static Future<MicrophonePermissionStatus> getPermissionStatus() async {
    final result =
        await _method.invokeMethod<String>('getPermissionStatus');
    return _parsePermission(result ?? 'unknown');
  }

  // ── Sound playback ────────────────────────────────────────

  /// Play a bundled sound asset.
  ///
  /// [assetPath] should be the Flutter asset key (e.g. `'assets/tap.wav'`).
  /// The native layer resolves it from the app bundle.
  static Future<void> playSound(
    String assetPath, {
    bool loop = false,
    double volume = 1.0,
  }) async {
    await _method.invokeMethod<void>('playSound', {
      'assetPath': assetPath,
      'loop': loop,
      'volume': volume,
    });
  }

  /// Stop any currently playing sound.
  static Future<void> stopSound() async {
    await _method.invokeMethod<void>('stopSound');
  }

  /// Play the macOS system alert beep (no asset file needed).
  static Future<void> playSystemBeep() async {
    await _method.invokeMethod<void>('playSystemBeep');
  }

  // ── Recording ─────────────────────────────────────────────

  /// Start recording from the microphone and save to Documents/TapSounds/<name>.m4a.
  /// Call [stopListening] first — TapDetector and AVAudioRecorder share the mic.
  static Future<void> startRecording(String name) async {
    await _method.invokeMethod<void>('startRecording', {'name': name});
  }

  /// Stop recording and return the absolute path of the saved file.
  /// Call [startListening] afterwards to resume tap detection.
  static Future<String?> stopRecording() async {
    return _method.invokeMethod<String>('stopRecording');
  }

  /// Return all recorded sound file paths, sorted newest first.
  static Future<List<String>> getSoundFiles() async {
    final raw = await _method.invokeMethod<List<dynamic>>('getSoundFiles');
    return (raw ?? []).cast<String>();
  }

  /// Permanently delete the sound file at [path].
  static Future<void> deleteSound(String path) async {
    await _method.invokeMethod<void>('deleteSound', {'path': path});
  }
}
