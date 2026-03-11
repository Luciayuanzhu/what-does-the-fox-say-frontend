import AVFoundation
import Combine
import SwiftUI

@MainActor
/// Owns the dual-player video pipeline that drives idle loops, one-shot reactions, and speaking playback.
final class VideoPlaybackController: ObservableObject {
    let primaryPlayer: AVQueuePlayer
    let secondaryPlayer: AVQueuePlayer

    @Published var primaryOpacity: Double = 1.0
    @Published var secondaryOpacity: Double = 0.0

    private var primaryLooper: AVPlayerLooper?
    private var secondaryLooper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var readinessObservation: NSKeyValueObservation?
    private var loopBoundaryObserver: Any?
    private weak var loopBoundaryObservedPlayer: AVPlayer?
    private var loopBoundarySwitchTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var currentLoopURL: URL?
    private var requestedLoopAsset: VideoAsset?
    private var activeLoopAsset: VideoAsset?
    private var isTransitioningLoop = false
    private var activeIsPrimary: Bool = true
    private let speakingLoopPrewarmLeadTime = 0.08
    private let loopTransitionDuration = 0.06

    init() {
        primaryPlayer = AVQueuePlayer()
        secondaryPlayer = AVQueuePlayer()
        configure(player: primaryPlayer)
        configure(player: secondaryPlayer)
    }

    /// Starts or resumes a looping asset, reusing the active loop only when playback is already stable.
    func playLoop(_ asset: VideoAsset) {
        debugLog("video playLoop \(asset.rawValue)")
        let url = asset.url
        let isAlreadyStableLoop =
            currentLoopURL == url &&
            activeLoopAsset == asset &&
            activePlayer.currentItem != nil &&
            activePlayer.timeControlStatus != .paused &&
            !isTransitioningLoop
        if isAlreadyStableLoop {
            return
        }
        requestedLoopAsset = asset
        currentLoopURL = url
        isTransitioningLoop = true
        clearObservers()

        if asset == .foxspeaking {
            playSeamlessLoop(asset)
            return
        }

        let target = targetPlayerForNewPlayback()
        clearPlayer(target)
        let item = AVPlayerItem(url: url)
        Task { [weak self] in
            guard let self else { return }
            await self.setLooper(for: target, item: item, asset: asset)
            self.startWhenReady(player: target) { [weak self] in
                guard let self else { return }
                target.play()
                self.activatePlayer(target, animated: self.shouldAnimateTransition, duration: self.loopTransitionDuration)
                self.activeLoopAsset = asset
                self.isTransitioningLoop = false
            }
        }
    }

    /// Plays a one-shot clip without scheduling a follow-up loop.
    func playOnce(_ asset: VideoAsset, completion: (() -> Void)? = nil) {
        debugLog("video playOnce \(asset.rawValue)")
        currentLoopURL = nil
        requestedLoopAsset = nil
        activeLoopAsset = nil
        isTransitioningLoop = false
        clearObservers()

        let target = targetPlayerForNewPlayback()
        clearPlayer(target)

        let item = AVPlayerItem(url: asset.url)
        if let completion {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                completion()
            }
        }

        target.insert(item, after: nil)

