//
//  ShaderTypes.h
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and C/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum VertexBufferIndices {
    kBufferIndexVertex    = 0,
    kBufferIndexMVP       = 1,
    kBufferIndexMV        = 2,
    kBufferIndexMeshParam = 2,
    kBufferIndexColorParam = 3
} VertexBufferIndices;

typedef enum FragmentBufferIndices {
    kBufferIndexColor = 0
} FragmentBufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
typedef enum VertexAttributes {
    kVertexAttributePosition  = 0,
    kVertexAttributeTexcoord  = 1
} VertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef enum TextureIndices {
    kTextureIndexColor    = 0,
    kTextureIndexY        = 1,
    kTextureIndexCbCr     = 2
} TextureIndices;

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum WFVertexBufferIndices {
    WFB_INDEX_VERTICES   = 0,
    WFB_INDEX_INDICIES   = 1,
    WFB_INDEX_MVP        = 2,
    WFB_INDEX_MESH_PARAM = 3,
    WFB_INDEX_SETTING    = 4
} WFVertexBufferIndices;

typedef enum WFFragmentBufferIndices {
    WFB_INDEX_COLOR        = 0,
    WFB_INDEX_SETTING_LINE = 1
} WFFragmentBufferIndices;

#endif /* ShaderTypes_h */
