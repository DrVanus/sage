//
//  MetalPerlinNoiseView.swift
//  CSAI1
//
//  Created by DM on 3/25/25.
//  Updated on 4/02/25
//
//  GPU-accelerated Perlin noise for premium background texture.
//  Used as an overlay in Theme.swift to add subtle organic movement.
//

import SwiftUI
import MetalKit
import Combine

// MARK: - MetalPerlinNoiseView

struct MetalPerlinNoiseView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        // Gracefully handle devices without Metal support
        guard let device = MTLCreateSystemDefaultDevice() else {
            // Return a fallback view with an animated gradient background
            return MetalFallbackView()
        }
        
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.backgroundColor = .clear
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0) // Transparent for overlay
        mtkView.isOpaque = false // Allow transparency
        
        // Create and assign the renderer - handle initialization failures gracefully
        guard let renderer = PerlinNoiseRenderer(mtkView: mtkView) else {
            // Return fallback if renderer fails to initialize
            return MetalFallbackView()
        }
        
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.mtkView = mtkView
        
        // MEMORY FIX: Reduced from 15 to 8 FPS. This is a subtle background effect -
        // 8 FPS is visually indistinguishable but halves GPU command buffer allocations.
        // Each frame allocates a command buffer that stays in memory until GPU completes.
        mtkView.preferredFramesPerSecond = 8
        
        // Enable display link pausing when not visible
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        
        // MEMORY FIX: Limit drawable size to reduce GPU memory.
        // Full-res on iPhone 15 Pro Max = 1290x2796 = 14.4MB per buffer.
        // At 512x512 (for a subtle noise overlay), it's only 1MB per buffer.
        // This saves ~30-40MB of GPU memory with triple buffering.
        // CRITICAL: Must disable autoResizeDrawable BEFORE setting drawableSize,
        // otherwise MTKView resets drawableSize to full screen resolution on every layout pass.
        mtkView.autoResizeDrawable = false
        mtkView.drawableSize = CGSize(width: 512, height: 512)
        
        return mtkView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No dynamic updates required
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var renderer: PerlinNoiseRenderer?
        weak var mtkView: MTKView?
        private var appStateObservers = Set<AnyCancellable>()
        
        init() {
            // Pause rendering when app enters background to save battery
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    self?.mtkView?.isPaused = true
                }
                .store(in: &appStateObservers)
            
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    self?.mtkView?.isPaused = false
                }
                .store(in: &appStateObservers)
            
            // MEMORY FIX: Pause rendering on memory warning to free GPU resources
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
                .sink { [weak self] _ in
                    self?.mtkView?.isPaused = true
                    // Resume after a delay to allow memory to stabilize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        self?.mtkView?.isPaused = false
                    }
                }
                .store(in: &appStateObservers)
        }
    }
}

// MARK: - Fallback View

/// A fallback view that displays an animated gradient when Metal is unavailable.
/// This ensures the app doesn't crash on older devices or simulators without Metal.
private class MetalFallbackView: UIView {
    private let gradientLayer = CAGradientLayer()
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        
        // Create a subtle animated gradient that mimics the noise aesthetic
        gradientLayer.colors = [
            UIColor(white: 0.5, alpha: 0.02).cgColor,
            UIColor(white: 0.6, alpha: 0.04).cgColor,
            UIColor(white: 0.4, alpha: 0.02).cgColor,
            UIColor(white: 0.55, alpha: 0.03).cgColor
        ]
        gradientLayer.locations = [0.0, 0.3, 0.6, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.type = .axial
        layer.addSublayer(gradientLayer)
        
        // Subtle animation
        startAnimation()
    }
    
    private func startAnimation() {
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateGradient))
        displayLink?.preferredFramesPerSecond = 10 // Low frame rate for subtle effect
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updateGradient() {
        let elapsed = CACurrentMediaTime() - startTime
        let shift = sin(elapsed * 0.3) * 0.1 // Slow, subtle shift
        
        gradientLayer.startPoint = CGPoint(x: shift, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1 + shift, y: 1)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            startAnimation()
        }
    }
    
    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - Perlin Noise Renderer

class PerlinNoiseRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    
    struct Uniforms {
        var time: Float
        var resolution: SIMD2<Float>
    }
    
    /// Failable initializer - returns nil if Metal resources can't be created
    init?(mtkView: MTKView) {
        guard let device = mtkView.device else {
            #if DEBUG
            print("[MetalPerlinNoiseView] No Metal device available - using fallback")
            #endif
            return nil
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            #if DEBUG
            print("[MetalPerlinNoiseView] Could not create command queue - using fallback")
            #endif
            return nil
        }
        self.commandQueue = queue
        
        super.init()
        
        // Try to build pipeline state, return nil if it fails
        if !buildPipelineState(mtkView: mtkView) {
            return nil
        }
    }
    
    /// Builds the render pipeline state
    /// - Returns: true if successful, false if any step fails
    private func buildPipelineState(mtkView: MTKView) -> Bool {
        // Load the default Metal library
        guard let library = device.makeDefaultLibrary() else {
            #if DEBUG
            print("[MetalPerlinNoiseView] Could not create default Metal library - using fallback")
            #endif
            return false
        }
        
        guard let vertexFunction = library.makeFunction(name: "v_main"),
              let fragmentFunction = library.makeFunction(name: "f_main") else {
            #if DEBUG
            print("[MetalPerlinNoiseView] Could not find shader functions - using fallback")
            #endif
            return false
        }
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunction
        pipelineDesc.fragmentFunction = fragmentFunction
        pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        // Enable alpha blending for transparency
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
            return true
        } catch {
            #if DEBUG
            print("[MetalPerlinNoiseView] Failed to create pipeline state: \(error.localizedDescription) - using fallback")
            #endif
            return false
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    func draw(in view: MTKView) {
        guard let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        
        // Use clear load action for transparent background
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        
        // Calculate elapsed time
        let currentTime = CACurrentMediaTime()
        let elapsed = Float(currentTime - startTime)
        
        // Prepare uniforms for shaders
        var uniforms = Uniforms(
            time: elapsed,
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)
        
        // Draw a full-screen triangle
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
