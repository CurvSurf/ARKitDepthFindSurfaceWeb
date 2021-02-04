# ARKitDepthFindSurfaceWeb

## Abstract

ARKitDepthFindSurfaceWeb is a demo application developed by CurvSurf for 
accumulate point cloud from depth map of Apple LiDAR, 
and find 5 primitive shapes (plane, sphere, cylinder, cone, torus) from that with our FindSurface Web API.

[![Video Label](https://img.youtube.com/vi/sUWCbS_P7b8/0.jpg)](https://youtu.be/sUWCbS_P7b8)

## How to use Program

1. Press **Record** button if you want to start recording (collection) depth points.
1. After recording is finished (when press the **Stop** button), 
1. Select primitive type you want to find.
1. Press **Find** button and wait for a result.

> NOTE: You can export accumulated point cloud data to text format by pressing export button (blue icon on upper right corner next to a motion reset button).

## Methods to consider

1. How to convert depth map to world coordinates

```swift
// Parameters from ARFrame
let localToWorld            : matrix_flaot4x4 // Calculated With Camera Extrinsic Parameter
let cameraIntrinsicsInversed: matrix_float3x3
let cameraResolution        : vector_float2
let depthMapResolution      : vector_float2

let x: Float // x-coordinate of the depth map
let y: Float // y-coordinate of the depth map
let d: Float // depth value of [x, y] coordinates of depth map

let scaleFactor = cameraResolution / depthMapResolution
let localPoint = cameraIntrinsicsInversed 
               * (vector_float3( x * scaleFactor.x, y * scaleFactor.y, 1 ) * d)
let worldPoint = localToWorld * vector_float4( localPoint, 1 )
```

> Note that: **_CameraIntrinscsInversed_**,  **_Camera Resolution_**, **_DepthMap Resolution_** and **_[x, y] coordinates_** will never be changed through entire application life cycle.
Due to remove redundant work, we have made a calculation of dealing these data: **GridElement**.

```swift
// SampleExtension.swift

struct GridElement {
    let x: Int  // X-coordinate of the depth map
    let y: Int  // Y-coordinate of the depth map
    let base: simd_float3 // pre-calculated parameter of [x, y]
    
    // ...omitted...

    static func makeDepthGrid( /* ...omitted... */ ) {
        // ...omitted...
        // Pre-calculation with camera intrinsic parameters here...
        grid.append( GridElement(
            x,
            y,
            cameraIntrinsicsInversed * simd_make_float3( x * rx, y * ry, 1 )
        ) )
        // ...omitted...
    }
}
```

2. Accumulate Point Cloud

```swift
// ViewController.swift

// ln:448
private func accumulatePoints(frame: ARFrame) {
    // ...omitted...

    // Get Camera Parameters
    let camera = frame.camera
    let localToWorld = camera.viewMatrix(for: .landscapeRight).inverse
                     * CameraHelper.makeRotateToARCameraMatrix(orientation: .landscapeRight)
    
    // Get DepthMap
    let frame.sceneDepth.depthMap // or frame.smoothedSceneDepth.depthMap

    // ...omitted...

    // Make Grid Element with Camera Intrinsic Parameter
    // This will be executed only once for initializing.
    let cameraIntrinsicsInversed = camera.intrinsics.inverse // mat3x3
    let cameraResolution         = camera.imageResolution
    depthGrid = GridElement.makeDepthGrid( depthWidth, depthHeight,
                                           cameraIntrinsicInversed: cameraIntrinsicsInversed,
                                           cameraResolution: cameraResolution )

    // ...omitted...

    // Random Sampling Grid Points
    let gridList = depthGrid.sample( UInt(sampleCount) )

    // ...omitted...

    // Depth Map to Point Cloud
    for g in gridList{
        // ...omitted...

        // 1. Get Depth Value From DepthMap on [g.x, g.y] coordinates
        let d = Float((depthData.advanced(by: g.y * depthStride).assumingMemoryBound(to: Float32.self))[g.x])

        // 2. Converting Depth Value to Local 3-D Point (with camera intrinsic parameters)
        let local = simd_make_float4( g.base * Float(d), 1 );

        // 3. Local Coordinates to World Coordinates (with camera extrinsic parameters)
        let worldPoint = localToWorld * local;

        // ...omitted...
    }
}
```

3. Request FindSurface

```swift
// ViewController.swift

// ln:696
@IBAction func onClickMainActionButton(_ sender: Any) {
    // ...omitted...
    runFindSurfaceAsync(
        onSuccess: { (result, extra) -> Void in 
            // TODO: when success
        },
        onFail: { (error) -> Void in 
            // TODO: when fail
        },
        onEnd: { () -> Void in
            // TODO: when all task is done (either success or fail)
        }
    )
    // ...omitted...
}

// See also runFindSurfaceAsync() method on ln:594
```

> NOTE: See **_FindSurfaceWeb.swift_** for actual request process and handling result data.

## License

This project is licensed under the MIT License. Copyright 2021 CurvSurf.