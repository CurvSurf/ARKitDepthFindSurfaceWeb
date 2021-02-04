//
//  RenderObjectFactory.h
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>
#import "RenderObject.h"


NS_ASSUME_NONNULL_BEGIN

@interface RenderObjectFactory : NSObject

- (id) initWithMTLDevice: (nonnull id<MTLDevice>)device;
- (void) dealloc;

- (RenderObject *)planeWithLL: (simd_float3)ll LR: (simd_float3)lr UR: (simd_float3)ur UL: (simd_float3)ul;
- (RenderObject *)planeWithLL: (simd_float3)ll LR: (simd_float3)lr UR: (simd_float3)ur UL: (simd_float3)ul ConvexFlag: (BOOL) isConvex;

- (RenderObject *)sphereWithCenter: (simd_float3)c Radius: (float) r;
- (RenderObject *)sphereWithCenter: (simd_float3)c Radius: (float) r ConvexFlag: (BOOL) isConvex;

- (RenderObject *)cylinderWithTop: (simd_float3)t Bottom: (simd_float3)b Radius: (float) r;
- (RenderObject *)cylinderWithTop: (simd_float3)t Bottom: (simd_float3)b Radius: (float) r ConvexFlag: (BOOL) isConvex;

- (RenderObject *)coneWithTop: (simd_float3)t Bottom: (simd_float3)b TopRadius: (float) tr BottomRadius: (float) br;
- (RenderObject *)coneWithTop: (simd_float3)t Bottom: (simd_float3)b TopRadius: (float) tr BottomRadius: (float) br ConvexFlag: (BOOL) isConvex;

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n MeanRadius: (float)mr TubeRadius: (float) tr;
- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n MeanRadius: (float)mr TubeRadius: (float) tr ConvexFlag: (BOOL) isConvex;

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n Right: (simd_float3)r MeanRadius: (float)mr TubeRadius: (float) tr Ratio: (float) ratio;
- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n Right: (simd_float3)r MeanRadius: (float)mr TubeRadius: (float) tr Ratio: (float) ratio ConvexFlag: (BOOL) isConvex;

+ (simd_float4) getTorusExtraParamWithCenter: (simd_float3)c Normal: (simd_float3)n Inliers: (const float *)inliers Count: (uint)cnt;
+ (simd_float4) getTorusExtraParamWithCenter: (simd_float3)c Normal: (simd_float3)n Inliers: (const float *)inliers Count: (uint)cnt Stride: (uint)stride;

@end

NS_ASSUME_NONNULL_END
