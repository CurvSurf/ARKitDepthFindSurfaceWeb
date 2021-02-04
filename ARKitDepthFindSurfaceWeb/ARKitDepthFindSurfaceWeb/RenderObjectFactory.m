//
//  RenderObjectFactory.m
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

#import "RenderObjectFactory.h"

#include <stdlib.h>
#include <math.h>

#define BUFFER_DEFAULT_OPTION MTLResourceStorageModeShared
#define UNIFORM_DEFAULT_OPTION MTLResourceStorageModeShared
#define EPSILLON 0.0001f

typedef struct {
    id<MTLBuffer> vb;
    id<MTLBuffer> ib;
    NSUInteger    cnt;
} BUFFER_PROPERTIES;

typedef struct
{
    matrix_float4x4 mvp;
    vector_float4   param;
    vector_float4   color;
} Uniforms;

static int _genUnitPlane(BUFFER_PROPERTIES *pOut, id<MTLDevice> device);
static int _genUnitSphere(BUFFER_PROPERTIES *pOut, id<MTLDevice> device);
static int _genUnitConeStatic(const int nSubHeight, const int nSubDiv, BUFFER_PROPERTIES *pOut, id<MTLDevice> device);
static int _genUnitTorusElement(BUFFER_PROPERTIES *pOut, id<MTLDevice> device);

@implementation RenderObject (Local)
- (id) initWithVertexBuffer: (id<MTLBuffer>) vb IndexBuffer: (id<MTLBuffer>) ib Count: (NSUInteger) count Uniform: (const Uniforms *) uniform ConvexFlag: (BOOL) isConvex
{
    self = [super init];
    if(self)
    {
        _vertexBuffer = vb;
        _indexBuffer  = ib;
        _elementCount = count;
        _model        = uniform->mvp;
        _param        = uniform->param;
        _color        = uniform->color;
        _isConvex     = isConvex;
    }
    return self;
}
@end

@implementation RenderObjectFactory
{
    id<MTLDevice> _device;
    BUFFER_PROPERTIES unit_plane;
    BUFFER_PROPERTIES unit_sphere;
    BUFFER_PROPERTIES unit_cylinder;
    BUFFER_PROPERTIES unit_cone_element;
    BUFFER_PROPERTIES unit_torus_element;
}

- (id) initWithMTLDevice: (nonnull id<MTLDevice>)device
{
    self = [super init];
    if(self) {
        _device = device;
        
        int ret = _genUnitPlane(&unit_plane, device);
        ret |= _genUnitSphere(&unit_sphere, device);
        ret |= _genUnitConeStatic(3, 24, &unit_cylinder, device);
        ret |= _genUnitConeStatic(2, 24, &unit_cone_element, device);
        ret |= _genUnitTorusElement(&unit_torus_element, device);
        
        if(ret) return nil;
    }
    return self;
}

- (void) dealloc
{
    
}

- (RenderObject *)planeWithLL: (simd_float3)ll LR: (simd_float3)lr UR: (simd_float3)ur UL: (simd_float3)ul
{
    return [self planeWithLL:ll LR:lr UR:ur UL:ul ConvexFlag:true];
}

- (RenderObject *)planeWithLL: (simd_float3)ll LR: (simd_float3)lr UR: (simd_float3)ur UL: (simd_float3)ul ConvexFlag:(BOOL)isConvex
{
    simd_float3 right = ur - ul;
    simd_float3 front = ll - ul;
    simd_float3 normal = simd_normalize( simd_cross( simd_normalize( front ), simd_normalize( right ) ) );
    
    simd_float4x4 model = simd_matrix( simd_make_float4(right, 0.0f),
                                   simd_make_float4(normal, 0.0f),
                                   simd_make_float4(front, 0.0f),
                                   simd_make_float4( (ll + lr + ur + ul) / 4.0f, 1.0f)
                                  );
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(0.0f);
    uniform.color = simd_make_float4(1.0f, 0.0f, 0.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_plane.vb IndexBuffer: unit_plane.ib Count: unit_plane.cnt Uniform: &uniform ConvexFlag:isConvex];
}

