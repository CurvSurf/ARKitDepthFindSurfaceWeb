//
//  myCustomWFMeshRenderer.swift
//  ARKitDetphFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

//
// Ref> MetalCode: myCustomWFMesh.metal, IndexConstants: ShaderTypes.h
//
import Foundation
import MetalKit
import ARKit

// My Custom Wire-Frame Mesh Renderer
class myCustomWFMeshRenderer
{
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    
    var wfMeshSettingBuffer: MTLBuffer!
    
    init(metalDevice device: MTLDevice, _ defaultLibrary: MTLLibrary, _ renderDestination: RenderDestinationProvider, _ viewportSize: CGSize)
    {
        // Create a parameter uniform buffer
        var param = simd_make_float4( Float(viewportSize.width), Float(viewportSize.height), 5, 0.0 )
        wfMeshSettingBuffer = device.makeBuffer(bytes: &param, length: MemoryLayout<simd_float4>.size, options: [])
        
        let vertexFunction   = defaultLibrary.makeFunction(name: "wfMeshVertex")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "wfMeshFragment")!
        
        // Create a reusable pipeline state for rendering mesh
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "myCustomWFMeshRenderPipeline"
        pipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        // NOTE!: No Vertex Description for this Shader Program!!
        
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        pipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do { try pipelineState = device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error {
            print("Failed to created My Custom WireFrame Mesh Renderer pipeline state, error \(error)")
            return
        }
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        
        depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)
    }
    
    func updateViewport(viewportSize: CGSize) {
        let buffer = wfMeshSettingBuffer.contents().assumingMemoryBound(to: simd_float4.self)
        buffer[0].x = Float(viewportSize.width)
        buffer[0].y = Float(viewportSize.height)
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder, targetMeshList:[RenderObject], vp: simd_float4x4)
    {
        guard !targetMeshList.isEmpty else { return }
        
        renderEncoder.pushDebugGroup("myCustomWFMeshDraw")
        
        renderEncoder.setRenderPipelineState( pipelineState )
        renderEncoder.setDepthStencilState( depthState )
        
        renderEncoder.setTriangleFillMode(.fill)
        renderEncoder.setCullMode(.front)
        
        // Set Common Uniform Buffer
        renderEncoder.setVertexBuffer(wfMeshSettingBuffer, offset: 0, index: Int(WFB_INDEX_SETTING.rawValue))
        renderEncoder.setFragmentBuffer(wfMeshSettingBuffer, offset: 0, index: Int(WFB_INDEX_SETTING_LINE.rawValue))
        
        for mesh in targetMeshList
        {
            var mvp    = simd_mul( vp, mesh.model )
            var params = mesh.params
            var color  = mesh.colors
            
            renderEncoder.setCullMode( mesh.convex ? .front : .back )
            renderEncoder.setVertexBuffer( mesh.vertexBuffer, offset: 0, index: Int(WFB_INDEX_VERTICES.rawValue) )
            renderEncoder.setVertexBuffer( mesh.indexBuffer, offset: 0, index: Int(WFB_INDEX_INDICIES.rawValue) )
            renderEncoder.setVertexBytes( &mvp, length: MemoryLayout<simd_float4x4>.size, index: Int(WFB_INDEX_MVP.rawValue) )
            renderEncoder.setVertexBytes( &params, length: MemoryLayout<simd_float4>.size, index: Int(WFB_INDEX_MESH_PARAM.rawValue) )
            renderEncoder.setFragmentBytes( &color, length: MemoryLayout<simd_float4>.size, index: Int(WFB_INDEX_COLOR.rawValue) )
            
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Int(mesh.elementCount));
        }
        
        renderEncoder.popDebugGroup()
    }
}
