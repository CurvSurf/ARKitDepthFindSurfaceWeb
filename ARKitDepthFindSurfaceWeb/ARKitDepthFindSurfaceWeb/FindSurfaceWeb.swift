//
//  FindSurfaceWeb.swift
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

import Foundation

// Define Constant
fileprivate let _baseURL  = "https://developers.curvsurf.com/FindSurface"
fileprivate let _reqMIME  = "application/x-findsurface-request"
fileprivate let _respMIME = "application/x-findsurface-response"

fileprivate let REQ_HEADER_SIZE = 40
fileprivate let MIN_FLOAT_STRIDE = UInt32( 3 * MemoryLayout<Float32>.size )
fileprivate let MIN_DOUBLE_STRIDE = UInt32( 3 * MemoryLayout<Float64>.size )

enum FS_FEATURE_TYPE: Int
{
    case FS_TYPE_PLANE = 1
    case FS_TYPE_SPHERE = 2
    case FS_TYPE_CYLINDER = 3
    case FS_TYPE_CONE = 4
    case FS_TYPE_TORUS = 5
    
    var urlName : String {
        switch( self ) {
            case .FS_TYPE_PLANE: return "plane"
            case .FS_TYPE_SPHERE: return "sphere"
            case .FS_TYPE_CYLINDER: return "cylinder"
            case .FS_TYPE_CONE: return "cone"
            case .FS_TYPE_TORUS: return "torus"
        }
    }
    
    var name : String {
        switch( self ) {
            case .FS_TYPE_PLANE: return "Plane"
            case .FS_TYPE_SPHERE: return "Sphere"
            case .FS_TYPE_CYLINDER: return "Cylinder"
            case .FS_TYPE_CONE: return "Cone"
            case .FS_TYPE_TORUS: return "Torus"
        }
    }
}

enum FS_SEARCH_LEVEL: UInt8
{
    case off = 0
    case lv1 = 1
    case lv2 = 2
    case lv3 = 3
    case lv4 = 4
    case lv5 = 5
    case lv6 = 6
    case lv7 = 7
    case lv8 = 8
    case lv9 = 9
    case lv10 = 10
    
    static var defaultLevel: FS_SEARCH_LEVEL { .lv5 }
    static var moderate: FS_SEARCH_LEVEL { .lv1 }
    static var radical: FS_SEARCH_LEVEL { .lv10 }
}

enum FsReqestError: Error
{
    case RequestError(desc: String)
    case NoResponse
    case StatusCodeError(statusCode: Int)
    case InvalidContentType(contentType: String)
    case NoResponseBody
    case InvalidResponseBody
    case UnknownResultCode(resultCode: Int)
}

class InlierList {
    let inlierList: UnsafePointer<simd_float3>
    let inlierCount: Int
    
    fileprivate init(_ list: UnsafePointer<simd_float3>, _ count: Int) {
        inlierList = list
        inlierCount = count
    }
    
    deinit { inlierList.deallocate() }
    
    var buffer: UnsafePointer<simd_float3> { get{ return inlierList } }
    var bufferRaw: UnsafeRawPointer { get { return UnsafeRawPointer(inlierList) } }
    var bufferFloat: UnsafePointer<Float> { get { return bufferRaw.assumingMemoryBound(to: Float.self) } }
    var count: Int { get { return inlierCount } }
    var stride: Int { get { return MemoryLayout<simd_float3>.stride } }
}

class FindSurfaceResult
{
    let responseBody: UnsafeMutableRawPointer
    let responseBodyLength: Int
    
