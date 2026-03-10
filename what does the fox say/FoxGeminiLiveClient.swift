import AVFoundation
import Combine
import Foundation
import QuartzCore

final class GeminiLiveClient: NSObject, ObservableObject {
    struct Configuration {
        var webSocketURL: URL
        var model: String
        var responseModalities: [String]
        var authToken: String?
        var inputAudioMimeType: String?
        var outputAudioMimeType: String?
        var realtimeChunkMimeType: String?
        var voiceName: String?
        var mediaResolution: String?
        var contextWindowTriggerTokens: Int?
        var contextWindowTargetTokens: Int?
        var allowAudioStreaming: Bool
    }

    enum AudioOutputRouteKind: String {
        case builtInSpeaker = "speaker"
        case builtInReceiver = "receiver"
        case headphones = "headphones"
        case bluetooth = "bluetooth"
        case airPlay = "airplay"
        case external = "external"
        case unknown = "unknown"

        var sttInputPrefersMicOnly: Bool {
            true
        }

        var uplinkResumeDelay: TimeInterval {
            switch self {
            case .headphones, .bluetooth:
                return 0.12
            case .airPlay, .external:
                return 0.18
            case .builtInReceiver:
                return 0.18
            case .builtInSpeaker, .unknown:
                return 0.25
            }
        }
    }

    struct PreparedConversationAudio {
        let sttInputURL: URL
        let archiveURL: URL?
        let durationSec: Int
        let outputRoute: AudioOutputRouteKind
        let sttInputSource: String
        let archiveSource: String?

        var cleanupURLs: [URL] {
            var urls = [sttInputURL]
            if let archiveURL, !urls.contains(archiveURL) {
                urls.append(archiveURL)
            }
            return urls
        }
    }

    @Published private(set) var isConnected: Bool = false

    var onUserSpeechStart: (() -> Void)?
    var onUserSpeechEnd: (() -> Void)?
    var onResponseStart: (() -> Void)?
    var onResponseEnd: (() -> Void)?
    var onAudioFileReady: ((PreparedConversationAudio) -> Void)?
    var onFinalTranscript: ((TranscriptSegment) -> Void)?
    var onSessionClosed: (() -> Void)?
    var onProtocolError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let playbackEngine = AVAudioEngine()
    private let playbackNode = AVAudioPlayerNode()
    private let targetSampleRate: Double = 16000
    private let targetChannelCount: AVAudioChannelCount = 1
    private var audioConverter: AVAudioConverter?
    private var converterSourceSampleRate: Double = 0
    private var converterSourceChannelCount: AVAudioChannelCount = 0
    private var isResponseActive: Bool = false
    private var lastResponseTextAt: CFTimeInterval = 0
    private var receivedMessageCount: Int = 0
    private var isReadyToSendAudio: Bool = false
    private var loggedFirstMessage: Bool = false
    private var sentAudioChunkCount: Int = 0
    private var receivedAudioChunkCount: Int = 0
    private var audioChunkMimeType: String = "audio/pcm"
    private var allowAudioStreaming: Bool = true
    private var didSendStartControl: Bool = false
    private var socketTask: URLSessionWebSocketTask?
    private lazy var urlSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()
    private var pendingConfiguration: Configuration?
    private var recordingFile: AVAudioFile?
    private var recordingRawURL: URL?
    private var recordingStartTime: Date?
    private var modelRecordingFile: AVAudioFile?
    private var modelRecordingURL: URL?
    private var modelRecordingFormat: AVAudioFormat?
    private var modelRecordingConverters: [String: AVAudioConverter] = [:]
    private var isUserSpeakingLocal: Bool = false
    private var lastSpeechTime: CFTimeInterval = 0
    private var speechAboveSince: CFTimeInterval?
    private var playbackOutputFormat: AVAudioFormat?
    private var playbackConverters: [String: AVAudioConverter] = [:]
    private var pendingAudioBuffers: Int = 0
    private var pendingTurnComplete: Bool = false
    private var uplinkEnabled: Bool = true
    private var uplinkResumeTask: DispatchWorkItem?
    private let localSpeechThreshold: Float = 0.02
    private let localSpeechSilenceDuration: CFTimeInterval = 1.0
    private let localSpeechMinDuration: CFTimeInterval = 0.25
    override init() {
        super.init()
        setupPlaybackEngine()
    }