- (RenderObject *)sphereWithCenter: (simd_float3)c Radius: (float) r
{
    return [self sphereWithCenter:c Radius:r ConvexFlag:true];
}

- (RenderObject *)sphereWithCenter: (simd_float3)c Radius: (float) r ConvexFlag:(BOOL)isConvex
{
    simd_float4x4 model = {{
        { r, 0.0f, 0.0f, 0.0f },
        { 0.0f, r, 0.0f, 0.0f },
        { 0.0f, 0.0f, r, 0.0f },
        { c.x, c.y, c.z, 1.0f },
    }};
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(0.0f);
    uniform.color = simd_make_float4(1.0f, 1.0f, 0.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_sphere.vb IndexBuffer: unit_sphere.ib Count: unit_sphere.cnt Uniform: &uniform ConvexFlag:isConvex];
}

- (RenderObject *)cylinderWithTop: (simd_float3)t Bottom: (simd_float3)b Radius: (float) r
{
    return [self cylinderWithTop:t Bottom:b Radius:r ConvexFlag:true];
}

- (RenderObject *)cylinderWithTop: (simd_float3)t Bottom: (simd_float3)b Radius: (float) r ConvexFlag:(BOOL)isConvex
{
    simd_float3 front = simd_make_float3( 0.0f, 0.0f, 1.0f );
    simd_float3 axis  = t - b;
    simd_float3 right;
    
    simd_float3 naxis = simd_normalize( axis );
    if( simd_length(front - axis) < EPSILLON ) {
        front = simd_make_float3( 1.0f, 0.0f, 0.0f );
    }
    
    right = simd_normalize( simd_cross( naxis, front ) );
    front = simd_normalize( simd_cross( right, naxis ) );
    
    right = r * right;
    front = r * front;
    
    simd_float4x4 model = simd_matrix( simd_make_float4( right, 0.0f ),
                                       simd_make_float4( axis, 0.0f ),
                                       simd_make_float4( front, 0.0f ),
                                       simd_make_float4( (t + b) / 2.0f, 1.0f ) );
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(0.0f);
    uniform.color = simd_make_float4(0.0f, 1.0f, 0.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_cylinder.vb IndexBuffer: unit_cylinder.ib Count: unit_cylinder.cnt Uniform: &uniform ConvexFlag:isConvex];
}

- (RenderObject *)coneWithTop: (simd_float3)t Bottom: (simd_float3)b TopRadius: (float) tr BottomRadius: (float) br
{
    return [self coneWithTop:t Bottom:b TopRadius:tr BottomRadius:br ConvexFlag:true];
}