    init(_ responseData : Data) {
        let bufferBytes = responseData.count
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferBytes, alignment: 1)
        responseData.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: bufferBytes)
        
        responseBody = buffer
        responseBodyLength = bufferBytes
    }
    
    deinit { responseBody.deallocate() }
    
    private var headerLength: Int {
        get { return Int(responseBody.load(fromByteOffset: 0x04, as: UInt32.self)) }
    }
    
    private var dataLength: Int {
        get { return Int(responseBody.load(fromByteOffset: 0x0C, as: UInt32.self)) }
    }
    
    public private(set) var type: FS_FEATURE_TYPE {
        get { return FS_FEATURE_TYPE(rawValue: Int(responseBody.load(fromByteOffset: 0x08, as: Int32.self)))! }
        set(val) { responseBody.storeBytes(of: Int32(val.rawValue), toByteOffset: 0x08, as: Int32.self) }
    }
    
    public var rms: Float {
        get { return Float(responseBody.load(fromByteOffset: 0x10, as: Float32.self)) }
    }
    
    public var inlierFlags: UnsafePointer<UInt8>? {
        get {
            if dataLength > 0 {
                return UnsafePointer<UInt8>( responseBody.advanced(by: headerLength).assumingMemoryBound(to: UInt8.self) )
            }
            return nil
        }
    }
    
    public var inlierFlagsLength: Int {
        get { return Int(responseBody.load(fromByteOffset: 0x0C, as: UInt32.self)) }
    }
    
    
    // MARK: - Public Methods
    
    public func reinterpreteFeature() {
        if type == .FS_TYPE_CONE {
            if coneTopRadius == coneBottomRadius { // -> Cylinder
                type = .FS_TYPE_CYLINDER
            }
        }
        else if type == .FS_TYPE_TORUS {
            if torusMeanRadius == 0.0 { // -> Sphere
                type = .FS_TYPE_SPHERE
                sphereRadius = torusTubeRadius
            }
            else if torusMeanRadius == .greatestFiniteMagnitude { //FLT_MAX -> Cylinder
                type = .FS_TYPE_CYLINDER
                cylinderRadius = torusTubeRadius
            }
        }
    }
    
    public func getInliers(fromPointBuffer points: UnsafePointer<simd_float3>, pointCount count: Int) -> InlierList? {
        guard count == inlierFlagsLength,
              let flags = inlierFlags else { return nil }
        
        var inlierCount = 0
        for i in 0..<count { if flags[i] == 0x00 { inlierCount += 1 } }
        
        let inlierList = UnsafeMutableRawPointer.allocate(byteCount: Int(MemoryLayout<simd_float3>.stride * inlierCount), alignment: 1).assumingMemoryBound(to: simd_float3.self)
        
        var dstIdx = 0
        for i in 0..<count {
            if flags[i] == 0x00 {
                inlierList[dstIdx] = points[i]
                dstIdx += 1
            }
        }
        return InlierList( UnsafePointer<simd_float3>(inlierList), inlierCount )
    }
    
    public func getInliers(fromPointerBuffer buffer: UnsafeRawPointer, pointCount count: Int, pointStride stride: Int) -> InlierList? {
        guard count == inlierFlagsLength,
              let flags = inlierFlags else { return nil }
        
        var inlierCount = 0
        for i in 0..<count { if flags[i] == 0x00 { inlierCount += 1 } }
        
        let inlierList = UnsafeMutableRawPointer.allocate(byteCount: Int(MemoryLayout<simd_float3>.stride * inlierCount), alignment: 1).assumingMemoryBound(to: simd_float3.self)
        
        var dstIdx = 0
        for i in 0..<count {
            if flags[i] == 0x00 {
                let FloatArr = buffer.advanced(by: (stride * i)).assumingMemoryBound(to: Float32.self)
                inlierList[dstIdx] = simd_make_float3( FloatArr[0], FloatArr[1], FloatArr[2] )
                dstIdx += 1
            }
        }
        return InlierList( UnsafePointer<simd_float3>(inlierList), inlierCount )
    }
    
    // Case> Plane
    
    public var planeLL: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 20, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 24, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 28, as: Float32.self))
            )
        }
    }
    
    public var planeLR: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 32, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 36, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 40, as: Float32.self))
            )
        }
    }
    
    public var planeUR: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 44, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 48, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 52, as: Float32.self))
            )
        }
    }
    
    public var planeUL: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 56, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 60, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 64, as: Float32.self))
            )
        }
    }
    
    // Case> Sphere
    
    public var sphereCenter: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 20, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 24, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 28, as: Float32.self))
            )
        }
    }
    
    public private(set) var sphereRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 32, as: Float32.self)) }
        set(val) { responseBody.storeBytes(of: Float32(val), toByteOffset: 32, as: Float32.self) }
    }
    
    // Case> Cylinder
    
    public var cylinderBottom: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 20, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 24, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 28, as: Float32.self))
            )
        }
    }
    
    public var cylinderTop: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 32, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 36, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 40, as: Float32.self))
            )
        }
    }
    
    public private(set) var cylinderRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 44, as: Float32.self)) }
        set(val) { responseBody.storeBytes(of: Float32(val), toByteOffset: 44, as: Float32.self) }
    }
    
    // Case> Cone
    
    public var coneBottom: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 20, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 24, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 28, as: Float32.self))
            )
        }
    }
    
    public var coneTop: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 32, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 36, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 40, as: Float32.self))
            )
        }
    }
    
    public var coneBottomRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 44, as: Float32.self)) }
    }
    
    public var coneTopRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 48, as: Float32.self)) }
    }
    
    // Case> Torus
    
    public var torusCenter: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 20, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 24, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 28, as: Float32.self))
            )
        }
    }
    
    public var torusNormal: simd_float3 {
        get {
            return simd_float3(
                Float(responseBody.load(fromByteOffset: 32, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 36, as: Float32.self)),
                Float(responseBody.load(fromByteOffset: 40, as: Float32.self))
            )
        }
    }
    
    public var torusMeanRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 44, as: Float32.self)) }
    }
    
    public var torusTubeRadius: Float {
        get { return Float(responseBody.load(fromByteOffset: 48, as: Float32.self)) }
    }
}

