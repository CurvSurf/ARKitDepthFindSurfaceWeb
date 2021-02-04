//
//  pointCloud.metal
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

#define MIN_DISTANCE 0.0f
#define MAX_DISTANCE 4.0f

#define DEFAULT_POINT_SIZE 15.0f
#define BLUE  float4(0.0f, 0.0f, 1.0f, 1.0f)
#define GREEN float4(0.0f, 1.0f, 0.0f, 1.0f)
#define RED   float4(1.0f, 0.0f, 0.0f, 1.0f)

using namespace metal;

// Define I/O Data Structure for each Stage
typedef struct {
    float3 position [[attribute(kVertexAttributePosition)]];
} VtxIn;

typedef struct {
    float4 position   [[position]];
    float4 color;
    float  point_size [[point_size]];
} VtxOut, FragIn;

// Vertex Function
vertex VtxOut pointCloudVertex( VtxIn vtx [[stage_in]],
                                constant float4x4& mvp [[buffer(kBufferIndexMVP)]],
                                constant float4x4& mv [[buffer(kBufferIndexMV)]],
                                constant float4& color [[buffer(kBufferIndexColorParam)]])
{
    float4 pos = float4(vtx.position, 1.0f);
    
    float lengthFromView = length( float3(mv * pos) );
    float scale = (clamp(lengthFromView, MIN_DISTANCE, MAX_DISTANCE ) - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE);
    
    VtxOut ret = {
        .position = mvp * pos,
        .point_size = max( 1.0, DEFAULT_POINT_SIZE * (1.0f - scale) )
    };
    
    if( color.a == 0.0f ) {
        float4 jetColor = scale < 0.5f
            ? mix( BLUE, GREEN, float4(scale * 2.0f) )
            : mix( GREEN, RED, float4( (scale - 0.5f) * 2.0f) );
        
        ret.color = jetColor;
    }
    else {
        ret.color = color;
    }
    
    return ret;
}

// Fragment Function
fragment float4 pointCloudFragment( FragIn in [[stage_in]] )
{
    return in.color;
}
