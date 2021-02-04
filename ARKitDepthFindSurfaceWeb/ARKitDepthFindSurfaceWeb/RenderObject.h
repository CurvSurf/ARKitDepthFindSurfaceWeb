//
//  RenderObject.h
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface RenderObject : NSObject
{
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    
    NSUInteger    _elementCount;
    simd_float4x4 _model;
    simd_float4   _param;
    simd_float4   _color;
    BOOL          _isConvex;
}

@property(readonly) id<MTLBuffer> vertexBuffer;
@property(readonly) id<MTLBuffer> indexBuffer;
@property(readonly) NSUInteger    elementCount;
@property(readonly) simd_float4x4 model;
@property(readonly) simd_float4   params;
@property(readonly) simd_float4   colors;
@property(readonly) BOOL          convex;

@end

NS_ASSUME_NONNULL_END
