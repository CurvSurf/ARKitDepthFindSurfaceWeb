//
//  FindSurfacaeWebExtension.swift
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

import Foundation

// Custom structure for Success Handler
struct ExtraInformation{
    let rayPosition: simd_float3
    let rayDirection: simd_float3
    let seedPoint: simd_float3
    
    init(rayPosition pos: simd_float3, rayDirection dir: simd_float3, seedPoint seed: simd_float3 ) {
        rayPosition = pos
        rayDirection = dir
        seedPoint = seed
    }
}

// typealias
typealias FindSurfaceSuccessHandler = (_ result: FindSurfaceResult, _ extra: ExtraInformation) -> Void
typealias FindSurfaceFailHandler = (_ error: Error?) -> Void
typealias FindSurfaceEndHandler = () -> Void

extension FindSurfaceResult {
    private func convexTestSphere( _ rayPos: simd_float3, _ rayDir: simd_float3, _ point: simd_float3 ) -> Bool {
        let base = sphereCenter - rayPos
        let base_length = simd_length( base )
        
        return sphereRadius < base_length && simd_dot( point - rayPos, base / base_length ) < base_length
    }
    
    private func convexTestCylinder( _ rayPos: simd_float3, _ rayDir: simd_float3, _ point: simd_float3 ) -> Bool {
        let axis = simd_normalize( cylinderTop - cylinderBottom )
        let center = (cylinderTop + cylinderBottom) / 2.0
        
        let o = rayPos + simd_dot( point - rayPos, axis ) * axis
        
        let base = center + simd_dot( point - center, axis ) * axis - o
        let base_length = simd_length(base)
        
        return cylinderRadius < base_length && simd_dot(point - o, base / base_length ) < base_length
    }
    
    public func convexTest( withRayPosition rayPos: simd_float3, andRayDirection rayDir: simd_float3, andHitPoint point: simd_float3 ) -> Bool {
        switch type {
        case .FS_TYPE_SPHERE:
            return convexTestSphere( rayPos, rayDir, point )
        case .FS_TYPE_CYLINDER:
            return convexTestCylinder( rayPos, rayDir, point )
        default:
            return true
        }
    }
}
