//
//  Renderer.swift
//  ARKitDetphFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ARKit

// Define Constants
let MAX_INLIERS_BUFFER_SIZE = 1024 * 1024 * 16 // 16 MB
let RED = simd_make_float3(1, 0, 0)

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

class Renderer {
    let session: ARSession
    let device: MTLDevice
    var renderDestination: RenderDestinationProvider
    
    // Metal objects
    var commandQueue: MTLCommandQueue!
    
    // Sub-Renderer
    var cimgR :capturedImageRenderer!
    var pcR   :pointCloudRenderer!
    var mR    :myCustomWFMeshRenderer!
    
    // The current viewport size
    var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    var viewportSizeDidChange: Bool = false
    
    // Render Object
    var objFactory: RenderObjectFactory? = nil
    var lastInliersBuffer: MTLBuffer? = nil
    var lastInliersCount: Int = 0
    var targetMeshList: [RenderObject] = []
    
    // Point Cloud Buffer
    var pointBuffer: MTLBuffer?
    var pointCount: Int = 0
    
    var pointShowFlag: Bool = true
    
    // Property
    var showPointcloud: Bool {
        get { return pointShowFlag }
        set(flag) { pointShowFlag = flag }
    }

    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        loadMetal()
    }
    
    // MARK: - Initialize Metal Resources
    
    func loadMetal() {
        // Create and load our basic Metal state objects
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        // Create Sub-Render Modules
        cimgR = capturedImageRenderer(metalDevice: device, defaultLibrary, renderDestination)
        pcR   = pointCloudRenderer(metalDevice: device, defaultLibrary, renderDestination)
        mR    = myCustomWFMeshRenderer(metalDevice: device, defaultLibrary, renderDestination, viewportSize)
        
        // Create a Point Buffer (for Rendering Live or Captured(recorded) Points)
        pointBuffer = device.makeBuffer(length: MAX_INLIERS_BUFFER_SIZE, options: [])
        if pointBuffer != nil { pointBuffer!.label = "PointBuffer" }
        pointCount = 0
        
        // Create Inliers Buffer
        lastInliersBuffer = device.makeBuffer(length: MAX_INLIERS_BUFFER_SIZE, options: []);
        if let myBuffer = lastInliersBuffer { myBuffer.label = "LastInliersVertexBuffer" }
        lastInliersCount = 0
        
        // Create Render Object Factory
        objFactory = RenderObjectFactory( mtlDevice: device );
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    
    // MARK: - Viewport Resized
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    
    // MARK: - Screen Position to Normalized Device Coordinates and Ray
    
    func screenPosition2NDC(screen_position pos : CGPoint) -> simd_float2 {
        return screenPosition2NDC(screen_position_x: pos.x, screen_position_y: pos.y)
    }
    
    func screenPosition2NDC(screen_position_x : CGFloat, screen_position_y : CGFloat) -> simd_float2 {
        return simd_make_float2(
            Float( 2.0 * (screen_position_x / viewportSize.width) - 1.0),
            Float( -(2.0 * (screen_position_y / viewportSize.height) - 1.0))
        )
    }
    
    func screenLength2WorldLength( length: CGFloat, projectionMatrix projMat: simd_float4x4) -> Float {
        if viewportSize.width < viewportSize.height {
            return Float(length / viewportSize.width) / projMat.columns.0.x
        }
        else {
            return Float(length / viewportSize.height) / projMat.columns.1.y
        }
    }
    
    func NDC2RayDirection( NDCPoint pt: simd_float2, inverseViewMatrix invViewMat: simd_float4x4, projectionMatrix projMat: simd_float4x4) -> simd_float3 {
        return simd_make_float3(
            simd_mul( invViewMat,
                      simd_make_float4( pt.x / projMat.columns.0.x, pt.y / projMat.columns.1.y, projMat.columns.2.z > 0.0 ? 1.0 : -1.0, 0.0 ) )
        )
    }
    
    func screenPosition2RayDirection( screen_position pos: CGPoint, inverseViewMatrix invViewMat: simd_float4x4, projectionMatrix projMat: simd_float4x4) -> simd_float3 {
        return NDC2RayDirection(NDCPoint: screenPosition2NDC(screen_position: pos), inverseViewMatrix: invViewMat, projectionMatrix: projMat)
    }
    
    func screenPosition2RayDirection( screen_position_x pos_x: CGFloat, screen_position_y pos_y: CGFloat, inverseViewMatrix invViewMat: simd_float4x4, projectionMatrix projMat: simd_float4x4) -> simd_float3 {
        return NDC2RayDirection(NDCPoint: screenPosition2NDC(screen_position_x: pos_x, screen_position_y: pos_y), inverseViewMatrix: invViewMat, projectionMatrix: projMat)
    }
    
    // MARK: - Simply Wrapping Function(s) of ARFrame
    
    func getViewMatrixFromARFrame( _ frame: ARFrame ) -> simd_float4x4 {
        return frame.camera.viewMatrix(for: .landscapeRight )
    }
    
    func getProjectionMatrixFromARFrame( _ frame: ARFrame ) -> simd_float4x4 {
        return frame.camera.projectionMatrix(for: .landscapeRight, viewportSize: viewportSize, zNear: 0.001, zFar: 100)
    }
    
    // MARK: - Actual Update & Render Function
    
    func render(){
        guard let frame = session.currentFrame else { return }
        
        // Update Camera Matrix
        let viewMatrix = getViewMatrixFromARFrame(frame)
        let projMatrix = getProjectionMatrixFromARFrame(frame)
        let vpMat      = simd_mul( projMatrix, viewMatrix )
        
        // Update Captured Image Textures
        cimgR.updateCapturedImageTextures(frame: frame)
        
        // Viewport Update Check
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            cimgR.updateImagePlane(frame: frame, viewportSize: viewportSize)
            mR.updateViewport(viewportSize: viewportSize)
        }
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MyCommand"
            
            // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
            //   we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
            //   are retained. Since we may release our CVMetalTexture ivars during the rendering
            //   cycle, we must retain them separately here.
            var textures = [cimgR.capturedImageTextureY, cimgR.capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler{ commandBuffer in
                textures.removeAll()
            }
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor,
               let currentDrawable = renderDestination.currentDrawable,
               let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            {
                
                renderEncoder.label = "MyRenderEncoder"
                
                // Draw Captured Image
                cimgR.render(renderEncoder: renderEncoder)
                
                if pointShowFlag {
                    // Draw Inliers, if exist
                    if lastInliersBuffer != nil && lastInliersCount > 0 {
                        pcR.renderVertices(renderEncoder: renderEncoder, vertexBuffer: lastInliersBuffer!, vertexCount: lastInliersCount, renderViewProjMat: vpMat, baseViewMat: viewMatrix, pointColorRGB: RED)
                    }
                    
                    // Draw (Live or Captured) Point Cloud
                    if pointBuffer != nil && pointCount > 0 {
                        pcR.renderVertices(renderEncoder: renderEncoder, vertexBuffer: pointBuffer!, vertexCount: pointCount, renderViewProjMat: vpMat, baseViewMat: viewMatrix)
                    }
                }
                
                // Draw myCustomMesh List (primitives which found)
                mR.render(renderEncoder: renderEncoder, targetMeshList: targetMeshList, vp: vpMat)
                
                // We're done encoding commands
                renderEncoder.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer.present(currentDrawable)
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
    }
    
    // MARK: - Update Live PointCloud Buffer
    
    func updatePointCloud(pointsRaw: UnsafeRawPointer, pointCount: Int, pointStride: Int) {
        guard let buffer = pointBuffer else { return }
        if pointCount > 0 {
            buffer.contents().copyMemory(from: pointsRaw, byteCount: pointCount * pointStride)
        }
        self.pointCount = pointCount
    }
    
    func clearPointCloud() {
        self.pointCount = 0;
    }
    
    // MARK: - Append Mesh with FindSurfaceResult
    
    private func _generateMesh(withFindSurfaceResult result:FindSurfaceResult, torusExtraParam param:simd_float4? = nil, convexFlag isConvex: Bool = true) -> RenderObject? {
        guard let factory = objFactory else { return nil }
        
        var rObj: RenderObject? = nil;
        switch result.type
        {
            case .FS_TYPE_PLANE:
                rObj = factory.plane(withLL: result.planeLL, lr: result.planeLR, ur: result.planeUR, ul: result.planeUL, convexFlag: isConvex)
            case .FS_TYPE_SPHERE:
                rObj = factory.sphere(withCenter: result.sphereCenter, radius: result.sphereRadius, convexFlag: isConvex)
            case .FS_TYPE_CYLINDER:
                rObj = factory.cylinder(withTop: result.cylinderTop, bottom: result.cylinderBottom, radius: result.cylinderRadius, convexFlag: isConvex)
            case .FS_TYPE_CONE:
                rObj = factory.cone(withTop: result.coneTop, bottom: result.coneBottom, topRadius: result.coneTopRadius, bottomRadius: result.coneBottomRadius, convexFlag: isConvex)
            case .FS_TYPE_TORUS:
                if let ext_param = param
                {
                    let _rvec3: simd_float3 = simd_make_float3(ext_param.x, ext_param.y, ext_param.z);
                    let _ratio = ext_param.w;
                    
                    rObj = factory.torus(withCenter: result.torusCenter, normal: result.torusNormal, right: _rvec3,
                                         meanRadius: result.torusMeanRadius, tubeRadius: result.torusTubeRadius, ratio: _ratio, convexFlag: isConvex)
                }
                else
                {
                    rObj = factory.torus(withCenter: result.torusCenter, normal: result.torusNormal, meanRadius: result.torusMeanRadius, tubeRadius: result.torusTubeRadius, convexFlag: isConvex)
                }
        }
        
        return rObj
    }
    
    func appendMesh(withFindSurfaceResult result:FindSurfaceResult, extParam param:simd_float4? = nil, convexFlag isConvex: Bool = true) {
        if let mesh = _generateMesh(withFindSurfaceResult: result, torusExtraParam: param, convexFlag: isConvex) {
            targetMeshList.append(mesh)
            lastInliersCount = 0 // No Inliers
        }
    }
    
    func appendMesh(withFindSurfaceResult result:FindSurfaceResult, andInliers inliers:UnsafePointer<simd_float3>, inliersCount count: Int, extParam param:simd_float4?, convexFlag isConvex: Bool = true) {
        if let mesh = _generateMesh(withFindSurfaceResult: result, torusExtraParam: param, convexFlag: isConvex) {
            targetMeshList.append(mesh)
            
            // Copy Inliers if exist
            if let buffer = lastInliersBuffer, count > 0 {
                let bytesLength = count * MemoryLayout<simd_float3>.size
                buffer.contents().copyMemory(from: inliers, byteCount: bytesLength)
                lastInliersCount = count
            }
            else {
                lastInliersCount = 0 // No Inliers
            }
        }
    }
    
    func isMeshEmpty() -> Bool {
        return targetMeshList.isEmpty;
    }
    
    func removeLatestMesh() {
        targetMeshList.removeLast()
        lastInliersCount = 0
    }
    
    func clearMeshList() {
        targetMeshList.removeAll()
        lastInliersCount = 0
    }
}
