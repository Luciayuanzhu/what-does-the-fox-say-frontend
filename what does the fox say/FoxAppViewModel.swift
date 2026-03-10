import AVFoundation
import Combine
import SwiftUI

@MainActor
final class FoxAppViewModel: ObservableObject {
    private enum ReviewPromptConfig {
        static let mainPageEntryThreshold = 3
    }

    enum MicPermissionStatus: Equatable {
        case idle
        case requesting
        case granted
        case denied
        case timedOut
    }

    @Published var video = VideoPlaybackController()
    @Published var profile: UserProfile = .placeholder
    @Published var showOnboarding = true
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var micEnabled = false
    @Published var isSpeaking = false
    @Published var isProcessingAudio = false
    @Published var hasUnreadHistory = false
    @Published var historySyncStatus: HistorySyncStatus = .empty
    @Published var historySessions: [PracticeSessionSummary] = []
    @Published var micPermissionStatus: MicPermissionStatus = .idle
    @Published var bannerText: String?
    @Published var isBootstrapping = false
    @Published var reviewRequestToken = 0

    let gemini = GeminiLiveClient()
    private let api = FoxAPIClient.shared
    private let deviceId = DeviceIdManager.shared.loadOrCreateDeviceId()
    private let historyPush = FoxHistoryPushClient()

    private var didAppear = false
    private var isAppActive = true
    private var currentSessionId: String?
    private var liveTranscript: [TranscriptSegment] = []
    private var isFinalizingCurrentSession = false
    private var historyPollTask: Task<Void, Never>?
    private var permissionTimeoutTask: Task<Void, Never>?
    private var authRecoveryTask: Task<Bool, Never>?
    private var pendingRealtimeFailureMessage: String?
    private var lastAppActiveState: Bool?
    private var finalizeWaitTask: Task<Void, Never>?
    private var waitingForFinalizeRecording = false
    private var didRecordMainPageEntryThisActiveCycle = false
    private var lastLiveTranscriptDedupKey: String?

    init() {
        loadLocalProfile()
        bindGeminiCallbacks()
        bindHistoryPush()
        video.playLoop(.foxidle)
    }

    func onAppear() {
        guard !didAppear else { return }
        didAppear = true
        debugLog(.lifecycle, "root appeared")
        Task {
            await bootstrap()
        }
    }

    func setAppActive(_ active: Bool) {
        if lastAppActiveState != active {
            debugLog(.lifecycle, active ? "scene became active" : "scene moved away from active")
            lastAppActiveState = active
        }
        isAppActive = active
        if active {
            didRecordMainPageEntryThisActiveCycle = false
            connectHistoryPushIfNeeded()
            startHistoryPolling()
            Task {
                await refreshHistorySync()
            }
        } else {
            if currentSessionId != nil || micEnabled {
                debugLog(.lifecycle, "backgrounding active practice session sessionId=\(foxShortID(currentSessionId))")
                endVoiceSession()
            }
            historyPush.disconnect()
            historyPollTask?.cancel()
            historyPollTask = nil
        }
    }

    func completeOnboarding(nativeLanguage: PracticeLanguage, targetLanguage: PracticeLanguage, persona: FoxPersona) {
        profile = UserProfile(nativeLanguage: nativeLanguage, targetLanguage: targetLanguage, persona: persona)
        persistLocalProfile()
        UserDefaults.standard.set(true, forKey: FoxStorageKeys.onboardingCompleted)
        showOnboarding = false
        debugLog(
            .profile,
            "complete onboarding native=\(nativeLanguage.rawValue) target=\(targetLanguage.rawValue) persona=\(persona.backendName)"
        )
        recordMainPageEntryIfNeeded()

        guard api.hasConfiguredBaseURL else {
            debugLog("Skipping onboarding profile sync because backend base URL is not configured")
            return
        }

        Task {
            guard await ensureAuthenticatedIfNeeded(reason: "onboarding_sync") else { return }
            do {
                _ = try await api.updateProfile(profile)
                clearNetworkBanner()
            } catch {
                presentNetworkError(error, fallback: "Couldn't save your profile right now.")
            }
        }
    }

