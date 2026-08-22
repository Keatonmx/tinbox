//
//  EmulatorViewController.swift
//  Tinbox
//
//  The one UIKit view controller in the app: hosts the MTKView that shows the
//  emulator output. Wrapped for SwiftUI by `EmulatorScreen`.
//

import UIKit
import MetalKit
import SwiftUI

final class EmulatorViewController: UIViewController {
    let frameStore: FrameStore
    private(set) var renderer: MetalRenderer?
    private var metalView: MTKView!

    init(frameStore: FrameStore) {
        self.frameStore = frameStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let renderer = MetalRenderer(frameStore: frameStore)
        self.renderer = renderer
        let view = MTKView(frame: .zero, device: renderer?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        view.isOpaque = true
        view.delegate = renderer
        view.isUserInteractionEnabled = false
        metalView = view
        self.view = view
    }

    func apply(scaling: DisplayScaling, filter: ScreenFilter) {
        renderer?.scaling = scaling
        renderer?.filter = filter
    }

    func setPaused(_ paused: Bool) {
        metalView.isPaused = paused
    }
}

/// SwiftUI wrapper. Place it where the game screen goes; it draws black bars
/// itself according to the scaling mode.
struct EmulatorScreen: UIViewControllerRepresentable {
    let frameStore: FrameStore
    var scaling: DisplayScaling
    var filter: ScreenFilter
    var paused: Bool = false

    func makeUIViewController(context: Context) -> EmulatorViewController {
        let vc = EmulatorViewController(frameStore: frameStore)
        vc.apply(scaling: scaling, filter: filter)
        return vc
    }

    func updateUIViewController(_ vc: EmulatorViewController, context: Context) {
        vc.apply(scaling: scaling, filter: filter)
        vc.setPaused(paused)
    }
}