        startWhenReady(player: target) { [weak self] in
            guard let self else { return }
            target.play()
            self.activatePlayer(target, animated: self.shouldAnimateTransition)
        }
    }

    /// Plays a one-shot clip and then hands control back to the requested looping asset.
    func playOnceThenLoop(_ once: VideoAsset, loop: VideoAsset, onLoopStart: (() -> Void)? = nil) {
        debugLog("video playOnceThenLoop \(once.rawValue) -> \(loop.rawValue)")
        let onceURL = once.url
        if onceURL == loop.url {
            playLoop(loop)
            onLoopStart?()
            return
        }

        currentLoopURL = nil
        requestedLoopAsset = nil
        activeLoopAsset = nil
        isTransitioningLoop = false
        clearObservers()

        let target = targetPlayerForNewPlayback()
        clearPlayer(target)

        let onceItem = AVPlayerItem(url: onceURL)
        target.insert(onceItem, after: nil)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: onceItem,
            queue: .main
            ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                debugLog("video playOnceThenLoop handoff -> \(loop.rawValue)")
                self.playLoop(loop)
                onLoopStart?()
            }
        }

        startWhenReady(player: target) { [weak self] in
            guard let self else { return }
            target.play()
            self.activatePlayer(target, animated: self.shouldAnimateTransition)
        }
    }

    /// Queues a short sequence of clips for cases where several animations must play back-to-back.
    func playSequence(_ assets: [VideoAsset], completion: (() -> Void)? = nil) {
        guard !assets.isEmpty else { return }
        debugLog("video playSequence \(assets.map { $0.rawValue }.joined(separator: ","))")
        currentLoopURL = nil
        requestedLoopAsset = nil
        activeLoopAsset = nil
        isTransitioningLoop = false
        clearObservers()

        let target = targetPlayerForNewPlayback()
        clearPlayer(target)

        let items = assets.map { AVPlayerItem(url: $0.url) }
        for item in items {
            target.insert(item, after: nil)
        }

        if let last = items.last, let completion {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: last,
                queue: .main
            ) { _ in
                completion()
            }
        }

        startWhenReady(player: target) { [weak self] in
            guard let self else { return }
            target.play()
            self.activatePlayer(target, animated: self.shouldAnimateTransition)
        }
    }

    /// Pauses both queue players without changing the currently requested asset state.
    func stop() {
        debugLog("video stop")
        primaryPlayer.pause()
        secondaryPlayer.pause()
        isTransitioningLoop = false
    }

    private func configure(player: AVQueuePlayer) {
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = true
        player.volume = 0
    }

    private var activePlayer: AVQueuePlayer {
        activeIsPrimary ? primaryPlayer : secondaryPlayer
    }

    private var inactivePlayer: AVQueuePlayer {
        activeIsPrimary ? secondaryPlayer : primaryPlayer
    }

    private var shouldAnimateTransition: Bool {
        activePlayer.currentItem != nil
    }

    private func targetPlayerForNewPlayback() -> AVQueuePlayer {
        shouldAnimateTransition ? inactivePlayer : activePlayer
    }

    /// Promotes one queue player to the visible layer and optionally crossfades away from the old one.
    private func activatePlayer(_ player: AVQueuePlayer, animated: Bool, duration: Double = 0.16) {
        let isPrimary = player === primaryPlayer
        let oldPlayer = activePlayer
        activeIsPrimary = isPrimary

        let update = {
            self.primaryOpacity = isPrimary ? 1.0 : 0.0
            self.secondaryOpacity = isPrimary ? 0.0 : 1.0
        }

        if animated {
            withAnimation(.easeInOut(duration: duration)) {
                update()
            }
            if oldPlayer !== player {
                scheduleCleanup(for: oldPlayer, delay: duration + 0.06)
            }
        } else {
            update()
            if oldPlayer !== player {
                clearPlayer(oldPlayer)
            }
        }
    }

    /// Clears the previously visible player after the current transition has finished.
    private func scheduleCleanup(for player: AVQueuePlayer, delay: Double = 0.22) {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.clearPlayer(player)
            }
        }
    }

    /// Resets a queue player so it can be reused for another loop or one-shot clip.
    private func clearPlayer(_ player: AVQueuePlayer) {
        if loopBoundaryObservedPlayer === player {
            clearLoopBoundaryObserver()
        }
        player.pause()
        player.removeAllItems()
        clearLooper(for: player)
    }

    /// Installs an AVPlayerLooper for the supplied asset and applies speaking trims when needed.
    private func setLooper(for player: AVQueuePlayer, item: AVPlayerItem, asset: VideoAsset) async {
        clearLooper(for: player)
        let looper: AVPlayerLooper
        if let loopTimeRange = await loopTimeRange(for: asset) {
            looper = AVPlayerLooper(player: player, templateItem: item, timeRange: loopTimeRange)
        } else {
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
        if player === primaryPlayer {
            primaryLooper = looper
        } else {
            secondaryLooper = looper
        }
    }

    /// Returns a trimmed time range for assets whose file boundaries need loop cleanup.
    private func loopTimeRange(for asset: VideoAsset) async -> CMTimeRange? {
        // foxspeaking has a visible seam at file boundaries; trim a few boundary frames.
        guard asset == .foxspeaking else { return nil }
        let avAsset = AVURLAsset(url: asset.url)
        guard let duration = try? await avAsset.load(.duration) else { return nil }
        guard duration.isNumeric && duration.seconds > 0 else { return nil }

        let startTrim = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let endTrim = CMTime(seconds: 2.0 / 30.0, preferredTimescale: 600)
        let available = duration - startTrim - endTrim
        guard available.seconds > 0.20 else { return nil }

        return CMTimeRange(start: startTrim, duration: available)
    }

    private func clearLooper(for player: AVQueuePlayer) {
        if player === primaryPlayer {
            primaryLooper = nil
        } else {
            secondaryLooper = nil
        }
    }

    /// Waits until the active AVPlayerItem is ready before starting playback or transitions.
    private func startWhenReady(player: AVQueuePlayer, onReady: @escaping () -> Void) {
        guard let item = player.currentItem else {
            onReady()
            return
        }

        if item.status == .readyToPlay {
            onReady()
            return
        }

        readinessObservation = item.observe(\.status, options: [.new, .initial]) { item, _ in
            if item.status == .readyToPlay || item.status == .failed {
                Task { @MainActor in
                    debugLog("video item status \(item.status.rawValue)")
                    onReady()
                }
            }
        }
    }

    /// Tears down playback observers that should not survive between clip changes.
    private func clearObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        readinessObservation = nil
        clearLoopBoundaryObserver()
    }

    /// Removes the speaking-loop boundary observer and cancels any pending boundary handoff task.
    private func clearLoopBoundaryObserver() {
        loopBoundarySwitchTask?.cancel()
        loopBoundarySwitchTask = nil
        if let observer = loopBoundaryObserver, let player = loopBoundaryObservedPlayer {
            player.removeTimeObserver(observer)
        }
        loopBoundaryObserver = nil
        loopBoundaryObservedPlayer = nil
    }

    /// Starts the speaking loop path that prewarms the next iteration before the boundary seam.
    private func playSeamlessLoop(_ asset: VideoAsset) {
        let target = targetPlayerForNewPlayback()
        clearPlayer(target)
        let item = AVPlayerItem(url: asset.url)
        target.insert(item, after: nil)

        Task { [weak self] in
            guard let self else { return }
            let loopRange = await self.loopTimeRange(for: asset)
            self.startWhenReady(player: target) { [weak self] in
                guard let self else { return }
                self.seekAndPrepare(player: target, loopRange: loopRange) { [weak self] in
                    guard let self else { return }
                    target.play()
                    self.activatePlayer(target, animated: self.shouldAnimateTransition)
                    self.activeLoopAsset = asset
                    self.isTransitioningLoop = false
                    self.installLoopBoundaryObserver(for: target, asset: asset, loopRange: loopRange)
                }
            }
        }
    }

    /// Seeks a player to the loop start and prerolls it so the visual handoff can happen cleanly.
    private func seekAndPrepare(player: AVQueuePlayer, loopRange: CMTimeRange?, completion: @escaping () -> Void) {
        let start = loopRange?.start ?? .zero
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.pause()
            player.preroll(atRate: 1.0) { _ in }
            completion()
        }
    }

    /// Installs the observer that prepares the next speaking-loop iteration before the current pass ends.
    private func installLoopBoundaryObserver(for player: AVQueuePlayer, asset: VideoAsset, loopRange: CMTimeRange?) {
        clearLoopBoundaryObserver()
        guard asset == .foxspeaking else { return }

        let duration = loopRange?.duration ?? player.currentItem?.duration ?? .zero
        let start = loopRange?.start ?? .zero
        guard duration.isNumeric && duration.seconds > speakingLoopPrewarmLeadTime else { return }

        let prewarmLead = CMTime(seconds: speakingLoopPrewarmLeadTime, preferredTimescale: 600)
        let boundaryTime = start + duration - prewarmLead
        guard boundaryTime > start else { return }

        loopBoundaryObservedPlayer = player
        loopBoundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: boundaryTime)],
            queue: .main
        ) { [weak self, weak player] in
            guard let self, let player else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleLoopBoundaryReached(from: player, asset: asset, loopRange: loopRange)
            }
        }
    }

    /// Prewarms the next speaking-loop player and swaps to it at the seam boundary.
    private func handleLoopBoundaryReached(from player: AVQueuePlayer, asset: VideoAsset, loopRange: CMTimeRange?) {
        guard currentLoopURL == asset.url else { return }
        guard player === activePlayer else { return }
        isTransitioningLoop = true

        let target = inactivePlayer
        clearPlayer(target)
        let item = AVPlayerItem(url: asset.url)
        target.insert(item, after: nil)

        startWhenReady(player: target) { [weak self] in
            guard let self else { return }
            self.seekAndPrepare(player: target, loopRange: loopRange) { [weak self] in
                guard let self else { return }
                debugLog("video seamless speaking loop prewarm=\(self.speakingLoopPrewarmLeadTime)s")
                let prewarmLeadTime = self.speakingLoopPrewarmLeadTime
                self.loopBoundarySwitchTask?.cancel()
                self.loopBoundarySwitchTask = Task { [weak self, weak target, weak player] in
                    try? await Task.sleep(nanoseconds: UInt64(prewarmLeadTime * 1_000_000_000))
                    await MainActor.run {
                        guard let self, let target, let player else { return }
                        guard self.currentLoopURL == asset.url, player === self.activePlayer else { return }
                        target.play()
                        self.activatePlayer(target, animated: false)
                        self.activeLoopAsset = asset
                        self.isTransitioningLoop = false
                        self.installLoopBoundaryObserver(for: target, asset: asset, loopRange: loopRange)
                    }
                }
            }
        }
    }
}