    func updateProfile(_ updated: UserProfile) {
        profile = updated
        persistLocalProfile()
        debugLog(
            .profile,
            "local profile updated native=\(updated.nativeLanguage.rawValue) target=\(updated.targetLanguage.rawValue) persona=\(updated.persona.backendName)"
        )

        guard api.hasConfiguredBaseURL else {
            debugLog("Skipping profile update because backend base URL is not configured")
            return
        }

        Task {
            guard await ensureAuthenticatedIfNeeded(reason: "profile_update") else { return }
            do {
                let remote = try await api.updateProfile(updated)
                self.profile = remote
                self.persistLocalProfile()
                self.clearNetworkBanner()
            } catch {
                self.presentNetworkError(error, fallback: "Couldn't update your settings right now.")
            }
        }
    }

    func handleTap(location: CGPoint, in size: CGSize) {
        guard !micEnabled, !isSpeaking else { return }

        let middleX = size.width / 3.0
        let topY = size.height / 3.0
        let midY = 2.0 * size.height / 3.0
        let inMiddleX = location.x >= middleX && location.x <= 2.0 * middleX
        guard inMiddleX else { return }

        if location.y <= topY {
            playOneShot(.toptap)
        } else if location.y <= midY {
            playOneShot(.midtap)
        } else {
            playOneShot(.bottomtap)
        }
    }

    func playEmotion(_ asset: VideoAsset) {
        guard !micEnabled, !isSpeaking else { return }
        playOneShot(asset)
    }

    func resetToIdle() {
        if micEnabled {
            endVoiceSession()
            return
        }
        bannerText = nil
        isSpeaking = false
        isProcessingAudio = false
        video.playLoop(.foxidle)
    }

    func toggleMic() {
        micEnabled ? endVoiceSession() : startVoiceSession()
    }

    func startListening() {
        if !micEnabled {
            startVoiceSession()
        }
    }

    func refreshHistory() async {
        guard api.hasConfiguredBaseURL else {
            historySessions = []
            return
        }
        guard await ensureAuthenticatedIfNeeded(reason: "history_refresh") else {
            historySessions = []
            return
        }
        do {
            historySessions = try await api.listPracticeSessions()
            clearNetworkBanner()
        } catch {
            presentNetworkError(error, fallback: "Couldn't load your history right now.")
        }
    }

    func fetchDetail(session: PracticeSessionSummary) async throws -> PracticeSessionDetail {
        guard await ensureAuthenticatedIfNeeded(reason: "history_detail") else {
            throw URLError(.userAuthenticationRequired)
        }
        let detail = try await api.getPracticeSession(session: session)
        debugLog(
            .session,
            "detail fetched sessionId=\(foxShortID(detail.id)) status=\(detail.status.rawValue) stage=\(detail.processingStage ?? "nil") reason=\(foxPreview(detail.failureReason, limit: 80)) feedbackChars=\(detail.feedbackOverall.count) summaryChars=\(detail.summary.count) transcriptCount=\(detail.transcript.count)"
        )
        return detail
    }

    func markSessionRead(_ detail: PracticeSessionDetail) async {
        guard detail.isUnread else { return }
        guard await ensureAuthenticatedIfNeeded(reason: "history_mark_read") else { return }
        do {
            try await api.markSessionRead(sessionId: detail.id, version: detail.resultVersion)
            if let index = historySessions.firstIndex(where: { $0.id == detail.id }) {
                historySessions[index].lastReadVersion = detail.resultVersion
            }
            await refreshHistorySync()
        } catch {
            presentNetworkError(error, fallback: "Couldn't update that history item.")
        }
    }

    func didViewSessionDetail(_ detail: PracticeSessionDetail) {
        debugLog(
            .history,
            "detail viewed sessionId=\(foxShortID(detail.id)) status=\(detail.status.rawValue) stage=\(detail.processingStage ?? "nil")"
        )
    }

