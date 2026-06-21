import SwiftUI
import MetalKit

struct MetalOrbViewRepresentable: NSViewRepresentable {
    let view: MetalOrbView
    var reduceMotion: Bool

    func makeNSView(context: Context) -> MetalOrbView {
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ nsView: MetalOrbView, context: Context) {
        nsView.reduceMotion = reduceMotion
    }
}
