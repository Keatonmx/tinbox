//
//  MetalRenderer.swift
//  Tinbox
//
//  Uploads the latest FrameStore frame into an MTLTexture and draws a
//  fullscreen quad. Scaling modes change the quad geometry; filters are
//  fragment-shader variants (see Shaders.metal).
//

import Foundation
import Metal
import MetalKit
import simd

struct RendererUniforms {
    var quadScale: SIMD2<Float>
    var textureSize: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var filter: Int32
    var opacity: Float
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let texture: MTLTexture
    private let frameStore: FrameStore
    private var lastFrameIndex: UInt64 = .max

    var scaling: DisplayScaling = .pixelPerfect
    var filter: ScreenFilter = .none
    var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

    init?(frameStore: FrameStore) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "tinbox_vertex"),
              let fragment = library.makeFunction(name: "tinbox_fragment") else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.frameStore = frameStore

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.pipeline = pipeline

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: frameStore.width, height: frameStore.height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        self.texture = texture
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Upload only when the emulation thread published a new frame.
        if frameStore.latestFrameIndex != lastFrameIndex {
            lastFrameIndex = frameStore.read { pixels, width, height in
                let region = MTLRegionMake2D(0, 0, width, height)
                texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
            }
        }

        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        passDescriptor.colorAttachments[0].clearColor = clearColor
        passDescriptor.colorAttachments[0].loadAction = .clear

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        var uniforms = makeUniforms(drawableSize: view.drawableSize)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RendererUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Quad geometry for the current scaling mode.
    private func makeUniforms(drawableSize: CGSize) -> RendererUniforms {
        let viewW = Float(max(drawableSize.width, 1))
        let viewH = Float(max(drawableSize.height, 1))
        let texW = Float(frameStore.width)
        let texH = Float(frameStore.height)

        var quadW: Float
        var quadH: Float
        switch scaling {
        case .stretch:
            quadW = viewW
            quadH = viewH
        case .fit:
            let scale = min(viewW / texW, viewH / texH)
            quadW = texW * scale
            quadH = texH * scale
        case .wide:
            // 10 % wider than 3:2 (1.65:1), fitted to the view.
            let targetW = texH * 1.65
            let scale = min(viewW / targetW, viewH / texH)
            quadW = targetW * scale
            quadH = texH * scale
        case .pixelPerfect:
            // Largest integer multiple that fits; fall back to "fit" when the
            // view is smaller than one texture (never on an iPhone).
            let scale = floor(min(viewW / texW, viewH / texH))
            if scale >= 1 {
                quadW = texW * scale
                quadH = texH * scale
            } else {
                let s = min(viewW / texW, viewH / texH)
                quadW = texW * s
                quadH = texH * s
            }
        }

        return RendererUniforms(
            quadScale: SIMD2<Float>(quadW / viewW, quadH / viewH),
            textureSize: SIMD2<Float>(texW, texH),
            outputSize: SIMD2<Float>(quadW, quadH),
            filter: filter.shaderIndex,
            opacity: 1)
    }
}