- (RenderObject *)coneWithTop: (simd_float3)t Bottom: (simd_float3)b TopRadius: (float) tr BottomRadius: (float) br ConvexFlag:(BOOL)isConvex
{
    simd_float3 front = simd_make_float3( 0.0f, 0.0f, 1.0f );
    simd_float3 axis  = t - b;
    simd_float3 right;
    
    simd_float3 naxis = simd_normalize( axis );
    if( simd_length(front - axis) < EPSILLON ) {
        axis  = simd_length(axis) * simd_make_float3( 0.0f, 0.0f, 1.0f );
        right = simd_make_float3( 0.0f, 1.0f, 0.0f );
        front = simd_make_float3( 1.0f, 0.0f, 0.0f );
    }
    else {
        right = simd_normalize( simd_cross( naxis, front ) );
        front = simd_normalize( simd_cross( right, naxis ) );
    }
    
    simd_float4x4 model = simd_matrix( simd_make_float4( right, 0.0f ),
                                       simd_make_float4( axis, 0.0f ),
                                       simd_make_float4( front, 0.0f ),
                                       simd_make_float4( (t + b) / 2.0f, 1.0f ) );
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(tr, br, 0.0f, -1.0f);
    uniform.color = simd_make_float4(0.0f, 1.0f, 1.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_cone_element.vb IndexBuffer: unit_cone_element.ib Count: unit_cone_element.cnt Uniform: &uniform ConvexFlag:isConvex];
}

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n MeanRadius: (float)mr TubeRadius: (float) tr
{
    return [self torusWithCenter:c Normal:n MeanRadius:mr TubeRadius:tr ConvexFlag:true];
}

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n MeanRadius: (float)mr TubeRadius: (float) tr ConvexFlag:(BOOL)isConvex
{
    simd_float3 axis = simd_precise_normalize( n );
    simd_float3 front = simd_make_float3( 0.0f, 0.0f, 1.0f );
    simd_float3 right;
    
    if( simd_length(front - axis) < EPSILLON ) {
        axis  = simd_make_float3( 0.0f, 0.0f, 1.0f );
        right = simd_make_float3( 0.0f, 1.0f, 0.0f );
        front = simd_make_float3( 1.0f, 0.0f, 0.0f );
    }
    else {
        right = simd_normalize( simd_cross( axis, front ) );
        front = simd_normalize( simd_cross( right, axis ) );
    }
    
    simd_float4x4 model = simd_matrix( simd_make_float4( right, 0.0f ),
                                       simd_make_float4( axis, 0.0f ),
                                       simd_make_float4( front, 0.0f ),
                                       simd_make_float4( c, 1.0f ) );
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(mr, tr, 1.0f, 1.0f);
    uniform.color = simd_make_float4(1.0f, 0.0f, 1.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_torus_element.vb IndexBuffer: unit_torus_element.ib Count: unit_torus_element.cnt Uniform: &uniform ConvexFlag:isConvex];
}

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n Right: (simd_float3)r MeanRadius: (float)mr TubeRadius: (float) tr Ratio: (float) ratio
{
    return [self torusWithCenter:c Normal:n Right:r MeanRadius:mr TubeRadius:tr Ratio:ratio ConvexFlag:true];
}

- (RenderObject *)torusWithCenter: (simd_float3)c Normal: (simd_float3)n Right: (simd_float3)r MeanRadius: (float)mr TubeRadius: (float) tr Ratio: (float) ratio ConvexFlag:(BOOL)isConvex
{
    simd_float3 axis  = simd_normalize( n );
    simd_float3 right = simd_normalize( r );
    simd_float3 front = simd_normalize( simd_cross( right, axis ) );
    
    simd_float4x4 model = simd_matrix( simd_make_float4( right, 0.0f ),
                                      simd_make_float4( axis, 0.0f ),
                                      simd_make_float4( front, 0.0f ),
                                      simd_make_float4( c, 1.0f ) );
    
    if( ratio < 0.0f ) ratio = 0.0f;
    else if( ratio > 1.0f ) ratio  = 1.0f;
    
    Uniforms uniform;
    uniform.mvp = model;
    uniform.param = simd_make_float4(mr, tr, ratio, 1.0f);
    uniform.color = simd_make_float4(1.0f, 0.0f, 1.0f, 1.0f);
    
    return [[RenderObject alloc] initWithVertexBuffer: unit_torus_element.vb IndexBuffer: unit_torus_element.ib Count: unit_torus_element.cnt Uniform: &uniform ConvexFlag:isConvex];
}

+ (simd_float4) getTorusExtraParamWithCenter: (simd_float3)c Normal: (simd_float3)n Inliers: (const float *)inliers Count: (uint)cnt {
    return [self getTorusExtraParamWithCenter: c Normal: n Inliers: inliers Count: cnt Stride: 12];
}