class FindSurfaceWeb
{
    var headerBuffer = UnsafeMutableRawPointer.allocate(byteCount: REQ_HEADER_SIZE, alignment: 1)
    var lastRequestElapsedTime: Double = 0.0
    
    init() {
        // Zero Memory
        headerBuffer.initializeMemory(as: UInt8.self, repeating: 0x00, count: REQ_HEADER_SIZE)
        // Fill Fixed Memory Values
        headerBuffer.storeBytes(of: 0x46, toByteOffset: 0x00, as: UInt8.self) // 'F'
        headerBuffer.storeBytes(of: 0x53, toByteOffset: 0x01, as: UInt8.self) // 'S'
        headerBuffer.storeBytes(of: 0x01, toByteOffset: 0x02, as: UInt8.self) // major - 1
        headerBuffer.storeBytes(of: 0x00, toByteOffset: 0x03, as: UInt8.self) // minor - 0
        headerBuffer.storeBytes(of: UInt32(REQ_HEADER_SIZE), toByteOffset:0x04, as: UInt32.self) // Sizeof Header
    }
    deinit { headerBuffer.deallocate() }
    

    // MARK: - Properties
    
    public private(set) var pointCount: UInt32 {
        get { return headerBuffer.load(fromByteOffset: 0x08, as: UInt32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x08, as: UInt32.self) }
    }
    public private(set) var pointOffset: UInt32 {
        get { return headerBuffer.load(fromByteOffset: 0x0C, as: UInt32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x0C, as: UInt32.self) }
    }
    public private(set) var pointStride: UInt32 {
        get { return headerBuffer.load(fromByteOffset: 0x10, as: UInt32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x10, as: UInt32.self) }
    }
    public private(set) var measurementAccuracy: Float32 {
        get { return headerBuffer.load(fromByteOffset: 0x14, as: Float32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x14, as: Float32.self) }
    }
    public private(set) var meanDistance: Float32 {
        get { return headerBuffer.load(fromByteOffset: 0x18, as: Float32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x18, as: Float32.self) }
    }
    public private(set) var touchRadius: Float32 {
        get { return headerBuffer.load(fromByteOffset: 0x1C, as: Float32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x1C, as: Float32.self) }
    }
    public private(set) var seedIndex: UInt32 {
        get { return headerBuffer.load(fromByteOffset: 0x20, as: UInt32.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x20, as: UInt32.self) }
    }
    public private(set) var radialExpansion: FS_SEARCH_LEVEL {
        get { return FS_SEARCH_LEVEL( rawValue: headerBuffer.load(fromByteOffset: 0x25, as: UInt8.self) )! }
        set( val ) { headerBuffer.storeBytes(of: val.rawValue, toByteOffset:0x25, as: UInt8.self) }
    }
    public private(set) var lateralExtension: FS_SEARCH_LEVEL {
        get { return FS_SEARCH_LEVEL( rawValue: headerBuffer.load(fromByteOffset: 0x26, as: UInt8.self) )! }
        set( val ) { headerBuffer.storeBytes(of: val.rawValue, toByteOffset:0x26, as: UInt8.self) }
    }
    private var optionFlag: UInt8 {
        get { return headerBuffer.load(fromByteOffset: 0x27, as: UInt8.self) }
        set( val ) { headerBuffer.storeBytes(of: val, toByteOffset:0x27, as: UInt8.self) }
    }
    private var useDoublePrecision: Bool {
        get { return (optionFlag & 0x02) != 0 }
        set (val) {
            if val {
                optionFlag = optionFlag | 0x02
            }
            else {
                optionFlag = optionFlag & ~0x02
            }
        }
    }
    private var requestInliers: Bool {
        get { return (optionFlag & 0x01) != 0 }
        set (val) {
            if val {
                optionFlag = optionFlag | 0x01
            }
            else {
                optionFlag = optionFlag & ~0x01
            }
        }
    }
    