    func recordMainPageEntryIfNeeded() {
        guard !showOnboarding, isAppActive else { return }
        guard !didRecordMainPageEntryThisActiveCycle else { return }
        didRecordMainPageEntryThisActiveCycle = true

        let defaults = UserDefaults.standard
        let entryCount = defaults.integer(forKey: FoxStorageKeys.reviewMainPageEntryCount) + 1
        defaults.set(entryCount, forKey: FoxStorageKeys.reviewMainPageEntryCount)
        debugLog(.ui, "main page entered count=\(entryCount)")

        guard entryCount >= ReviewPromptConfig.mainPageEntryThreshold else { return }
        guard !defaults.bool(forKey: FoxStorageKeys.reviewPromptShown) else {
            debugLog(.ui, "review prompt skipped reason=already_shown")
            return
        }

        reviewRequestToken += 1
        debugLog(.ui, "review prompt requested mainPageEntries=\(entryCount)")
    }

    func markRatePromptShown() {
        UserDefaults.standard.set(true, forKey: FoxStorageKeys.reviewPromptShown)
        debugLog(.ui, "review prompt marked shown")
    }

    func retrySession(_ session: PracticeSessionSummary) async {
        guard await ensureAuthenticatedIfNeeded(reason: "history_retry") else { return }
        do {
            let response = try await api.retryPracticeSession(sessionId: session.id)
            debugLog(
                .history,
                "retry success sessionId=\(foxShortID(response.sessionId)) status=\(response.status.rawValue) stage=\(response.processingStage ?? "nil")"
            )
            bannerText = "Retry requested. We'll refresh this session when it's ready."
            await refreshHistorySync()
            await refreshHistory()
        } catch {
            presentNetworkError(error, fallback: "Couldn't retry that session right now.")
        }
    }

    func deleteSession(_ session: PracticeSessionSummary) async {
        guard await ensureAuthenticatedIfNeeded(reason: "history_delete") else { return }
        do {
            try await api.deletePracticeSession(sessionId: session.id)
            debugLog(.history, "delete success sessionId=\(foxShortID(session.id))")
            historySessions.removeAll { $0.id == session.id }
            await refreshHistorySync()
        } catch {
            presentNetworkError(error, fallback: "Couldn't delete that session right now.")
        }
    }

    var micPermissionBannerText: String? {
        switch micPermissionStatus {
        case .denied:
            return "Microphone permission denied. Enable it in Settings to start practicing."
        case .timedOut:
            return "Microphone permission timed out. Open Settings and enable microphone access."
        default:
            return bannerText
        }
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        debugLog(.auth, "bootstrap start deviceId=\(foxShortID(deviceId))")

        guard api.hasConfiguredBaseURL else {
            debugLog("Skipping bootstrap because backend base URL is not configured")
            return
        }

        do {
            let auth = try await api.authenticateAnonymous(deviceId: deviceId)
            debugLog(.auth, "bootstrap authed userId=\(foxShortID(auth.userId)) deviceId=\(foxShortID(auth.deviceId))")
            let device = try await api.registerDevice(deviceId: deviceId)
            debugLog(.auth, "device registered deviceId=\(foxShortID(device.deviceId))")
            if let remoteProfile = try? await api.fetchProfile() {
                profile = remoteProfile
                persistLocalProfile()
            }
            connectHistoryPushIfNeeded()
            startHistoryPolling()
            await refreshHistorySync()
            clearNetworkBanner()
            debugLog(.auth, "bootstrap complete")
        } catch {
            presentNetworkError(error, fallback: "Couldn't connect to the server right now.")
        }
    }