+ (simd_float4) getTorusExtraParamWithCenter: (simd_float3)center Normal: (simd_float3)normal Inliers: (const float *)inliers Count: (uint)cnt Stride: (uint)stride
{
    simd_float3 dir, tmp;
    float len;
    float l_min_dot = FLT_MAX, r_min_dot = FLT_MAX;
    int l_min_idx = -1, r_min_idx = -1;
    simd_float3 lvec = simd_make_float3(0);
    simd_float3 rvec = simd_make_float3(0);
    
    const float *pCurr = NULL;
    const UInt8 *pRaw = NULL;
    
    // Get Center of Mass
    {
        simd_double3 com = simd_make_double3(0.0);
        
        pRaw = (const UInt8 *)inliers;
        for(uint i = 0; i < cnt; i++) {
            pCurr = (const float *)pRaw;
            
            com += simd_make_double3( pCurr[0], pCurr[1], pCurr[2] );
            pRaw += stride;
        }
        tmp = simd_float(com / (double)cnt);
    }
    
    tmp = simd_normalize( tmp - center );
    if( fabs(simd_dot( normal, tmp )) > 0.999f ) {
        return simd_make_float4(0);
    }
    
    dir = simd_normalize( simd_cross( normal, simd_normalize( simd_cross( tmp, normal ) ) ) );
    
    // Find Left most & Right most Point index
    {
        pRaw = (const UInt8 *)inliers;
        for(uint i = 0; i < cnt; i++) {
            pCurr = (const float *)pRaw;
            
            tmp = simd_normalize( simd_cross( normal, simd_cross( simd_make_float3( pCurr[0], pCurr[1], pCurr[2] ) - center, normal ) ) );
            
            len = simd_dot(dir, tmp);
            if( simd_dot( normal, simd_cross(dir, tmp) ) > 0.0f ) {
                if(len < l_min_dot) {
                    l_min_dot = len;
                    l_min_idx = (int)i;
                    lvec = tmp;
                }
            }
            else {
                if( len < r_min_dot) {
                    r_min_dot = len;
                    r_min_idx = (int)i;
                    rvec = tmp;
                }
            }
            
            pRaw += stride;
        }
    }
    
    len = acosf( simd_dot(dir, rvec) ) + acosf( simd_dot(dir, lvec) );
    
    return simd_make_float4( lvec, len / (2.0f * 3.14159265359f) );
}

@end

