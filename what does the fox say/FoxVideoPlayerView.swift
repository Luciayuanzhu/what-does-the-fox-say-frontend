import AVFoundation
import SwiftUI

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            return AVPlayerLayer()
        }
        return layer
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

struct DualVideoPlayerView: View {
    @ObservedObject var controller: VideoPlaybackController
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    var body: some View {
        ZStack {
            VideoPlayerView(player: controller.primaryPlayer, videoGravity: videoGravity)
                .opacity(controller.primaryOpacity)

            VideoPlayerView(player: controller.secondaryPlayer, videoGravity: videoGravity)
                .opacity(controller.secondaryOpacity)
        }
    }
}
