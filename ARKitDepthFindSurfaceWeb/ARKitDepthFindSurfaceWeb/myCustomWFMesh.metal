//
//  myCustomWFMesh.metal
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float4 position [[position]];
    float3 bcoord;
} WFMeshInOut;

inline float4 perVertexOp( float4 pos, float4 param  ) {
    if( param.w < 0.0 ) {
        // Cone
        float r = mix( param.y, param.x, pos.y + 0.5 );
        pos = float4( pos.x * r, pos.y, pos.z * r, pos.w );
    }
    else if( param.w > 0.0 ) {
        // Torus
        float x = pos.x * param.y + param.x;
        pos = float4( x * cos(pos.z * param.z), pos.y * param.y, x * sin(pos.z * param.z), pos.w );
    }
    return pos;
}

// Mesh Solid WireFrame Vertex Function
vertex WFMeshInOut wfMeshVertex( uint                        vid [[vertex_id]],
                                 device const packed_float3* vertices [[buffer(WFB_INDEX_VERTICES)]],
                                 device const ushort*        indices [[buffer(WFB_INDEX_INDICIES)]],
                                 constant float4x4&          mvp [[buffer(WFB_INDEX_MVP)]],
                                 constant float4&            param [[buffer(WFB_INDEX_MESH_PARAM)]],
                                 constant float4&            setting [[buffer(WFB_INDEX_SETTING)]] )
{
    const uint tid  = vid / 3; // triangle id
    const uint tvid = vid % 3; // vertex id of triangle. one of [0, 1, 2]
    const uint iidx = 3 * tid;
    const float2 scale = setting.xy; // viewport scale
    
    const float4 vtx[3] = {
        mvp * perVertexOp( float4( vertices[ indices[iidx] ], 1.0 ), param ),
        mvp * perVertexOp( float4( vertices[ indices[iidx + 1] ], 1.0 ), param ),
        mvp * perVertexOp( float4( vertices[ indices[iidx + 2] ], 1.0 ), param )
    };
    
    const float2 p0 = vtx[0].xy / vtx[0].w;
    const float2 p1 = vtx[1].xy / vtx[1].w;
    const float2 p2 = vtx[2].xy / vtx[2].w;
    
    const float2 v1 = scale * (p1 - p0);
    const float2 v2 = scale * (p2 - p0);
    
    const float area = abs( v1.x * v2.y - v1.y * v2.x ); // cross product
    
    WFMeshInOut ret;
    ret.position = vtx[tvid];
    
    if( tvid == 0 ) {
        ret.bcoord = float3( area / length( v1 - v2 ), 0, 0 );
    }
    else if( tvid == 1 ) {
        ret.bcoord = float3( 0, area / length(v2), 0 );
    }
    else {
        ret.bcoord = float3( 0, 0, area / length(v1) );
    }
    
    return ret;
}

// Mesh Solid WireFrame Fragment Function
fragment float4 wfMeshFragment( WFMeshInOut      in      [[stage_in]],
                                constant float4& color   [[buffer(WFB_INDEX_COLOR)]],
                                constant float4& setting [[buffer(WFB_INDEX_SETTING_LINE)]])
{
    float4 lineColor = float4( color.rgb, 1 );
    const float half_line_width = setting.z;
    
    float d = min( in.bcoord.x, min(in.bcoord.y, in.bcoord.z) ) - (half_line_width - 1.0);
    if( d < 2.0 ) { return lineColor; }
    else {
        discard_fragment();
    }
    return simd_float4(0); // never reach here
}