static int _genUnitPlane(BUFFER_PROPERTIES *pOut, id<MTLDevice> device)
{
    const int nSubDiv = 6;
    const int nSubDivHalf = ( nSubDiv + (nSubDiv % 2) ) / 2;
    const int vtxCnt = (nSubDiv + 1) * (nSubDiv + 1);
    const int vtxBytes = sizeof(float) * 3 * vtxCnt;
    const int pitch = 3 * (nSubDiv + 1);
    const float DIV_FACTOR = 1.0f / (float)nSubDiv;
    
    const int faceCnt = nSubDiv * nSubDiv * 2;
    const int idxCnt = faceCnt * 3 * 2;
    const int idxBytes = idxCnt * sizeof(UInt16);
    
    float *vtxList = NULL;
    UInt16 *idxList = NULL;
    
    vtxList = (float *)malloc(vtxBytes);
    idxList = (UInt16 *)malloc(idxBytes);
    
    if(vtxList == NULL || idxList == NULL) {
        free(vtxList); free(idxList);
        return -1;
    }
    
#if 1
    int r, c;
    for( r = 0; r < nSubDivHalf; ++r) {
        float *pDst1 = vtxList + ( r * pitch );
        float *pDst2 = vtxList + ( (nSubDiv - r) * pitch );
        
        float _z = 0.5f - ((float)r * DIV_FACTOR);
        
        for( c = 0; c < nSubDivHalf; ++c) {
            float _x = 0.5f - ((float)c * DIV_FACTOR); // x position
            
            float *pCurr1L = pDst1 + ( 3 * c );
            float *pCurr1R = pDst1 + ( 3 * (nSubDiv-c) );
            
            float *pCurr2L = pDst2 + ( 3 * c );
            float *pCurr2R = pDst2 + ( 3 * (nSubDiv-c) );
            
            pCurr1L[0] = -_x;
            pCurr1L[1] = 0.0f;
            pCurr1L[2] = -_z;
            
            pCurr1R[0] = _x;
            pCurr1R[1] = 0.0f;
            pCurr1R[2] = -_z;
            
            pCurr2L[0] = -_x;
            pCurr2L[1] = 0.0f;
            pCurr2L[2] = _z;
            
            pCurr2R[0] = _x;
            pCurr2R[1] = 0.0f;
            pCurr2R[2] = _z;
        }
    }
    
    if( nSubDiv % 2 == 0 ) {
        float *rowCurrPre  = vtxList + ( 3 * nSubDivHalf );
        float *rowCurrPost = rowCurrPre + ( nSubDiv * pitch );
        
        float *colCurrPre  = vtxList + ( nSubDivHalf * pitch );
        float *colCurrPost = colCurrPre + pitch - 3;
        
        for( int i = 0; i < nSubDivHalf; ++i)
        {
            float _t = 0.5f - ((float)i * DIV_FACTOR);
            
            rowCurrPre[2]  = colCurrPre[0]  = -_t;
            rowCurrPost[2] = colCurrPost[0] = _t;
            
            rowCurrPre[0] = rowCurrPre[1] = rowCurrPost[0] = rowCurrPost[1] =
            colCurrPre[1] = colCurrPre[2] = colCurrPost[1] = colCurrPost[2] = 0.0f;
            
            rowCurrPre += pitch; rowCurrPost -= pitch;
            colCurrPre += 3; colCurrPost -= 3;
        }
        
        
        rowCurrPre[0] = 0.0f;
        rowCurrPre[1] = 0.0f;
        rowCurrPre[2] = 0.0f;
    }
#else
    float *pCurr = vtxList;
    int r, c;
    for(r = 0; r < (nSubDiv + 1); r++) {
        for(c = 0; c < (nSubDiv + 1); ++c) {
            pCurr[0] = -0.5f + ((float)c * DIV_FACTOR);
            pCurr[1] = 0.0f;
            pCurr[2] = -0.5f + ((float)r * DIV_FACTOR);
            pCurr += 3;
        }
    }
#endif
    
    // Build Index
    int idx = 0;
    int bidx = 0;
    UInt16 *back_idxList = idxList + (faceCnt * 3);
    for(r = 0; r < nSubDiv; ++r) {
        for(c = 0; c < nSubDiv; ++c) {
            int base_index = (r * (nSubDiv + 1)) + c;
            
            idxList[idx++] = base_index;
            idxList[idx++] = base_index + (nSubDiv + 1);
            idxList[idx++] = base_index + (nSubDiv + 2);
            idxList[idx++] = base_index;
            idxList[idx++] = base_index + (nSubDiv + 2);
            idxList[idx++] = base_index + 1;
            
            back_idxList[bidx++] = base_index + 1;
            back_idxList[bidx++] = base_index + (nSubDiv + 2);
            back_idxList[bidx++] = base_index + (nSubDiv + 1);
            back_idxList[bidx++] = base_index + 1;
            back_idxList[bidx++] = base_index + (nSubDiv + 1);
            back_idxList[bidx++] = base_index;
        }
    }
    
    // Create Buffer
    id<MTLBuffer> vb = [device newBufferWithBytes: vtxList length: vtxBytes options: BUFFER_DEFAULT_OPTION];
    id<MTLBuffer> ib = [device newBufferWithBytes: idxList length: idxBytes options: BUFFER_DEFAULT_OPTION];
    
    free(vtxList);
    free(idxList);
    
    if(!vb || !ib) { return -1; }
    
    pOut->vb  = vb;
    pOut->ib  = ib;
    pOut->cnt = idxCnt;
    
    
    /*
    float vtxList[3 * 9] = {
        -0.5f, 0.0f, -0.5f,
        -0.5f, 0.0f,  0.0f,
        -0.5f, 0.0f,  0.5f,
        
         0.0f, 0.0f, -0.5f,
         0.0f, 0.0f,  0.0f,
         0.0f, 0.0f,  0.5f,
        
         0.5f, 0.0f, -0.5f,
         0.5f, 0.0f,  0.0f,
         0.5f, 0.0f,  0.5f,
    };
    
    UInt16 idxList[3 * 16] = {
        // front
        0, 1, 4,
        0, 4, 3,
        
        1, 2, 5,
        1, 5, 4,
        
        3, 4, 7,
        3, 7, 6,
        
        4, 5, 8,
        4, 8, 7,
        
        // back
        6, 7, 4,
        6, 4, 3,
        
        7, 8, 5,
        7, 5, 4,
        
        3, 4, 1,
        3, 1, 0,
        
        4, 5, 2,
        4, 2, 1
    };
    
    id<MTLBuffer> vb = [device newBufferWithBytes: vtxList length: (sizeof(float) * 3 * 9) options: BUFFER_DEFAULT_OPTION];
    id<MTLBuffer> ib = [device newBufferWithBytes: idxList length: (sizeof(UInt16) * 3 * 16) options: BUFFER_DEFAULT_OPTION];
    
    if(!vb || !ib) { return -1; }
    
    pOut->vb  = vb;
    pOut->ib  = ib;
    pOut->cnt = 48;
    */
    
    return 0;
}

