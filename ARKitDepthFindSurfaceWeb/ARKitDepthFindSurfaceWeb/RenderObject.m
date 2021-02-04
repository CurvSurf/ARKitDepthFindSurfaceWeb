//
//  RenderObject.m
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#import "RenderObject.h"

@implementation RenderObject

- (id<MTLBuffer>) vertexBuffer
{
    return _vertexBuffer;
}

- (id<MTLBuffer>) indexBuffer
{
    return _indexBuffer;
}

- (NSUInteger) elementCount
{
    return _elementCount;
}

- (simd_float4x4) model
{
    return _model;
}

- (simd_float4) params
{
    return _param;
}

- (simd_float4) colors
{
    return _color;
}

- (BOOL) convex
{
    return _isConvex;
}

@end
