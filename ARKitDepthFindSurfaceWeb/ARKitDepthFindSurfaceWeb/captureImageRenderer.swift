//
//  captureImageRenderer.swift
//  ARKitDetphFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

//
// Ref> MetalCode: capturedImage.metal, IndexConstants: ShaderTypes.h
//
import Foundation
import MetalKit
import ARKit

class capturedImageRenderer
{
    // Vertex data for an image plane
    let kImagePlaneVertexData: [Float] = [
        -1.0, -1.0,  0.0, 1.0,
         1.0, -1.0,  1.0, 1.0,
        -1.0,  1.0,  0.0, 0.0,
         1.0,  1.0,  1.0, 0.0,
    ]
    
    var imagePlaneVertexBuffer: MTLBuffer!
    var capturedImagePipelineState: MTLRenderPipelineState!
    var capturedImageDepthState: MTLDepthStencilState!
    
    // Captured image texture cache
    var capturedImageTextureCache: CVMetalTextureCache!
    
    var capturedImageTextureY: CVMetalTexture?
    var capturedImageTextureCbCr: CVMetalTexture?
    
    init(metalDevice device: MTLDevice,_ defaultLibrary: MTLLibrary,_ renderDestination: RenderDestinationProvider)
    {
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexTransform")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentShader")!
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexVertex.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexVertex.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        // Create a depth state for rendering the captured image
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
    }
    
    private func _createTexture( fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture?
    {
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess { texture = nil }
        
        return texture
    }
    
    func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2 ) { return }
        
        capturedImageTextureY    = _createTexture( fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0 )
        capturedImageTextureCbCr = _createTexture( fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1 )
    }
    
    func updateImagePlane(frame: ARFrame, viewportSize: CGSize) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: .landscapeRight, viewportSize: viewportSize).inverted()
        
        let vertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(
                x: CGFloat(kImagePlaneVertexData[textureCoordIndex]),
                y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1])
            )
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder)
    {
        guard let textureY = capturedImageTextureY,
              let textureCbCr = capturedImageTextureCbCr
              else { return }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("CapturedImageRender")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexVertex.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture( CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue) )
        renderEncoder.setFragmentTexture( CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue) )
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives( type: .triangleStrip, vertexStart: 0, vertexCount: 4 )
        
        renderEncoder.popDebugGroup()
    }
}