static int _genUnitSphere(BUFFER_PROPERTIES *pOut, id<MTLDevice> device)
{
    const int nSubAxis   = 24;
    const int nSubHeight = 24;
    
    int i, k, half;
    float r, h;
    float angle, rad;
    float base_angle, base_div;
    float  *vtxList, *pCurrVtx, *pEndVtx, *pCurrVtx2;
    UInt16 *idxList, *pCurrIdx;
    
    int idxCnt = 3 * nSubAxis * 2 * (nSubHeight - 1);
    int vtxSize = sizeof(float) * 3 * (nSubAxis * (nSubHeight - 1) + 2);
    int idxSize = sizeof(UInt16) * idxCnt;
    
    vtxList = (float *)malloc(vtxSize);
    idxList = (UInt16 *)malloc(idxSize);
    
    if (vtxList == NULL || idxList == NULL) {
        free(vtxList);
        free(idxList);
        return -1; /* Memory Allocation Failed */
    }
    
    half = (nSubHeight - 1) / 2;
    base_angle = (float)M_PI / (float)nSubHeight;
    base_div = (float)M_PI * 2.0f / (float)nSubAxis;
    pEndVtx = (float *)(((UInt8 *)vtxList) + vtxSize);
    
    /* Fill the Vertex Buffer */
    pCurrVtx = vtxList;
    pCurrVtx[0] = 0.0f; pCurrVtx[1] = 1.0f; pCurrVtx[2] = 0.0f;
    
    pCurrVtx = pEndVtx - 3;
    pCurrVtx[0] = 0.0f; pCurrVtx[1] = -1.0f; pCurrVtx[2] = 0.0f;
    
    for (k = 0; k < half; k++) {
        angle = base_angle * (k + 1);
        r = sinf(angle);
        h = cosf(angle);
        
        pCurrVtx = vtxList + 3 + (3 * (nSubAxis * k));
        pCurrVtx2 = pEndVtx - 3 - (3 * (nSubAxis * (k + 1)));
        
        for (i = 0; i < nSubAxis; i++) {
            rad = base_div * i;
            
            pCurrVtx[0] = r * -sinf(rad);
            pCurrVtx[1] = h;
            pCurrVtx[2] = r * -cosf(rad);
            pCurrVtx += 3;
            
            
            pCurrVtx2[0] = r * -sinf(rad);
            pCurrVtx2[1] = -h;
            pCurrVtx2[2] = r * -cosf(rad);
            pCurrVtx2 += 3;
        }
    }
    
    if (nSubHeight % 2 == 0) {
        pCurrVtx = vtxList + (3 * (half * nSubAxis + 1));
        for (i = 0; i < nSubAxis; i++) {
            rad = base_div * i;
            pCurrVtx[0] = -sinf(rad);
            pCurrVtx[1] = 0.0f;
            pCurrVtx[2] = -cosf(rad);
            pCurrVtx += 3;
        }
    }
    
    /* Fill the Index Buffer */
    pCurrIdx = idxList;
    for (i = 1; i <= nSubAxis; i++) {
        pCurrIdx[0] = 0;
        pCurrIdx[1] = i;
        pCurrIdx[2] = (i < nSubAxis ? i : 0) + 1;
        pCurrIdx += 3;
    }
    
    pCurrIdx = (UInt16 *)((((UInt8 *)idxList) + idxSize) - (sizeof(UInt16) * 3 * nSubAxis));
    for (i = 1; i <= nSubAxis; i++) {
        pCurrIdx[0] = nSubAxis * (nSubHeight - 1) + 2 - 1;
        pCurrIdx[1] = pCurrIdx[0] - nSubAxis + (i < nSubAxis ? i : 0);
        pCurrIdx[2] = pCurrIdx[0] - nSubAxis + i - 1;
        pCurrIdx += 3;
    }
    
    pCurrIdx = idxList + (3 * nSubAxis);
    for (k = 0; k < nSubHeight - 2; k++) {
        for (i = 1; i <= nSubAxis; i++) {
            pCurrIdx[0] = pCurrIdx[3] = nSubAxis * k + ((i < nSubAxis ? i : 0) + 1);
            pCurrIdx[1] = nSubAxis * k + i;
            pCurrIdx[2] = pCurrIdx[4] = pCurrIdx[1] + nSubAxis;
            pCurrIdx[5] = pCurrIdx[0] + nSubAxis;
            
            pCurrIdx += 6;
        }
    }
    
    id<MTLBuffer> vb = [device newBufferWithBytes: vtxList length: vtxSize options: BUFFER_DEFAULT_OPTION];
    id<MTLBuffer> ib = [device newBufferWithBytes: idxList length: idxSize options: BUFFER_DEFAULT_OPTION];
    
    free(vtxList);
    free(idxList);
    
    if(!vb || !ib) { return -1; }
    
    pOut->vb  = vb;
    pOut->ib  = ib;
    pOut->cnt = idxCnt;
    
    return 0;
}

