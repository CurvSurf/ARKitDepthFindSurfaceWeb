//
//  pointCloudRenderer.swift
//  ARKitDetphFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

//
// Ref> MetalCode: pointCloud.metal, IndexConstants: ShaderTypes.h
//
import Foundation
import MetalKit
import ARKit

let FLOAT4_ZERO = simd_make_float4(0, 0, 0, 0)

// Point Cloud Renderer
class pointCloudRenderer
{
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    
    init(metalDevice device: MTLDevice, _ defaultLibrary: MTLLibrary, _ renderDestination: RenderDestinationProvider)
    {
        let vertexFunction   = defaultLibrary.makeFunction(name: "pointCloudVertex")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "pointCloudFragment")!
        
        // Create a vertex descriptor for point vertex buffer
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexVertex.rawValue)
        
        vertexDescriptor.layouts[0].stride   = MemoryLayout<simd_float3>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a reusable pipeline state for rendering point
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "pointCloudRenderPipeline"
        pipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        pipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do { try pipelineState = device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error {
            print("Failed to created point cloud pipeline state, error \(error)")
            return
        }
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        
        depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)
    }
    
    func renderVertices(renderEncoder: MTLRenderCommandEncoder, vertexBuffer: MTLBuffer, vertexCount: Int, renderViewProjMat: simd_float4x4, baseViewMat: simd_float4x4) {
        guard vertexCount > 0 else { return }
        
        renderEncoder.pushDebugGroup("VertexBufferPointsRender")
        
        renderEncoder.setRenderPipelineState( pipelineState )
        renderEncoder.setDepthStencilState( depthState )
        
        var mv    = baseViewMat
        var mvp   = renderViewProjMat
        var color = FLOAT4_ZERO
        
        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(kBufferIndexVertex.rawValue))
        
        // Set uniforms
        renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: Int(kBufferIndexMVP.rawValue))
        renderEncoder.setVertexBytes(&mv, length: MemoryLayout<simd_float4x4>.size, index: Int(kBufferIndexMV.rawValue))
        renderEncoder.setVertexBytes(&color, length: MemoryLayout<simd_float4>.size, index: Int(kBufferIndexColorParam.rawValue))
        
        // Draw points
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
        
        renderEncoder.popDebugGroup()
    }
    
    func renderVertices(renderEncoder: MTLRenderCommandEncoder, vertexBuffer: MTLBuffer, vertexCount: Int, renderViewProjMat: simd_float4x4, baseViewMat: simd_float4x4, pointColorRGB: simd_float3) {
        guard vertexCount > 0 else { return }
        
        renderEncoder.pushDebugGroup("VertexBufferPointsRender")
        
        renderEncoder.setRenderPipelineState( pipelineState )
        renderEncoder.setDepthStencilState( depthState )
        
        var mv    = baseViewMat
        var mvp   = renderViewProjMat
        var color = simd_make_float4(pointColorRGB, 1.0)
        
        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(kBufferIndexVertex.rawValue))
        
        // Set uniforms
        renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: Int(kBufferIndexMVP.rawValue))
        renderEncoder.setVertexBytes(&mv, length: MemoryLayout<simd_float4x4>.size, index: Int(kBufferIndexMV.rawValue))
        renderEncoder.setVertexBytes(&color, length: MemoryLayout<simd_float4>.size, index: Int(kBufferIndexColorParam.rawValue))
        
        // Draw points
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
        
        renderEncoder.popDebugGroup()
    }
}
