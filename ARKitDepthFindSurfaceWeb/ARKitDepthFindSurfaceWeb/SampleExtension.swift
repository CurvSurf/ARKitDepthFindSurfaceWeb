//
//  SampleExtension.swift
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

import simd
import CoreMedia

struct GridElement
{
    let x: Int
    let y: Int
    let base: simd_float3
    
    init( _ _x: Int, _ _y: Int, _ _base: simd_float3 ) {
        x = _x;
        y = _y;
        base = _base;
    }
    
    static func makeDepthGrid(_ width: Int, _ height: Int, cameraIntrinsicsInversed: simd_float3x3, cameraResolution:CGSize ) -> [GridElement] {
        var grid:[GridElement] = [];
        grid.reserveCapacity(width * height);
        
        let rx = Float(cameraResolution.width) / Float(width)
        let ry = Float(cameraResolution.height) / Float(height)
        
        for y in 0..<height {
            for x in 0..<width {
                grid.append( GridElement( x, y, cameraIntrinsicsInversed * simd_make_float3(Float(x) * rx, Float(y) * ry, 1) ));
            }
        }
        
        return grid;
    }
}

enum Sampling
{
    case full, div_2, div_4, div_8, div_16, div_32, div_64, div_128, div_256, div_512
    
    func denominator() -> Int {
        switch(self)
        {
        case .full: return 1;
        case .div_2: return 2;
        case .div_4: return 4;
        case .div_8: return 8;
        case .div_16: return 16;
        case .div_32: return 32;
        case .div_64: return 64;
        case .div_128: return 128;
        case .div_256: return 256;
        case .div_512: return 512;
        }
    }
    
    func real() -> Float {
        switch(self)
        {
        case .full: return 1.0;
        case .div_2: return 0.5;
        case .div_4: return 0.25;
        case .div_8: return 0.125;
        case .div_16: return 0.0625;
        case .div_32: return 0.03125;
        case .div_64: return 0.015625;
        case .div_128: return 0.0078125;
        case .div_256: return 0.00390625;
        case .div_512: return 0.001953125;
        }
    }
}

extension Array
{
    func sample(_ count: UInt) -> [Element]
    {
        let sampleCount = Swift.min(numericCast(count), self.count)
        guard sampleCount > 0 else { return []; }
        
        var elements = Array(self)
        var samples: [Element] = []
        samples.reserveCapacity(sampleCount)
        
        while samples.count < sampleCount {
            let idx = arc4random_uniform(numericCast(elements.count))
            samples.append( elements.remove(at: Int(idx)) )
        }
        
        return samples
    }
}