static int _genUnitConeStatic(const int nSubHeight, const int nSubDiv, BUFFER_PROPERTIES *pOut, id<MTLDevice> device)
{
    /* No Hat Cylinder / Cone (top radius = bottom radius = 1) */
    int i, j, base_idx;
    float  *vtxList, *pCurrVtx, h, rad;
    UInt16 *idxList, *pCurrIdx;
    
    int idxCnt = 3 * nSubDiv * 2 * nSubHeight;
    int vtxSize = sizeof(float) * 3 * (nSubDiv + 1) * (nSubHeight + 1);
    int idxSize = sizeof(UInt16) * idxCnt;
    
    vtxList = (float *)malloc(vtxSize);
    idxList = (UInt16 *)malloc(idxSize);
    
    if (vtxList == NULL || idxList == NULL) {
        free(vtxList);
        free(idxList);
        return -1; /* Memory Allocation Failed */
    }
    
    /* Fill the Vertex Buffer */
    pCurrVtx = vtxList;
    for (j = 0; j <= nSubHeight; j++) {
        h = 0.5f - ((float)j / (float)nSubHeight);
        for (i = 0; i <= nSubDiv; i++) {
            rad = i < nSubDiv ? ((float)i * (2.0f * (float)M_PI) / (float)nSubDiv) : 0.0f;
            
            pCurrVtx[0] = sinf(rad);
            pCurrVtx[1] = h;
            pCurrVtx[2] = cosf(rad);
            pCurrVtx += 3;
        }
    }
    
    /* Fill the Index Buffer */
    pCurrIdx = idxList;
    for (j = 0; j < nSubHeight; j++) {
        base_idx = j * (nSubDiv + 1);
        for (i = 0; i < nSubDiv; i++) {
            pCurrIdx[0] = pCurrIdx[3] = base_idx + i;
            pCurrIdx[1] = base_idx + i + nSubDiv + 1;
            pCurrIdx[2] = pCurrIdx[4] = base_idx + i + nSubDiv + 2;
            pCurrIdx[5] = base_idx + i + 1;
            pCurrIdx += 6;
        }
    }
    
    id<MTLBuffer> vb = [device newBufferWithBytes: vtxList length: vtxSize options: BUFFER_DEFAULT_OPTION];
    id<MTLBuffer> ib = [device newBufferWithBytes: idxList length: idxSize options: BUFFER_DEFAULT_OPTION];
    
    free(vtxList);
    free(idxList);
    
    if(!vb || !ib) { return -1; }
    
    pOut->vb  = vb;
    pOut->ib  = ib;
    pOut->cnt = idxCnt;
    
    return 0;

}