    // MARK: - Private Methods

    private func open(withFindType findType: FS_FEATURE_TYPE, andRequestBody data: Data) -> URLRequest {
        var urlReq = URLRequest(url: URL(string: _baseURL + "/" + findType.urlName)!)
        urlReq.httpMethod = "POST"
        urlReq.setValue( _reqMIME, forHTTPHeaderField: "Content-Type" )
        
        if CFByteOrderGetCurrent() == CFByteOrder( CFByteOrderBigEndian.rawValue ) {
            urlReq.setValue("big", forHTTPHeaderField: "X-Content-Endian")
            urlReq.setValue("big", forHTTPHeaderField: "X-Accept-Endian")
        }
        
        urlReq.httpBody = data
        
        return urlReq
    }
    
    // MARK: - Public Methods
    
    public func setPointBufferDescription( pointCount count: UInt32 ) {
        pointCount = count
        pointOffset = 0
        pointStride = MIN_FLOAT_STRIDE
        useDoublePrecision = false
    }
    
    public func setPointBufferDescription( pointCount count: UInt32, useDoublePrecision use: Bool ) {
        pointCount = count
        pointStride = MIN_FLOAT_STRIDE
        pointOffset = 0
        useDoublePrecision = use
    }
    
    public func setPointBufferDescription( pointCount count: UInt32, pointStride stride: UInt32 ) {
        pointCount = count
        pointStride = stride < MIN_FLOAT_STRIDE ? MIN_FLOAT_STRIDE : stride;
        pointOffset = 0
        useDoublePrecision = false
    }
    
    public func setPointBufferDescription( pointCount count: UInt32, pointStride stride: UInt32, useDoublePrecision use: Bool ) {
        let MIN_STRIDE = use ? MIN_DOUBLE_STRIDE : MIN_FLOAT_STRIDE
        
        pointCount = count
        pointStride = stride < MIN_STRIDE ? MIN_STRIDE : stride
        pointOffset = 0
        useDoublePrecision = use
    }
    
    public func setPointBufferDescription( pointCount count: UInt32, pointStride stride: UInt32, pointOffset offset: UInt32 ) {
        pointCount = count
        pointStride = stride < MIN_FLOAT_STRIDE ? MIN_FLOAT_STRIDE : stride;
        pointOffset = offset
        useDoublePrecision = false
    }
    
    public func setPointBufferDescription( pointCount count: UInt32, pointStride stride: UInt32, pointOffset offset: UInt32, useDoublePrecision use: Bool ) {
        let MIN_STRIDE = use ? MIN_DOUBLE_STRIDE : MIN_FLOAT_STRIDE
        
        pointCount = count
        pointStride = stride < MIN_STRIDE ? MIN_STRIDE : stride
        pointOffset = offset
        useDoublePrecision = use
    }
    
    public func setPointDataDescription( measurementAccuracy ma: Float32, meanDistance md: Float32 ) {
        measurementAccuracy = ma
        meanDistance = md
    }
    
