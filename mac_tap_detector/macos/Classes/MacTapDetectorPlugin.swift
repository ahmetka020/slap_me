import AVFoundation
import Accelerate
import FlutterMacOS

// ─────────────────────────────────────────────────────────────
// MARK: - Plugin entry point
// ─────────────────────────────────────────────────────────────

public class MacTapDetectorPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private let detector = TapDetector()
    private var soundPlayer: SoundPlayer?
    private var soundRecorder: SoundRecorder?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MacTapDetectorPlugin()

        let methodCh = FlutterMethodChannel(
            name: "mac_tap_detector/methods",
            binaryMessenger: registrar.messenger
        )
        let eventCh = FlutterEventChannel(
            name: "mac_tap_detector/events",
            binaryMessenger: registrar.messenger
        )

        instance.methodChannel = methodCh
        instance.eventChannel = eventCh
        instance.soundPlayer  = SoundPlayer()
        instance.soundRecorder = SoundRecorder()

        registrar.addMethodCallDelegate(instance, channel: methodCh)
        eventCh.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startListening":
            startListening(args: call.arguments as? [String: Any], result: result)
        case "stopListening":
            detector.stop()
            result(nil)
        case "updateConfig":
            if let args = call.arguments as? [String: Any] {
                detector.updateConfig(TapDetectorConfig(from: args))
            }
            result(nil)
        case "requestMicrophonePermission":
            requestPermission(result: result)
        case "getPermissionStatus":
            result(permissionStatusString())
        case "playSound":
            handlePlaySound(args: call.arguments as? [String: Any], result: result)
        case "stopSound":
            soundPlayer?.stop()
            result(nil)
        case "playSystemBeep":
            NSSound.beep()
            result(nil)
        case "startRecording":
            handleStartRecording(args: call.arguments as? [String: Any], result: result)
        case "stopRecording":
            result(soundRecorder?.stopRecording())
        case "getSoundFiles":
            result(soundRecorder?.getSoundFiles() ?? [])
        case "deleteSound":
            handleDeleteSound(args: call.arguments as? [String: Any], result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Start / stop ─────────────────────────────────────────

    private func startListening(args: [String: Any]?, result: @escaping FlutterResult) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            result(FlutterError(
                code: "PERMISSION_DENIED",
                message: "Microphone permission is not granted. Call requestMicrophonePermission() first.",
                details: nil
            ))
            return
        }

        if let args = args {
            detector.updateConfig(TapDetectorConfig(from: args))
        }

        detector.onTapDetected = { [weak self] event in
            DispatchQueue.main.async {
                self?.eventSink?(event.toFlutterMap())
            }
        }

        do {
            try detector.start()
            result(nil)
        } catch {
            result(FlutterError(
                code: "START_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    // ── Permissions ──────────────────────────────────────────

    private func requestPermission(result: @escaping FlutterResult) {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        if current == .authorized {
            result("granted")
            return
        }
        if current == .denied || current == .restricted {
            result(permissionStatusString())
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                result(granted ? "granted" : "denied")
            }
        }
    }

    private func permissionStatusString() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:   return "granted"
        case .denied:       return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted:   return "restricted"
        @unknown default:   return "unknown"
        }
    }

    // ── Sound ────────────────────────────────────────────────

    private func handleStartRecording(args: [String: Any]?, result: @escaping FlutterResult) {
        guard let raw = args?["name"] as? String, !raw.isEmpty else {
            result(FlutterError(code: "INVALID_ARGS", message: "name is required", details: nil))
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = raw.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        do {
            try soundRecorder?.startRecording(name: safe)
            result(nil)
        } catch {
            result(FlutterError(code: "RECORD_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func handleDeleteSound(args: [String: Any]?, result: @escaping FlutterResult) {
        guard let path = args?["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "path is required", details: nil))
            return
        }
        let ok = soundRecorder?.deleteSound(path: path) ?? false
        result(ok)
    }

    private func handlePlaySound(args: [String: Any]?, result: @escaping FlutterResult) {
        guard let args = args,
              let assetPath = args["assetPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "assetPath is required", details: nil))
            return
        }
        let loop   = args["loop"]   as? Bool   ?? false
        let volume = args["volume"] as? Double ?? 1.0

        do {
            try soundPlayer?.play(assetPath: assetPath, loop: loop, volume: Float(volume))
            result(nil)
        } catch {
            result(FlutterError(code: "PLAY_FAILED", message: error.localizedDescription, details: nil))
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - FlutterStreamHandler
// ─────────────────────────────────────────────────────────────

extension MacTapDetectorPlugin: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - TapDetectorConfig
// ─────────────────────────────────────────────────────────────

struct TapDetectorConfig {
    var threshold: Float                  = 0.05
    var cooldownMs: Int                   = 300
    var bufferSize: Int                   = 1024
    var enableDebugLogs: Bool             = false

    // Adaptive noise floor
    var adaptiveNoiseFloorEnabled: Bool   = true
    var noiseFloorWindowMs: Int           = 300
    var baselineMultiplier: Float         = 4.0
    var minimumAbsoluteThreshold: Float   = 0.03

    // Attack
    var attackMsMax: Int                  = 15
    var minAttackDelta: Float             = 0.0
    var minPeakToBaselineRatio: Float     = 3.0

    // Decay
    var decayMsMax: Int                   = 80
    var maxEventDurationMs: Int           = 300
    var peakDropRatio: Float              = 0.3

    // Spectral
    var speechBandWeight: Float           = 1.0
    var highFrequencyWeight: Float        = 1.0
    var minHighFreqRatio: Float           = 0.0

    // Continuity
    var speechContinuityWindowMs: Int     = 500
    var maxConsecutiveHotFrames: Int      = 5
    var maxSpeechContinuityScore: Float   = 0.30
    var continuityRejectionEnabled: Bool  = true

    init() {}

    init(from map: [String: Any]) {
        threshold                   = map.f("threshold")              ?? threshold
        cooldownMs                  = map.i("cooldownMs")             ?? cooldownMs
        bufferSize                  = map.i("bufferSize")             ?? bufferSize
        enableDebugLogs             = map.b("enableDebugLogs")        ?? enableDebugLogs
        adaptiveNoiseFloorEnabled   = map.b("adaptiveNoiseFloorEnabled") ?? adaptiveNoiseFloorEnabled
        noiseFloorWindowMs          = map.i("noiseFloorWindowMs")     ?? noiseFloorWindowMs
        baselineMultiplier          = map.f("baselineMultiplier")     ?? baselineMultiplier
        minimumAbsoluteThreshold    = map.f("minimumAbsoluteThreshold") ?? minimumAbsoluteThreshold
        attackMsMax                 = map.i("attackMsMax")            ?? attackMsMax
        minAttackDelta              = map.f("minAttackDelta")         ?? minAttackDelta
        minPeakToBaselineRatio      = map.f("minPeakToBaselineRatio") ?? minPeakToBaselineRatio
        decayMsMax                  = map.i("decayMsMax")             ?? decayMsMax
        maxEventDurationMs          = map.i("maxEventDurationMs")     ?? maxEventDurationMs
        peakDropRatio               = map.f("peakDropRatio")          ?? peakDropRatio
        speechBandWeight            = map.f("speechBandWeight")       ?? speechBandWeight
        highFrequencyWeight         = map.f("highFrequencyWeight")    ?? highFrequencyWeight
        minHighFreqRatio            = map.f("minHighFreqRatio")       ?? minHighFreqRatio
        speechContinuityWindowMs    = map.i("speechContinuityWindowMs") ?? speechContinuityWindowMs
        maxConsecutiveHotFrames     = map.i("maxConsecutiveHotFrames") ?? maxConsecutiveHotFrames
        maxSpeechContinuityScore    = map.f("maxSpeechContinuityScore") ?? maxSpeechContinuityScore
        continuityRejectionEnabled  = map.b("continuityRejectionEnabled") ?? continuityRejectionEnabled
    }
}

// Convenience extensions for safely pulling typed values from a map
private extension Dictionary where Key == String, Value == Any {
    func f(_ key: String) -> Float?  { (self[key] as? NSNumber).map { Float(truncating: $0) } }
    func i(_ key: String) -> Int?    { (self[key] as? NSNumber).map { Int(truncating: $0) } }
    func b(_ key: String) -> Bool?   { self[key] as? Bool }
}

// ─────────────────────────────────────────────────────────────
// MARK: - TapDetectionEvent
// ─────────────────────────────────────────────────────────────

struct TapDetectionEvent {
    let amplitude: Float
    let peakToBaselineRatio: Float
    let attackTimeMs: Float
    let decayTimeMs: Float
    let eventDurationMs: Float
    let highFreqRatio: Float
    let speechContinuityScore: Float

    func toFlutterMap() -> [String: Any] {
        return [
            "type":                   "tap",
            "amplitude":              Double(amplitude),
            "peakToBaselineRatio":    Double(peakToBaselineRatio),
            "attackTimeMs":           Double(attackTimeMs),
            "decayTimeMs":            Double(decayTimeMs),
            "eventDurationMs":        Double(eventDurationMs),
            "highFreqRatio":          Double(highFreqRatio),
            "speechContinuityScore":  Double(speechContinuityScore),
            "timestamp":              Int64(Date().timeIntervalSince1970 * 1000),
        ]
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - TapDetector
// ─────────────────────────────────────────────────────────────

/// Core detection engine. Runs on a dedicated serial queue.
///
/// Detection pipeline per audio buffer:
///   1. Compute per-frame RMS
///   2. Maintain rolling noise floor baseline
///   3. On threshold crossing → state machine: IDLE → RISING → PEAK → DECAYING
///   4. On state transitions: check attack speed, decay speed, duration
///   5. Compute spectral features (ZCR + band energy from FFT)
///   6. Check speech continuity score
///   7. Check cooldown
///   8. Emit event
class TapDetector {
    var onTapDetected: ((TapDetectionEvent) -> Void)?

    private var config = TapDetectorConfig()
    private let engine = AVAudioEngine()
    private let processQueue = DispatchQueue(label: "com.mactapdetector.process", qos: .userInteractive)
    private var isRunning = false
    private let lock = NSLock()

    // ── Noise floor state ─────────────────────────────────────
    // Ring buffer of recent RMS values for baseline estimation
    private var rmsHistory: [Float] = []
    private var rmsHistoryMaxFrames = 30  // recalculated on config update
    private var currentBaseline: Float = 0.0

    // ── Detection state machine ───────────────────────────────
    private enum DetState { case idle, rising, peak, decaying }
    private var state: DetState = .idle

    private var onsetBaseline: Float = 0.0    // baseline at the moment of onset
    private var peakAmplitude: Float  = 0.0
    private var attackStartFrame: Int = 0
    private var peakFrame: Int        = 0
    private var onsetFrame: Int       = 0
    private var frameCount: Int       = 0

    // ── Continuity tracking ───────────────────────────────────
    // count of consecutive frames above the "hot" threshold
    private var consecutiveHotFrames: Int = 0
    // short sliding window of "hot/not" booleans for continuity score
    private var continuityWindow: [Bool] = []
    private var continuityWindowMaxFrames = 20

    // ── Cooldown ──────────────────────────────────────────────
    private var lastTriggerFrame: Int = -10_000

    // ── FFT setup (reused across buffers) ─────────────────────
    private var fftSetup: FFTSetup?
    private var fftLog2n: vDSP_Length = 0
    private var fftSize: Int = 0

    // ── Audio format ──────────────────────────────────────────
    private var sampleRate: Double = 44100.0
    private var framesPerMs: Double { sampleRate / 1000.0 }

    // ─────────────────────────────────────────────────────────
    // MARK: Start / Stop
    // ─────────────────────────────────────────────────────────

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !isRunning else { return }

        let inputNode = engine.inputNode

        // Use the hardware's own format to avoid silent format-mismatch failures
        let hwFormat = inputNode.inputFormat(forBus: 0)
        sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 44100.0

        reconfigureInternals()
        prepareFft(bufferSize: config.bufferSize)

        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(config.bufferSize),
            format: hwFormat
        ) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        log("Started. sampleRate=\(Int(sampleRate)) bufferSize=\(config.bufferSize)")
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        resetState()
        log("Stopped.")
    }

    func updateConfig(_ newConfig: TapDetectorConfig) {
        lock.lock(); defer { lock.unlock() }
        config = newConfig
        reconfigureInternals()
        prepareFft(bufferSize: config.bufferSize)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Internal helpers
    // ─────────────────────────────────────────────────────────

    private func reconfigureInternals() {
        let msPerFrame = Double(config.bufferSize) / max(sampleRate, 1.0) * 1000.0
        rmsHistoryMaxFrames = max(1, Int(Double(config.noiseFloorWindowMs) / msPerFrame))
        continuityWindowMaxFrames = max(1, Int(Double(config.speechContinuityWindowMs) / msPerFrame))

        if rmsHistory.count > rmsHistoryMaxFrames {
            rmsHistory = Array(rmsHistory.suffix(rmsHistoryMaxFrames))
        }
        if continuityWindow.count > continuityWindowMaxFrames {
            continuityWindow = Array(continuityWindow.suffix(continuityWindowMaxFrames))
        }
    }

    private func prepareFft(bufferSize: Int) {
        // Use half the buffer for FFT (must be power of 2)
        let n = nearestPowerOf2(bufferSize)
        if n == fftSize { return }
        if let old = fftSetup { vDSP_destroy_fftsetup(old) }
        fftLog2n = vDSP_Length(log2(Float(n)))
        fftSetup = vDSP_create_fftsetup(fftLog2n, FFTRadix(kFFTRadix2))
        fftSize = n
    }

    private func resetState() {
        state = .idle
        peakAmplitude = 0
        consecutiveHotFrames = 0
        continuityWindow.removeAll()
        rmsHistory.removeAll()
        currentBaseline = 0
        frameCount = 0
        lastTriggerFrame = -10_000
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Audio buffer processing (called on CoreAudio thread)
    // ─────────────────────────────────────────────────────────

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelDataPtr = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        var samples: [Float]

        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelDataPtr[0], count: frameLength))
        } else {
            // Mix all channels to mono
            samples = [Float](repeating: 0, count: frameLength)
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                let chData = UnsafeBufferPointer(start: channelDataPtr[ch], count: frameLength)
                for i in 0..<frameLength {
                    samples[i] += chData[i] * scale
                }
            }
        }

        processQueue.async { [weak self] in
            self?.analyze(samples: samples)
        }
    }

    private func analyze(samples: [Float]) {
        let rms = computeRMS(samples)
        frameCount += 1
        // ── 1. Update noise floor baseline ────────────────────
        updateNoiseFloor(rms: rms)

        let dynamicThreshold = computeDynamicThreshold()
        let isHot = rms > dynamicThreshold

        // ── 2. Continuity tracking ────────────────────────────
        updateContinuity(isHot: isHot)

        // ── 3. State machine ──────────────────────────────────
        switch state {
        case .idle:
            if isHot {
                // Onset detected
                state = .rising
                onsetFrame       = frameCount
                attackStartFrame = frameCount
                peakFrame        = frameCount
                onsetBaseline    = currentBaseline
                peakAmplitude    = rms
            }

        case .rising:
            if rms >= peakAmplitude {
                peakAmplitude = rms
                peakFrame = frameCount
            } else {
                // Energy started dropping — transition to decaying
                state = .decaying
            }

        case .decaying:
            if rms > peakAmplitude * config.peakDropRatio {
                // Still above decay threshold — keep decaying
                if rms > peakAmplitude {
                    // New peak emerged (double-knock) — restart
                    peakAmplitude = rms
                    peakFrame = frameCount
                }
            } else {
                // Decayed sufficiently — evaluate candidate event
                evaluateCandidate(currentFrame: frameCount, samples: samples)
                state = .idle
                peakAmplitude = 0
            }

            // Hard cutoff: event lasted too long → reject and reset
            let msPerFrame = 1000.0 * Double(config.bufferSize) / max(sampleRate, 1)
            let durationMs = Double(frameCount - onsetFrame) * msPerFrame
            if durationMs > Double(config.maxEventDurationMs) {
                log("Event rejected: duration \(String(format: "%.1f", durationMs))ms > maxEventDurationMs \(config.maxEventDurationMs)ms")
                state = .idle
                peakAmplitude = 0
            }

        case .peak:
            break // unused but kept for clarity
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Event evaluation
    // ─────────────────────────────────────────────────────────

    private func evaluateCandidate(currentFrame: Int, samples: [Float]) {
        let msPerFrame = 1000.0 * Double(config.bufferSize) / max(sampleRate, 1)

        let attackTimeMs  = Float(Double(peakFrame - onsetFrame) * msPerFrame)
        let decayTimeMs   = Float(Double(currentFrame - peakFrame) * msPerFrame)
        let eventDurationMs = Float(Double(currentFrame - onsetFrame) * msPerFrame)
        let peakToBaseline  = onsetBaseline > 0 ? peakAmplitude / onsetBaseline : peakAmplitude / config.minimumAbsoluteThreshold
        let attackDelta     = peakAmplitude - onsetBaseline

        // ── Spectral features ─────────────────────────────────
        let (highFreqRatio, speechContinuityScore) = computeSpectralFeatures(samples: samples)

        // ── Continuity score ──────────────────────────────────
        let continuityScore = computeContinuityScore()

        // ── Cooldown ──────────────────────────────────────────
        let cooldownFrames = Int(Double(config.cooldownMs) / msPerFrame)
        let cooldownOk = (currentFrame - lastTriggerFrame) >= cooldownFrames

        // ── Decision ──────────────────────────────────────────
        var reasons: [String] = []

        if peakAmplitude <= computeDynamicThreshold() {
            reasons.append("peak below threshold (\(String(format:"%.4f",peakAmplitude)) <= \(String(format:"%.4f",computeDynamicThreshold())))")
        }
        if peakToBaseline < config.minPeakToBaselineRatio {
            reasons.append("p2b too low (\(String(format:"%.2f",peakToBaseline)) < \(config.minPeakToBaselineRatio))")
        }
        if attackTimeMs > Float(config.attackMsMax) {
            reasons.append("attack too slow (\(String(format:"%.1f",attackTimeMs))ms > \(config.attackMsMax)ms)")
        }
        if attackDelta < config.minAttackDelta {
            reasons.append("attack delta too small (\(String(format:"%.4f",attackDelta)) < \(config.minAttackDelta))")
        }
        if decayTimeMs > Float(config.decayMsMax) {
            reasons.append("decay too slow (\(String(format:"%.1f",decayTimeMs))ms > \(config.decayMsMax)ms)")
        }
        if highFreqRatio < config.minHighFreqRatio {
            reasons.append("highFreqRatio too low (\(String(format:"%.2f",highFreqRatio)) < \(config.minHighFreqRatio))")
        }
        if config.continuityRejectionEnabled {
            if speechContinuityScore > config.maxSpeechContinuityScore {
                reasons.append("speechContinuityScore too high (\(String(format:"%.2f",speechContinuityScore)) > \(config.maxSpeechContinuityScore))")
            }
            if consecutiveHotFrames > config.maxConsecutiveHotFrames {
                reasons.append("consecutiveHotFrames too high (\(consecutiveHotFrames) > \(config.maxConsecutiveHotFrames))")
            }
            if continuityScore > config.maxSpeechContinuityScore {
                reasons.append("continuityScore too high (\(String(format:"%.2f",continuityScore)))")
            }
        }
        if !cooldownOk {
            reasons.append("in cooldown")
        }

        if reasons.isEmpty {
            // All checks passed → emit
            lastTriggerFrame = currentFrame
            let event = TapDetectionEvent(
                amplitude: peakAmplitude,
                peakToBaselineRatio: peakToBaseline,
                attackTimeMs: attackTimeMs,
                decayTimeMs: decayTimeMs,
                eventDurationMs: eventDurationMs,
                highFreqRatio: highFreqRatio,
                speechContinuityScore: speechContinuityScore
            )
            log("TAP DETECTED: \(event.toFlutterMap())")
            onTapDetected?(event)
        } else {
            log("Event rejected: \(reasons.joined(separator: "; "))")
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Noise floor
    // ─────────────────────────────────────────────────────────

    private func updateNoiseFloor(rms: Float) {
        rmsHistory.append(rms)
        if rmsHistory.count > rmsHistoryMaxFrames {
            rmsHistory.removeFirst()
        }
        // Use a low percentile of recent history as baseline so loud events
        // don't inflate the floor.
        if rmsHistory.count >= 3 {
            let sorted = rmsHistory.sorted()
            let idx = max(0, Int(Float(sorted.count) * 0.25))
            currentBaseline = sorted[idx]
        } else {
            currentBaseline = rmsHistory.min() ?? rms
        }
    }

    private func computeDynamicThreshold() -> Float {
        guard config.adaptiveNoiseFloorEnabled, currentBaseline > 0 else {
            return max(config.threshold, config.minimumAbsoluteThreshold)
        }
        let dynamic = currentBaseline * config.baselineMultiplier
        return max(dynamic, config.minimumAbsoluteThreshold)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Continuity
    // ─────────────────────────────────────────────────────────

    private func updateContinuity(isHot: Bool) {
        continuityWindow.append(isHot)
        if continuityWindow.count > continuityWindowMaxFrames {
            continuityWindow.removeFirst()
        }

        if isHot {
            consecutiveHotFrames += 1
        } else {
            consecutiveHotFrames = 0
        }
    }

    private func computeContinuityScore() -> Float {
        guard !continuityWindow.isEmpty else { return 0 }
        let hotCount = continuityWindow.filter { $0 }.count
        return Float(hotCount) / Float(continuityWindow.count)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Spectral features
    // ─────────────────────────────────────────────────────────

    /// Returns (highFreqRatio, speechContinuityScore).
    ///
    /// - highFreqRatio: fraction of energy in upper half of spectrum
    /// - speechContinuityScore: fraction of energy in speech band (300–3400 Hz)
    ///   weighted and normalised so it is useful as a speech rejection score.
    private func computeSpectralFeatures(samples: [Float]) -> (Float, Float) {
        guard let setup = fftSetup, fftSize > 0, samples.count >= fftSize else {
            // Fallback: use zero-crossing rate as a proxy
            let zcr = zeroCrossingRate(samples)
            // High ZCR ≈ high-freq content; low ZCR with energy ≈ speech
            let hfProxy = min(zcr * 2.0, 1.0)
            let speechProxy = max(0, 1.0 - hfProxy)
            return (hfProxy, speechProxy)
        }

        var n = fftSize
        var paddedSamples = Array(samples.prefix(n))
        if paddedSamples.count < n {
            paddedSamples += [Float](repeating: 0, count: n - paddedSamples.count)
        }

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(paddedSamples, 1, window, 1, &paddedSamples, 1, vDSP_Length(n))

        // Pack as split complex — use withUnsafeMutableBufferPointer so pointers
        // remain valid for the entire duration of the FFT calls.
        var realPart = [Float](repeating: 0, count: n / 2)
        var imagPart = [Float](repeating: 0, count: n / 2)

        var magnitudes = [Float](repeating: 0, count: n / 2)
        var totalEnergy: Float = 0

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )
                paddedSamples.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, fftLog2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))
                vDSP_sve(magnitudes, 1, &totalEnergy, vDSP_Length(n / 2))
            }
        }

        guard totalEnergy > 1e-10 else { return (0.5, 0.2) }

        // Bin → Hz:  binHz = (bin / (n/2)) * (sampleRate / 2)
        let nyquist = Float(sampleRate) / 2.0
        let binToHz = nyquist / Float(n / 2)

        // Speech band: 300 – 3400 Hz
        let speechLowBin  = Int(300.0 / binToHz)
        let speechHighBin = min(Int(3400.0 / binToHz), n / 2 - 1)
        // High-freq band: above 2 kHz (chassis taps have energy here)
        let highFreqLowBin = max(1, Int(2000.0 / binToHz))

        var speechEnergy: Float = 0
        var highFreqEnergy: Float = 0

        for bin in 0 ..< n / 2 {
            let e = magnitudes[bin]
            if bin >= speechLowBin && bin <= speechHighBin { speechEnergy += e }
            if bin >= highFreqLowBin { highFreqEnergy += e }
        }

        let highFreqRatio = highFreqEnergy / totalEnergy
        let speechRatio = (speechEnergy / totalEnergy) * config.speechBandWeight

        return (highFreqRatio * config.highFrequencyWeight, speechRatio)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Signal utilities
    // ─────────────────────────────────────────────────────────

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func zeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1 ..< samples.count {
            if (samples[i] >= 0) != (samples[i - 1] >= 0) { crossings += 1 }
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    private func nearestPowerOf2(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var p = 1
        while p < n { p <<= 1 }
        // Use n itself if it's already a power of 2, otherwise half it for FFT
        return p == n ? n : p >> 1
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Logging
    // ─────────────────────────────────────────────────────────

    private func log(_ msg: String) {
        guard config.enableDebugLogs else { return }
        NSLog("[MacTapDetector] %@", msg)
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - SoundPlayer
// ─────────────────────────────────────────────────────────────

/// Plays bundled audio assets.  Uses AVAudioPlayer for simplicity
/// (suitable for short notification sounds).
class SoundPlayer {
    private var player: AVAudioPlayer?

    /// Play an asset resolved from the main bundle.
    ///
    /// Flutter packages assets into the app bundle under `flutter_assets/`.
    func play(assetPath: String, loop: Bool, volume: Float) throws {
        // Normalise the path: strip leading slash, try exact path first,
        // then look under flutter_assets/.
        let candidates = buildCandidateSoundURLs(for: assetPath)

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw NSError(
                domain: "MacTapDetector",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Asset not found: \(assetPath). Tried: \(candidates.map(\.path).joined(separator: ", "))"]
            )
        }

        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.volume = volume
        newPlayer.numberOfLoops = loop ? -1 : 0
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func buildCandidateSoundURLs(for assetPath: String) -> [URL] {
        let bundle = Bundle.main
        var urls: [URL] = []

        // 1. Exact resource path within the bundle
        let stripped = assetPath.hasPrefix("/") ? String(assetPath.dropFirst()) : assetPath
        if let u = bundle.url(forResource: stripped, withExtension: nil) { urls.append(u) }

        // 2. Under flutter_assets/
        if let resourceURL = bundle.resourceURL {
            urls.append(resourceURL.appendingPathComponent("flutter_assets/\(stripped)"))
        }

        // 3. Absolute path as-is (for development convenience)
        if assetPath.hasPrefix("/") {
            urls.append(URL(fileURLWithPath: assetPath))
        }

        return urls
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - SoundRecorder
// ─────────────────────────────────────────────────────────────

class SoundRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    private func soundsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("TapSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func startRecording(name: String) throws {
        stopRecording()
        let dir = try soundsDirectory()
        let url = dir.appendingPathComponent("\(name).m4a")
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:          44100.0,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.delegate = self
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(domain: "MacTapDetector", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"])
        }
        recorder = rec
    }

    @discardableResult
    func stopRecording() -> String? {
        recorder?.stop()
        recorder = nil
        let path = currentURL?.path
        currentURL = nil
        return path
    }

    func getSoundFiles() -> [String] {
        guard let dir = try? soundsDirectory() else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return items
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a > b
            }
            .map(\.path)
    }

    func deleteSound(path: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
}