static int _genUnitTorusElement(BUFFER_PROPERTIES *pOut, id<MTLDevice> device)
{
    const int nSubDiv    = 24;
    const int nSubCircle = 20;
    
    int i, j, base_idx;
    float  *vtxList, *pCurrVtx, m_rad, t_rad;
    UInt16 *idxList, *pCurrIdx;
    
    int idxCnt = 3 * nSubDiv * 2 * nSubCircle;
    int vtxSize = sizeof(float) * 3 * (nSubDiv + 1) * (nSubCircle + 1);
    int idxSize = sizeof(UInt16) * idxCnt;
    
    vtxList = (float *)malloc(vtxSize);
    idxList = (UInt16 *)malloc(idxSize);
    
    /* Fill the Vertex Buffer */
    pCurrVtx = vtxList;
    for (j = 0; j <= nSubDiv; j++) {
        m_rad = (float)j * ((2.0f * (float)M_PI) / (float)nSubDiv);
        for (i = 0; i <= nSubCircle; i++) {
            t_rad = i < nSubCircle ? (float)i * ((2.0f * (float)M_PI) / (float)nSubCircle) : 0.0f;
            pCurrVtx[0] = cosf(t_rad);
            pCurrVtx[1] = sinf(t_rad);
            pCurrVtx[2] = m_rad;
            
            pCurrVtx += 3;
        }
    }
    
    /* Fill the Index Buffer */
    pCurrIdx = idxList;
    for (j = 0; j < nSubDiv; j++) {
        base_idx = j * (nSubCircle + 1);
        for (i = 0; i < nSubCircle; i++) {
            /*
            pCurrIdx[0] = pCurrIdx[3] = base_idx + i;
            pCurrIdx[1] = base_idx + i + nSubCircle + 1;
            pCurrIdx[2] = pCurrIdx[4] = base_idx + i + nSubCircle + 2;
            pCurrIdx[5] = base_idx + i + 1;
            */
            pCurrIdx[0] = pCurrIdx[3] = base_idx + i;
            pCurrIdx[1] = pCurrIdx[5] = base_idx + i + nSubCircle + 2;
            pCurrIdx[2] = base_idx + i + nSubCircle + 1;
            pCurrIdx[4] = base_idx + i + 1;
            
            pCurrIdx += 6;
        }
    }
    
    id<MTLBuffer> vb = [device newBufferWithBytes: vtxList length: vtxSize options: BUFFER_DEFAULT_OPTION];
    id<MTLBuffer> ib = [device newBufferWithBytes: idxList length: idxSize options: BUFFER_DEFAULT_OPTION];
    
    free(vtxList);
    free(idxList);
    
    if(!vb || !ib) { return -1; }
    
    pOut->vb  = vb;
    pOut->ib  = ib;
    pOut->cnt = idxCnt;
    
    return 0;
}