    private func startVoiceSession() {
        guard api.hasConfiguredBaseURL else {
            bannerText = "Connect your backend before starting practice."
            return
        }
        debugLog(
            .session,
            "start requested deviceId=\(foxShortID(deviceId)) native=\(profile.nativeLanguage.rawValue) target=\(profile.targetLanguage.rawValue) persona=\(profile.persona.backendName)"
        )
        micEnabled = true
        isSpeaking = false
        isProcessingAudio = false
        bannerText = nil

        Task {
            guard await ensureAuthenticatedIfNeeded(reason: "start_voice_session") else {
                micEnabled = false
                return
            }
            do {
                let created = try await api.createPracticeSession(profile: profile, deviceId: deviceId)
                currentSessionId = created.sessionId
                liveTranscript = []
                lastLiveTranscriptDedupKey = nil
                waitingForFinalizeRecording = false
                finalizeWaitTask?.cancel()
                debugSessionStage("live_active", sessionId: created.sessionId, extra: "backendStatus=\(created.status.rawValue)")
                debugLog(
                    .session,
                    "create success sessionId=\(foxShortID(created.sessionId)) status=\(created.status.rawValue) native=\(profile.nativeLanguage.rawValue) target=\(profile.targetLanguage.rawValue) persona=\(profile.persona.backendName)"
                )
                ensureGeminiConnected()
                requestMicPermission()
            } catch {
                micEnabled = false
                presentNetworkError(error, fallback: "Couldn't start practice right now.")
            }
        }
    }

    private func endVoiceSession() {
        debugLog(.session, "end requested sessionId=\(foxShortID(currentSessionId)) micEnabled=\(micEnabled) transcriptCount=\(liveTranscript.count)")
        micEnabled = false
        isSpeaking = false
        isProcessingAudio = false
        micPermissionStatus = .idle
        permissionTimeoutTask?.cancel()
        video.playLoop(.foxidle)
        gemini.endSession()
    }

    private func ensureGeminiConnected() {
        guard !gemini.isConnected else {
            gemini.startMicrophone()
            return
        }
        guard let sessionId = currentSessionId,
              let wsURL = api.realtimeWebSocketURL(sessionId: sessionId) else {
            bannerText = "Realtime websocket URL is unavailable."
            return
        }
        debugLog(
            .realtime,
            "connect requested sessionId=\(foxShortID(sessionId)) url=\(foxPreview(foxRedactToken(in: wsURL.absoluteString), limit: 180))"
        )

        let model = ProcessInfo.processInfo.environment["FOX_LIVE_MODEL"] ?? "models/gemini-2.5-flash-native-audio-preview-12-2025"
        let configuration = GeminiLiveClient.Configuration(
            webSocketURL: wsURL,
            model: model,
            responseModalities: ["AUDIO"],
            authToken: api.currentToken(),
            inputAudioMimeType: nil,
            outputAudioMimeType: nil,
            realtimeChunkMimeType: "audio/pcm;rate=16000",
            voiceName: nil,
            mediaResolution: nil,
            contextWindowTriggerTokens: nil,
            contextWindowTargetTokens: nil,
            allowAudioStreaming: true
        )
        gemini.connect(configuration: configuration)
    }

