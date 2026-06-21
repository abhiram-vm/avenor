import SwiftUI
import MetalKit

struct MetalParticleViewRepresentable: NSViewRepresentable {
    let view: MetalParticleView
    var reduceMotion: Bool

    func makeNSView(context: Context) -> MetalParticleView {
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ nsView: MetalParticleView, context: Context) {
        nsView.reduceMotion = reduceMotion
    }
}