    public func setSeedRegion( seedPointIndex index: UInt32, regionRadius radius: Float32 ) {
        seedIndex = index
        touchRadius = radius
    }
    
    public func setRadialExpansionLevel( searchLevel level: FS_SEARCH_LEVEL ) {
        radialExpansion = level
    }
    
    public func setLateralExtensionLevel( searchLevel level: FS_SEARCH_LEVEL ) {
        lateralExtension = level
    }
    
    public func getLastRequestElapsedTime() -> Double {
        return lastRequestElapsedTime
    }
    
    public func requestFindSurface( findType type: FS_FEATURE_TYPE, withPointData pointData: UnsafePointer<simd_float3>, requestInliers reqIn: Bool = false ) throws -> FindSurfaceResult? {
        return try requestFindSurface(findType: type, withPointDataRaw: UnsafeRawPointer(pointData), requestInliers: reqIn)
    }
    public func requestFindSurface( findType type: FS_FEATURE_TYPE, withPointDataRaw pointData: UnsafeRawPointer, requestInliers reqIn: Bool = false ) throws -> FindSurfaceResult? {
        // Set Request Inliers Flags
        requestInliers = reqIn
        
        let pointBufferBytes = Int(pointCount * pointStride)
        var requestBody = Data(capacity: REQ_HEADER_SIZE + pointBufferBytes)
        requestBody.append( headerBuffer.bindMemory(to: UInt8.self, capacity: REQ_HEADER_SIZE), count: REQ_HEADER_SIZE )
        requestBody.append( pointData.bindMemory(to: UInt8.self, capacity: pointBufferBytes), count: pointBufferBytes )
        
        var fsErr: FsReqestError? = nil
        var fsResult: FindSurfaceResult? = nil
        // ResultProtocol?
        
        let urlRequest = open(withFindType: type, andRequestBody: requestBody)
        let finishCondition = NSCondition()
        let requestTask = URLSession.shared.dataTask(with: urlRequest, completionHandler: { data, response, error in
            guard error == nil else {
                fsErr = .RequestError(desc: error!.localizedDescription)
                finishCondition.signal()
                return
            }
            
            guard let resp = response as? HTTPURLResponse else {
                fsErr = .NoResponse
                finishCondition.signal()
                return
            }
            
            guard resp.statusCode == 200 else {
                fsErr = .StatusCodeError(statusCode: resp.statusCode)
                finishCondition.signal()
                return
            }
            
            guard let contentType = resp.allHeaderFields["Content-Type"] as? String,
                  contentType == _respMIME
            else {
                fsErr = .InvalidContentType(contentType: resp.allHeaderFields["Content-Type"] as? String ?? "")
                finishCondition.signal()
                return
            }
            
            guard let responseData = data else {
                fsErr = .NoResponseBody
                finishCondition.signal()
                return
            }
            
            responseData.withUnsafeBytes({ responseBody in
                if  responseBody.load(fromByteOffset: 0x00, as: UInt8.self) != 0x46 ||
                    responseBody.load(fromByteOffset: 0x01, as: UInt8.self) != 0x53 ||
                    responseBody.load(fromByteOffset: 0x02, as: UInt8.self) != 0x01 ||
                    responseBody.load(fromByteOffset: 0x03, as: UInt8.self) != 0x00
                {
                    fsErr = .InvalidResponseBody
                    finishCondition.signal()
                    return
                }
                
                let resultCode = Int(responseBody.load(fromByteOffset: 0x08, as: Int32.self))
                switch( resultCode )
                {
                case 0: // Not Found
                    break
                case 1, 2, 3, 4, 5:
                    fsResult = FindSurfaceResult( responseData )
                default: // Unexpected Value
                    fsErr = .UnknownResultCode(resultCode: resultCode)
                }
            })
            
            finishCondition.signal()
        })
        
        let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        
        requestTask.resume()
        finishCondition.wait()
        
        let elapsedTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - startTime
        
        self.lastRequestElapsedTime = Double(elapsedTime) / Double(1000000000) // nanosec to sec
        
        if let error = fsErr { throw error }
        
        return fsResult
    }
}