    private func requestMicPermission() {
        micPermissionStatus = .requesting
        debugLog(.audio, "mic permission request")
        permissionTimeoutTask?.cancel()
        permissionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await MainActor.run {
                guard let self, self.micPermissionStatus == .requesting else { return }
                self.micPermissionStatus = .timedOut
                debugLog(.audio, "mic permission timeout")
                self.endVoiceSession()
            }
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                self.permissionTimeoutTask?.cancel()
                if granted {
                    self.micPermissionStatus = .granted
                    debugLog(.audio, "mic permission granted")
                    if self.micEnabled {
                        self.gemini.startMicrophone()
                    }
                } else {
                    self.micPermissionStatus = .denied
                    debugLog(.audio, "mic permission denied")
                    self.endVoiceSession()
                }
            }
        }
    }

    private func bindGeminiCallbacks() {
        gemini.onUserSpeechStart = { [weak self] in
            Task { @MainActor in
                debugLog(.audio, "vad speech start sessionId=\(foxShortID(self?.currentSessionId))")
                self?.isProcessingAudio = true
            }
        }
        gemini.onUserSpeechEnd = { [weak self] in
            Task { @MainActor in
                debugLog(.audio, "vad speech end sessionId=\(foxShortID(self?.currentSessionId))")
                if self?.isSpeaking != true {
                    self?.isProcessingAudio = false
                }
            }
        }
        gemini.onResponseStart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                debugLog(.realtime, "response start sessionId=\(foxShortID(self.currentSessionId))")
                self.isSpeaking = true
                self.isProcessingAudio = true
                self.video.playLoop(.foxspeaking)
            }
        }
        gemini.onResponseEnd = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                debugLog(.realtime, "response end sessionId=\(foxShortID(self.currentSessionId))")
                self.isSpeaking = false
                self.isProcessingAudio = self.micEnabled
                self.video.playLoop(.foxidle)
            }
        }
        gemini.onAudioFileReady = { [weak self] preparedAudio in
            Task { @MainActor in
                debugLog(
                    .audio,
                    "recording ready sessionId=\(foxShortID(self?.currentSessionId)) sttFile=\(preparedAudio.sttInputURL.lastPathComponent) archiveFile=\(preparedAudio.archiveURL?.lastPathComponent ?? "nil") durationSec=\(preparedAudio.durationSec) route=\(preparedAudio.outputRoute.rawValue)"
                )
                self?.waitingForFinalizeRecording = false
                self?.finalizeWaitTask?.cancel()
                self?.debugSessionStage(
                    "recording_ready",
                    sessionId: self?.currentSessionId,
                    extra: "durationSec=\(preparedAudio.durationSec) route=\(preparedAudio.outputRoute.rawValue) sttInput=\(preparedAudio.sttInputSource) archive=\(preparedAudio.archiveSource ?? "nil")"
                )
                await self?.finalizeCurrentSession(preparedAudio: preparedAudio, source: "audio_ready")
            }
        }
        gemini.onFinalTranscript = { [weak self] segment in
            Task { @MainActor in
                debugLog(
                    .realtime,
                    "final transcript sessionId=\(foxShortID(self?.currentSessionId)) speaker=\(segment.speaker.rawValue) chars=\(segment.text.count)"
                )
                self?.appendLiveTranscriptIfNeeded(segment)
            }
        }
        gemini.onProtocolError = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                self.pendingRealtimeFailureMessage = trimmed.isEmpty ? nil : trimmed
                self.isSpeaking = false
                self.isProcessingAudio = false
                self.video.playLoop(.foxidle)
                self.bannerText = trimmed.isEmpty
                    ? "This practice session failed."
                    : "This practice session failed. \(trimmed)"
            }
        }
        gemini.onSessionClosed = { [weak self] in
            Task { @MainActor in
                guard let self, let sessionId = self.currentSessionId else { return }
                if self.waitingForFinalizeRecording {
                    debugLog(.session, "ws close ignored sessionId=\(foxShortID(sessionId)) reason=already_waiting_for_recording")
                    return
                }
                debugLog(.session, "ws closed sessionId=\(foxShortID(sessionId))")
                self.waitingForFinalizeRecording = true
                self.debugSessionStage("waiting_for_recording", sessionId: sessionId, extra: "source=ws_close")
                self.finalizeWaitTask?.cancel()
                self.finalizeWaitTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    await MainActor.run {
                        guard let self,
                              self.waitingForFinalizeRecording,
                              self.currentSessionId == sessionId,
                              !self.isFinalizingCurrentSession else { return }
                        self.debugSessionStage("finalizing", sessionId: sessionId, extra: "source=ws_close_timeout")
                        Task {
                            await self.finalizeCurrentSessionIfNeeded(durationSec: nil, source: "ws_close_timeout")
                        }
                    }
                }
            }
        }
    }

    private func bindHistoryPush() {
        historyPush.onEvent = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                debugLog(
                    .history,
                    "push event type=\(event.type) sessionId=\(foxShortID(event.sessionId)) status=\(event.status?.rawValue ?? "nil") stage=\(event.processingStage ?? "nil") version=\(event.resultVersion ?? 0)"
                )
                await self.refreshHistorySync()
                if self.showHistory {
                    await self.refreshHistory()
                }
            }
        }
        historyPush.onConnectionChange = { connected in
            debugLog(.history, "push connected=\(connected)")
        }
    }

    private func connectHistoryPushIfNeeded() {
        guard isAppActive, let url = api.historyWebSocketURL() else { return }
        debugLog(.history, "push connect requested url=\(foxPreview(foxRedactToken(in: url.absoluteString), limit: 180))")
        historyPush.connect(url: url, authToken: api.currentToken())
    }

    private func startHistoryPolling() {
        guard historyPollTask == nil else { return }
        historyPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                await MainActor.run {
                    guard self.isAppActive else { return }
                    Task {
                        await self.refreshHistorySync()
                        if self.showHistory {
                            await self.refreshHistory()
                        }
                    }
                }
            }
        }
    }

    private func refreshHistorySync() async {
        guard api.hasConfiguredBaseURL else {
            historySyncStatus = .empty
            hasUnreadHistory = false
            return
        }
        guard await ensureAuthenticatedIfNeeded(reason: "history_sync") else {
            historySyncStatus = .empty
            hasUnreadHistory = false
            return
        }
        do {
            historySyncStatus = try await api.getHistorySyncStatus()
            hasUnreadHistory = historySyncStatus.hasUnread
            clearNetworkBanner()
            debugLog(
                .history,
                "sync applied hasUnread=\(historySyncStatus.hasUnread) unread=\(historySyncStatus.unreadCount) processing=\(historySyncStatus.processingCount)"
            )
        } catch {
            presentNetworkError(error, fallback: "Couldn't refresh your history status.")
        }
    }

    private func finalizeCurrentSession(preparedAudio: GeminiLiveClient.PreparedConversationAudio, source: String) async {
        guard let sessionId = currentSessionId else {
            preparedAudio.cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            return
        }
        defer {
            preparedAudio.cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        var audioURL: String?
        do {
            debugSessionStage(
                "uploading_audio",
                sessionId: sessionId,
                extra: "durationSec=\(preparedAudio.durationSec) route=\(preparedAudio.outputRoute.rawValue) sttInput=\(preparedAudio.sttInputSource) archive=\(preparedAudio.archiveSource ?? "nil")"
            )
            debugLog(
                .session,
                "audio upload start sessionId=\(foxShortID(sessionId)) sttFile=\(preparedAudio.sttInputURL.lastPathComponent) archiveFile=\(preparedAudio.archiveURL?.lastPathComponent ?? "nil") durationSec=\(preparedAudio.durationSec) route=\(preparedAudio.outputRoute.rawValue)"
            )
            audioURL = try await api.uploadSessionAudio(sessionId: sessionId, fileURL: preparedAudio.sttInputURL, durationSec: preparedAudio.durationSec)
            debugLog(
                .session,
                "audio upload success sessionId=\(foxShortID(sessionId)) hasAudioURL=\(audioURL != nil) sttInput=\(preparedAudio.sttInputSource) archive=\(preparedAudio.archiveSource ?? "nil")"
            )
        } catch {
            debugLog(.session, "audio upload failed sessionId=\(foxShortID(sessionId)) error=\(error.localizedDescription)")
        }
        await finalizeCurrentSessionIfNeeded(durationSec: preparedAudio.durationSec, audioURL: audioURL, source: source)
    }

    private func finalizeCurrentSessionIfNeeded(durationSec: Int?, audioURL: String? = nil, source: String) async {
        guard let sessionId = currentSessionId else { return }
        guard !isFinalizingCurrentSession else { return }
        isFinalizingCurrentSession = true
        waitingForFinalizeRecording = false
        finalizeWaitTask?.cancel()
        debugSessionStage("finalizing", sessionId: sessionId, extra: "source=\(source)")
        if liveTranscript.isEmpty {
            debugLog(.session, "finalize warning sessionId=\(foxShortID(sessionId)) emptyTranscript=true source=\(source)")
        }
        debugLog(
            .session,
            "finalize start sessionId=\(foxShortID(sessionId)) transcriptCount=\(liveTranscript.count) durationSec=\(durationSec ?? 0) hasAudioURL=\(audioURL != nil) source=\(source)"
        )
        defer {
            currentSessionId = nil
            liveTranscript.removeAll()
            lastLiveTranscriptDedupKey = nil
            isFinalizingCurrentSession = false
            pendingRealtimeFailureMessage = nil
            waitingForFinalizeRecording = false
            finalizeWaitTask?.cancel()
        }

        do {
            let response = try await api.finalizeSession(
                sessionId: sessionId,
                transcript: liveTranscript,
                durationSec: durationSec,
                audioURL: audioURL
            )
            debugLog(
                .session,
                "finalize response sessionId=\(foxShortID(sessionId)) status=\(response.status.rawValue) stage=\(response.processingStage ?? "nil") source=\(source)"
            )
            debugSessionStage("waiting_for_result", sessionId: sessionId, extra: "backendStatus=\(response.status.rawValue) backendStage=\(response.processingStage ?? "nil")")
            debugLog(.session, "finalize success sessionId=\(foxShortID(sessionId))")
            await refreshHistorySync()
            await refreshHistory()
        } catch {
            presentNetworkError(error, fallback: "Couldn't finish processing this session.")
        }
    }

    private func playOneShot(_ asset: VideoAsset) {
        video.playOnceThenLoop(asset, loop: .foxidle)
    }

    private func loadLocalProfile() {
        let defaults = UserDefaults.standard
        showOnboarding = !defaults.bool(forKey: FoxStorageKeys.onboardingCompleted)
        guard let data = defaults.data(forKey: FoxStorageKeys.localProfile),
              let saved = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return
        }
        profile = saved
    }

    private func persistLocalProfile() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: FoxStorageKeys.localProfile)
        }
    }

    private func presentNetworkError(_ error: Error, fallback: String) {
        debugLog(.error, "network error: \(error.localizedDescription)")

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                bannerText = "Couldn't reach the server. Check your connection and try again."
                return
            case .timedOut:
                bannerText = "The request timed out. Please try again."
                return
            default:
                break
            }
        }

        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            bannerText = localized
        } else {
            bannerText = fallback
        }
    }

    private func clearNetworkBanner() {
        bannerText = nil
    }

    private func debugSessionStage(_ stage: String, sessionId: String?, extra: String? = nil) {
        let suffix = extra.map { " \($0)" } ?? ""
        debugLog(.session, "stage=\(stage) sessionId=\(foxShortID(sessionId))\(suffix)")
    }

    private func appendLiveTranscriptIfNeeded(_ segment: TranscriptSegment) {
        let dedupKey = liveTranscriptDedupKey(for: segment)
        if dedupKey == lastLiveTranscriptDedupKey {
            debugLog(
                .realtime,
                "final transcript deduped sessionId=\(foxShortID(currentSessionId)) speaker=\(segment.speaker.rawValue) chars=\(segment.text.count)"
            )
            return
        }
        liveTranscript.append(segment)
        lastLiveTranscriptDedupKey = dedupKey
    }

    private func liveTranscriptDedupKey(for segment: TranscriptSegment) -> String {
        let normalizedText = segment.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "\(segment.speaker.rawValue)|\(normalizedText)"
    }

    private func ensureAuthenticatedIfNeeded(reason: String) async -> Bool {
        guard api.hasConfiguredBaseURL else { return false }
        if api.currentToken() != nil {
            return true
        }
        if let authRecoveryTask {
            return await authRecoveryTask.value
        }

        debugLog(.auth, "auth recovery start reason=\(reason) deviceId=\(foxShortID(deviceId))")
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            do {
                let auth = try await self.api.authenticateAnonymous(deviceId: self.deviceId)
                debugLog(.auth, "auth recovery success userId=\(foxShortID(auth.userId)) deviceId=\(foxShortID(auth.deviceId))")
                let device = try await self.api.registerDevice(deviceId: self.deviceId)
                debugLog(.auth, "auth recovery device registered deviceId=\(foxShortID(device.deviceId))")
                self.connectHistoryPushIfNeeded()
                self.startHistoryPolling()
                self.clearNetworkBanner()
                return true
            } catch {
                self.presentNetworkError(error, fallback: "Couldn't connect to the server right now.")
                return false
            }
        }
        authRecoveryTask = task
        let success = await task.value
        authRecoveryTask = nil
        return success
    }
}