    func connect(configuration: Configuration) {
        guard socketTask == nil else { return }
        debugLog(.realtime, "connect \(redactToken(in: configuration.webSocketURL.absoluteString))")

        isReadyToSendAudio = false
        setUplinkEnabled(true, reason: "connect")
        loggedFirstMessage = false
        sentAudioChunkCount = 0
        if let chunkMime = configuration.realtimeChunkMimeType, !chunkMime.isEmpty {
            audioChunkMimeType = chunkMime
        } else if let inputMime = configuration.inputAudioMimeType, !inputMime.isEmpty {
            audioChunkMimeType = inputMime
        } else {
            audioChunkMimeType = "audio/pcm"
        }
        allowAudioStreaming = configuration.allowAudioStreaming
        pendingConfiguration = configuration
        didSendStartControl = false
        socketTask = urlSession.webSocketTask(with: configuration.webSocketURL)
        socketTask?.resume()
    }

    func disconnect() {
        debugLog(.realtime, "disconnect")
        stopMicrophone()
        closeSocket()
    }

    func endSession() {
        debugLog(.realtime, "end session")
        stopMicrophone()
        sendControl("end")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.closeSocket()
        }
    }

    func startMicrophone() {
        debugLog(.audio, "start microphone")
        resetVAD()
        if audioEngine.isRunning {
            stopMicrophone()
        }
        resetModelAudioRecording()
        let session = AVAudioSession.sharedInstance()
        guard session.isInputAvailable else { return }
        do {
            // Keep route policy stable to avoid frequent graph/cache invalidation.
            let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            let nsError = error as NSError
            debugLog(.audio, "audio session setup failed: \(nsError.localizedDescription) code=\(nsError.code)")
            return
        }

        let input = audioEngine.inputNode
        let hwInputFormat = input.inputFormat(forBus: 0)
        let outputFormat = input.outputFormat(forBus: 0)
        // Use hardware input format for tap creation. On some routes (e.g. HFP),
        // inputFormat and outputFormat may differ (24k vs 48k), causing -10868.
        let inputFormat = hwInputFormat
        debugLog(.audio, "mic format hw=\(formatLabel(hwInputFormat)) out=\(formatLabel(outputFormat)) tap=\(formatLabel(inputFormat))")
        converterSourceSampleRate = 0
        converterSourceChannelCount = 0
        audioConverter = nil
        // Defensive cleanup: route/sample-rate changes can leave a stale graph/tap cache.
        audioEngine.stop()
        audioEngine.reset()
        input.removeTap(onBus: 0)
        setupAudioRecording(format: inputFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.sendAudioBuffer(buffer, inputFormat: buffer.format)
            self?.writeAudioBuffer(buffer)
            self?.detectLocalSpeech(buffer)
        }
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            let nsError = error as NSError
            debugLog(.audio, "mic start failed: \(nsError.localizedDescription) code=\(nsError.code) -> retry")
            audioEngine.stop()
            audioEngine.reset()
            input.removeTap(onBus: 0)
            setupAudioRecording(format: inputFormat)
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.sendAudioBuffer(buffer, inputFormat: buffer.format)
                self?.writeAudioBuffer(buffer)
                self?.detectLocalSpeech(buffer)
            }
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                let retryError = error as NSError
                debugLog(.audio, "mic start retry failed: \(retryError.localizedDescription) code=\(retryError.code)")
                return
            }
            return
        }
    }

    func stopMicrophone() {
        debugLog(.audio, "stop microphone")
        cancelPendingUplinkResume()
        setUplinkEnabled(true, reason: "stop_microphone")
        resetVAD()
        let durationSec = recordingStartTime.map { max(1, Int(Date().timeIntervalSince($0))) } ?? 0
        let rawURL = recordingRawURL
        let modelURL = modelRecordingURL
        let routeKind = currentOutputRouteKind()
        debugLog(.audio, "stop microphone route=\(routeKind.rawValue)")
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        recordingFile = nil
        recordingRawURL = nil
        recordingStartTime = nil
        modelRecordingFile = nil
        modelRecordingURL = nil
        modelRecordingFormat = nil
        modelRecordingConverters.removeAll()

        if rawURL != nil || modelURL != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                let preparedAudio = await self.prepareConversationAudioForUpload(
                    micURL: rawURL,
                    modelURL: modelURL,
                    routeKind: routeKind,
                    durationSec: max(1, durationSec)
                )
                if let preparedAudio {
                    self.onAudioFileReady?(preparedAudio)
                }
            }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func sendText(_ text: String) {
        guard let socketTask else { return }
        let payload = URLSessionWebSocketTask.Message.string(text)
        socketTask.send(payload) { _ in }
    }

    func interrupt() {
        onResponseEnd?()
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard allowAudioStreaming else { return }
        guard uplinkEnabled else { return }
        guard let socketTask, isConnected, isReadyToSendAudio else { return }
        guard let converter = ensureAudioConverter(inputFormat: inputFormat) else { return }
        guard let outputBuffer = convertPCM(buffer, converter: converter, inputFormat: inputFormat) else { return }
        guard let data = pcmData(from: outputBuffer), !data.isEmpty else { return }

        let payload: [String: Any] = [
            "type": "audio",
            "pcmBase64": data.base64EncodedString(),
            "sampleRate": Int(targetSampleRate),
            "channels": Int(targetChannelCount)
        ]
        sentAudioChunkCount += 1
        if sentAudioChunkCount <= 5 {
            debugLog(.audio, "send audio chunk \(sentAudioChunkCount) bytes=\(data.count)")
        }
        sendJSON(payload, through: socketTask)
    }

    private func ensureAudioConverter(inputFormat: AVAudioFormat) -> AVAudioConverter? {
        if audioConverter == nil
            || converterSourceSampleRate != inputFormat.sampleRate
            || converterSourceChannelCount != inputFormat.channelCount {
            audioConverter = makeConverter(inputFormat: inputFormat)
            converterSourceSampleRate = inputFormat.sampleRate
            converterSourceChannelCount = inputFormat.channelCount
        }
        return audioConverter
    }

    private func detectLocalSpeech(_ buffer: AVAudioPCMBuffer) {
        guard uplinkEnabled else { return }
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            var i = 0
            while i < frameLength {
                let sample = data[i]
                sum += sample * sample
                i += 1
            }
        }

        let mean = sum / Float(frameLength * max(channelCount, 1))
        let rms = sqrt(mean)
        let now = CACurrentMediaTime()

        if rms > localSpeechThreshold {
            if speechAboveSince == nil {
                speechAboveSince = now
            }
            lastSpeechTime = now
            if !isUserSpeakingLocal, let started = speechAboveSince, now - started >= localSpeechMinDuration {
                isUserSpeakingLocal = true
                debugLog(.audio, "vad speech start rms=\(rms)")
                onUserSpeechStart?()
            }
        } else {
            speechAboveSince = nil
            if isUserSpeakingLocal, now - lastSpeechTime > localSpeechSilenceDuration {
                isUserSpeakingLocal = false
                debugLog(.audio, "vad speech end rms=\(rms)")
                onUserSpeechEnd?()
            }
        }
    }

    private func resetVAD() {
        isUserSpeakingLocal = false
        speechAboveSince = nil
        lastSpeechTime = 0
    }

    private func cancelPendingUplinkResume() {
        uplinkResumeTask?.cancel()
        uplinkResumeTask = nil
    }

    private func setUplinkEnabled(_ enabled: Bool, reason: String) {
        guard uplinkEnabled != enabled else { return }
        uplinkEnabled = enabled
        if !enabled {
            resetVAD()
            debugLog(.audio, "uplink muted reason=\(reason)")
        } else {
            debugLog(.audio, "uplink resumed reason=\(reason)")
        }
    }

    private func suppressUplinkForPlayback(reason: String) {
        cancelPendingUplinkResume()
        setUplinkEnabled(false, reason: reason)
    }

    private func scheduleUplinkResumeAfterPlayback() {
        cancelPendingUplinkResume()
        let routeKind = currentOutputRouteKind()
        let delay = routeKind.uplinkResumeDelay
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setUplinkEnabled(true, reason: "playback_cooldown_complete")
        }
        uplinkResumeTask = work
        debugLog(.audio, "uplink resume scheduled delayMs=\(Int(delay * 1000)) route=\(routeKind.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setupAudioRecording(format: AVAudioFormat) {
        let filename = "voice-\(UUID().uuidString).caf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingRawURL = url
            recordingStartTime = Date()
        } catch {
            recordingFile = nil
            recordingRawURL = nil
            recordingStartTime = nil
            debugLog(.audio, "audio recording setup failed: \(error.localizedDescription)")
        }
    }

    private func writeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = recordingFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            debugLog(.audio, "audio recording write failed: \(error.localizedDescription)")
        }
    }

    private func resetModelAudioRecording() {
        if let url = modelRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelRecordingFile = nil
        modelRecordingURL = nil
        modelRecordingFormat = nil
        modelRecordingConverters.removeAll()
    }

    private func appendModelAudioBuffer(_ sourceBuffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) {
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        )
        guard let targetFormat else { return }

        if modelRecordingFile == nil {
            let filename = "voice-model-\(UUID().uuidString).caf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                let created = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
                modelRecordingFile = created
                modelRecordingURL = url
                modelRecordingFormat = created.processingFormat
                if let modelRecordingFormat {
                    debugLog(.audio, "model audio writer format \(formatLabel(modelRecordingFormat))")
                }
            } catch {
                debugLog(.audio, "model audio recording setup failed: \(error.localizedDescription)")
                modelRecordingFile = nil
                modelRecordingURL = nil
                modelRecordingFormat = nil
                return
            }
        }

        guard let file = modelRecordingFile else { return }
        let fileFormat = modelRecordingFormat ?? file.processingFormat
        let bufferToWrite: AVAudioPCMBuffer
        if sourceFormat == fileFormat {
            bufferToWrite = sourceBuffer
        } else {
            guard let converted = convertAudioBuffer(sourceBuffer, from: sourceFormat, to: fileFormat) else {
                debugLog(.audio, "model audio convert skipped src=\(formatLabel(sourceFormat)) dst=\(formatLabel(fileFormat))")
                return
            }
            bufferToWrite = converted
        }
        guard bufferToWrite.frameLength > 0 else { return }
        if (try? file.write(from: bufferToWrite)) == nil {
            debugLog(
                .audio,
                "model audio recording write failed src=\(formatLabel(sourceFormat)) file=\(formatLabel(fileFormat)) frames=\(bufferToWrite.frameLength)"
            )
        }
    }

    private func convertAudioBuffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        from sourceFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let key = "\(Int(sourceFormat.sampleRate))-\(sourceFormat.channelCount)-\(sourceFormat.commonFormat.rawValue)->\(Int(targetFormat.sampleRate))-\(targetFormat.channelCount)-\(targetFormat.commonFormat.rawValue)"
        let converter: AVAudioConverter
        if let cached = modelRecordingConverters[key] {
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                return nil
            }
            modelRecordingConverters[key] = created
            converter = created
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 8
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        if status == .error {
            if let error {
                debugLog(.audio, "model audio convert failed: \(error.localizedDescription)")
            }
            return nil
        }
        if outBuffer.frameLength == 0 {
            return nil
        }
        return outBuffer
    }

    private func prepareConversationAudioForUpload(
        micURL: URL?,
        modelURL: URL?,
        routeKind: AudioOutputRouteKind,
        durationSec: Int
    ) async -> PreparedConversationAudio? {
        let micExists = micURL.map { FileManager.default.fileExists(atPath: $0.path) && ((fileSizeBytes($0) ?? 0) > 0) } ?? false
        let modelExists = modelURL.map { FileManager.default.fileExists(atPath: $0.path) && ((fileSizeBytes($0) ?? 0) > 0) } ?? false
        debugLog(.audio, "voice mix prepare mic=\(micExists) model=\(modelExists) route=\(routeKind.rawValue)")

        guard micExists || modelExists else { return nil }
        if !modelExists {
            if let modelURL { try? FileManager.default.removeItem(at: modelURL) }
            guard let micURL else { return nil }
            debugLog(.audio, "voice mix result archive=mic_only sttInput=mic_only file=\(micURL.lastPathComponent)")
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }
        if !micExists {
            if let micURL { try? FileManager.default.removeItem(at: micURL) }
            guard let modelURL else { return nil }
            debugLog(.audio, "voice mix result archive=model_only sttInput=model_only file=\(modelURL.lastPathComponent)")
            return PreparedConversationAudio(
                sttInputURL: modelURL,
                archiveURL: modelURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "model_only",
                archiveSource: "model_only"
            )
        }

        guard let micURL, let modelURL else {
            guard let fallbackURL = micURL ?? modelURL else { return nil }
            let source = micURL != nil ? "mic_only" : "model_only"
            return PreparedConversationAudio(
                sttInputURL: fallbackURL,
                archiveURL: fallbackURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: source,
                archiveSource: source
            )
        }
        let micAsset = AVURLAsset(url: micURL)
        let modelAsset = AVURLAsset(url: modelURL)
        guard let micTrack = await firstAudioTrack(in: micAsset) else {
            try? FileManager.default.removeItem(at: micURL)
            debugLog(.audio, "voice mix fallback micTrackMissing -> model_only")
            return PreparedConversationAudio(
                sttInputURL: modelURL,
                archiveURL: modelURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "model_only",
                archiveSource: "model_only"
            )
        }
        guard let modelTrack = await firstAudioTrack(in: modelAsset) else {
            try? FileManager.default.removeItem(at: modelURL)
            debugLog(.audio, "voice mix fallback modelTrackMissing -> mic_only")
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }

        let composition = AVMutableComposition()
        guard let micCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let modelCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }
        guard let micDuration = await assetDuration(of: micAsset),
              let modelDuration = await assetDuration(of: modelAsset) else {
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }
        do {
            try micCompTrack.insertTimeRange(CMTimeRange(start: .zero, duration: micDuration), of: micTrack, at: .zero)
            try modelCompTrack.insertTimeRange(CMTimeRange(start: .zero, duration: modelDuration), of: modelTrack, at: .zero)
        } catch {
            debugLog(.audio, "conversation mix insert failed: \(error.localizedDescription)")
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }

        let micParams = AVMutableAudioMixInputParameters(track: micCompTrack)
        micParams.setVolume(1.0, at: .zero)
        let modelParams = AVMutableAudioMixInputParameters(track: modelCompTrack)
        modelParams.setVolume(1.0, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [micParams, modelParams]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-mixed-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: micURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mic_only"
            )
        }
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true

        let result = await runExport(exporter, outputURL: outputURL, fileType: .m4a)
        if case .success = result {
            try? FileManager.default.removeItem(at: modelURL)
            debugLog(
                .audio,
                "voice mix result archive=mixed sttInput=\(routeKind.sttInputPrefersMicOnly ? "mic_only" : "mixed") archiveFile=\(outputURL.lastPathComponent) sttFile=\(micURL.lastPathComponent)"
            )
            return PreparedConversationAudio(
                sttInputURL: micURL,
                archiveURL: outputURL,
                durationSec: durationSec,
                outputRoute: routeKind,
                sttInputSource: "mic_only",
                archiveSource: "mixed"
            )
        }
        if case .failure(let error) = result {
            debugLog(.audio, "conversation mix export failed: \(error.localizedDescription)")
        } else {
            debugLog(.audio, "conversation mix export failed: unknown")
        }
        try? FileManager.default.removeItem(at: modelURL)
        debugLog(.audio, "voice mix fallback exportFailed -> mic_only file=\(micURL.lastPathComponent)")
        return PreparedConversationAudio(
            sttInputURL: micURL,
            archiveURL: micURL,
            durationSec: durationSec,
            outputRoute: routeKind,
            sttInputSource: "mic_only",
            archiveSource: "mic_only"
        )
    }

    private func firstAudioTrack(in asset: AVURLAsset) async -> AVAssetTrack? {
        do {
            return try await asset.loadTracks(withMediaType: .audio).first
        } catch {
            return nil
        }
    }

    private func assetDuration(of asset: AVURLAsset) async -> CMTime? {
        do {
            return try await asset.load(.duration)
        } catch {
            return nil
        }
    }

    private func runExport(
        _ exporter: AVAssetExportSession,
        outputURL: URL,
        fileType: AVFileType
    ) async -> Result<Void, Error> {
        do {
            try await exporter.export(to: outputURL, as: fileType)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func fileSizeBytes(_ url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize
    }

    private func currentOutputRouteKind() -> AudioOutputRouteKind {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.currentRoute.outputs.first?.portType else {
            return .unknown
        }
        switch port {
        case .builtInSpeaker:
            return .builtInSpeaker
        case .builtInReceiver:
            return .builtInReceiver
        case .headphones:
            return .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth
        case .airPlay:
            return .airPlay
        case .carAudio, .usbAudio, .lineOut:
            return .external
        default:
            return .unknown
        }
    }

    private func listenForMessages() {
        socketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.listenForMessages()
            case .failure(let error):
                let nsError = error as NSError
                debugLog(.realtime, "receive error: \(nsError.localizedDescription) code=\(nsError.code) domain=\(nsError.domain)")
                self.isConnected = false
                self.isResponseActive = false
                self.socketTask = nil
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handlePayload(text: text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handlePayload(text: text)
            }
        @unknown default:
            break
        }
    }

    private func handlePayload(text: String) {
        receivedMessageCount += 1
        if !loggedFirstMessage {
            loggedFirstMessage = true
            let preview = text.prefix(1200)
            debugLog(.realtime, "first message: \(preview)")
        }
        if receivedMessageCount <= 5 {
            let preview = text.prefix(800)
            debugLog(.realtime, "recv \(receivedMessageCount): \(preview)")
        }
        guard let data = text.data(using: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        handleProtocolMessage(json)
    }

    private func debounceResponseEnd() {
        guard pendingAudioBuffers == 0 else { return }
        let now = CACurrentMediaTime()
        let elapsed = now - lastResponseTextAt
        if elapsed > 1.0 {
            endResponseIfNeeded()
        }
    }

    private func endResponseIfNeededIfReady() {
        guard pendingTurnComplete else { return }
        guard pendingAudioBuffers == 0 else { return }
        pendingTurnComplete = false
        endResponseIfNeeded()
    }

    private func endResponseIfNeeded() {
        guard isResponseActive else { return }
        isResponseActive = false
        scheduleUplinkResumeAfterPlayback()
        onResponseEnd?()
    }

    private func isTurnComplete(_ json: [String: Any]) -> Bool {
        if let serverContent = json["serverContent"] as? [String: Any] {
            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                return true
            }
        }
        if let eventType = json["eventType"] as? String {
            let normalized = eventType.lowercased()
            if normalized.contains("turn_complete") || normalized.contains("turncomplete") {
                return true
            }
        }
        if let done = json["done"] as? Bool, done {
            return true
        }
        return false
    }

    private func handleProtocolMessage(_ json: [String: Any]) {
        let type = (json["type"] as? String ?? "").lowercased()
        switch type {
        case "state":
            handleStateValue((json["value"] as? String ?? "").lowercased())
        case "audio_reply":
            guard let base64 = json["pcmBase64"] as? String,
                  let data = Data(base64Encoded: base64),
                  !data.isEmpty else {
                return
            }
            let sampleRate = (json["sampleRate"] as? NSNumber)?.doubleValue ?? 24_000
            let channels = (json["channels"] as? NSNumber)?.uint32Value ?? 1
            if !isResponseActive {
                isResponseActive = true
                suppressUplinkForPlayback(reason: "audio_reply")
                onResponseStart?()
            }
            lastResponseTextAt = CACurrentMediaTime()
            playAudioReply(data: data, sampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        case "final_transcript":
            guard let speakerRaw = json["speaker"] as? String,
                  let text = json["text"] as? String,
                  !text.isEmpty else {
                return
            }
            let speaker = TranscriptSpeaker(rawValue: speakerRaw) ?? .assistant
            onFinalTranscript?(TranscriptSegment(speaker: speaker, text: text))
        case "partial_transcript":
            break
        case "error":
            let message = json["message"] as? String ?? "Unknown realtime error"
            debugLog(.realtime, "protocol error: \(message)")
            onProtocolError?(message)
        default:
            debugLog(.realtime, "unknown protocol message: \(type)")
        }
    }

    private func handleStateValue(_ value: String) {
        debugLog(.realtime, "state=\(value)")
        switch value {
        case "listening":
            isReadyToSendAudio = true
            if isResponseActive {
                endResponseIfNeeded()
            }
        case "thinking":
            isReadyToSendAudio = true
        case "speaking":
            if !isResponseActive {
                isResponseActive = true
                suppressUplinkForPlayback(reason: "state_speaking")
                onResponseStart?()
            }
        case "idle":
            if didSendStartControl {
                isReadyToSendAudio = true
            }
            if isResponseActive {
                pendingTurnComplete = true
                endResponseIfNeededIfReady()
            }
        default:
            break
        }
    }

    private func makeConverter(inputFormat: AVAudioFormat) -> AVAudioConverter? {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: true
        ) else {
            return nil
        }
        return AVAudioConverter(from: inputFormat, to: targetFormat)
    }

    private func convertPCM(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        inputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let outputFormat = converter.outputFormat
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            if let error {
                debugLog(.audio, "audio convert failed: \(error.localizedDescription)")
            }
            return nil
        }
        return outputBuffer
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else { return nil }
        return Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
    }

    private func sendControl(_ op: String) {
        guard let socketTask, isConnected else { return }
        debugLog(.realtime, "send control op=\(op)")
        sendJSON(["type": "control", "op": op], through: socketTask)
    }

    private func redactToken(in url: String) -> String {
        guard let range = url.range(of: "token=") else { return url }
        let prefix = url[..<range.upperBound]
        return "\(prefix)REDACTED"
    }

    private func sendJSON(_ payload: [String: Any], through socketTask: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        socketTask.send(.string(text)) { _ in }
    }

    private func setupPlaybackEngine() {
        if playbackNode.engine == nil {
            playbackEngine.attach(playbackNode)
        }
        playbackEngine.disconnectNodeOutput(playbackNode)
        playbackEngine.connect(playbackNode, to: playbackEngine.mainMixerNode, format: nil)
        playbackOutputFormat = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
        playbackConverters.removeAll()
    }

    private func ensurePlaybackEngineRunning() {
        if playbackOutputFormat == nil {
            setupPlaybackEngine()
        }
        if !playbackEngine.isRunning {
            do {
                try playbackEngine.start()
            } catch {
                let nsError = error as NSError
                debugLog(.audio, "playback start failed: \(nsError.localizedDescription) code=\(nsError.code)")
                return
            }
        }
        if !playbackNode.isPlaying {
            playbackNode.play()
        }
    }

    private func playAudioReply(data: Data, sampleRate: Double, channels: AVAudioChannelCount) {
        ensurePlaybackEngineRunning()
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else { return }
        guard let outputFormat = playbackOutputFormat else { return }
        let frameCount = data.count / 2
        guard frameCount > 0 else { return }
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)
        let audioBuffer = sourceBuffer.mutableAudioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else { return }
        data.copyBytes(to: mData.assumingMemoryBound(to: UInt8.self), count: data.count)
        sourceBuffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(data.count)
        appendModelAudioBuffer(sourceBuffer, sourceFormat: sourceFormat)

        let bufferToPlay: AVAudioPCMBuffer
        if sourceFormat == outputFormat {
            bufferToPlay = sourceBuffer
        } else {
            guard let converted = convertPlaybackBuffer(sourceBuffer, from: sourceFormat, to: outputFormat) else {
                return
            }
            bufferToPlay = converted
        }

        pendingAudioBuffers += 1
        receivedAudioChunkCount += 1
        if receivedAudioChunkCount <= 5 {
            debugLog(.audio, "play audio chunk \(receivedAudioChunkCount) bytes=\(data.count) rate=\(sampleRate)")
        }
        playbackNode.scheduleBuffer(bufferToPlay) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.pendingAudioBuffers = max(0, self.pendingAudioBuffers - 1)
                self.endResponseIfNeededIfReady()
            }
        }
    }

    private func convertPlaybackBuffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        from sourceFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let key = "\(Int(sourceFormat.sampleRate))-\(sourceFormat.channelCount)-\(sourceFormat.commonFormat.rawValue)->\(Int(outputFormat.sampleRate))-\(outputFormat.channelCount)-\(outputFormat.commonFormat.rawValue)"
        let converter: AVAudioConverter
        if let cached = playbackConverters[key] {
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: sourceFormat, to: outputFormat) else { return nil }
            playbackConverters[key] = created
            converter = created
        }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 8
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error {
            if let error {
                debugLog(.audio, "playback convert failed: \(error.localizedDescription) code=\(error.code)")
            }
            return nil
        }
        if outBuffer.frameLength == 0 {
            return nil
        }
        return outBuffer
    }

    private func stopPlayback() {
        playbackNode.stop()
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }
        playbackConverters.removeAll()
        pendingAudioBuffers = 0
        pendingTurnComplete = false
    }

    private func formatLabel(_ format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate))Hz/\(format.channelCount)ch/\(format.commonFormat.rawValue)"
    }

    private func closeSocket() {
        cancelPendingUplinkResume()
        deactivateAudioSession()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        isConnected = false
        isResponseActive = false
        pendingConfiguration = nil
        isReadyToSendAudio = false
        uplinkEnabled = true
        loggedFirstMessage = false
        sentAudioChunkCount = 0
        didSendStartControl = false
        stopPlayback()
    }
}

extension GeminiLiveClient: URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        debugLog(.realtime, "ws didOpen")
        isConnected = true
        receivedMessageCount = 0
        loggedFirstMessage = false
        sentAudioChunkCount = 0
        receivedAudioChunkCount = 0
        pendingTurnComplete = false
        pendingAudioBuffers = 0
        isReadyToSendAudio = false
        didSendStartControl = true
        sendControl("start")
        listenForMessages()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        debugLog(.realtime, "ws didClose code=\(closeCode.rawValue) reason=\(reasonText) sentChunks=\(sentAudioChunkCount)")
        isConnected = false
        isResponseActive = false
        socketTask = nil
        isReadyToSendAudio = false
        loggedFirstMessage = false
        didSendStartControl = false
        stopPlayback()
        onSessionClosed?()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsError = error as NSError
            debugLog(.realtime, "ws error: \(nsError.localizedDescription) code=\(nsError.code) domain=\(nsError.domain)")
        }
        isConnected = false
        isResponseActive = false
        socketTask = nil
        isReadyToSendAudio = false
        loggedFirstMessage = false
        didSendStartControl = false
        stopPlayback()
        onSessionClosed?()
    }
}
