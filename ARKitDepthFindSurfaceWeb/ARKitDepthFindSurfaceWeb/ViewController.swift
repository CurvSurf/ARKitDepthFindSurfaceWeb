//
//  ViewController.swift
//  ARKitDetphFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import ARKit

// Defined Constants
let KEY_MEASUREMENT_ACCURACY = "MeasurementAccuracy"
let KEY_MEAN_DISTANCE        = "MeanDistance"
let KEY_LATERAL_EXTENSION    = "LateralExtension"
let KEY_RADIAL_EXPANSION     = "RadialExpansion"

// Maximum number of points we store in the point cloud
let maxPoints = 500_000

enum RuntimeError : Error {
    case error(String)
}

extension MTKView : RenderDestinationProvider {
}

class ViewController: UIViewController, MTKViewDelegate, ARSessionDelegate {
    @IBOutlet weak var mainActionButton: UIButton!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var clrButton: UIButton!
    @IBOutlet weak var resetMotionButton: UIButton!
    @IBOutlet weak var findTypeSelector: UISegmentedControl!
    @IBOutlet weak var probeView: UIView!
    @IBOutlet weak var circleView: UIView!
    @IBOutlet weak var cubeView: UIImageView!
    @IBOutlet weak var pointShowButton: UIButton!
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var statusTextField: UITextField!
    @IBOutlet weak var probeSlider: UISlider!
    @IBOutlet weak var pointCountLabel: UILabel!
    @IBOutlet weak var smoothSelector: UISegmentedControl!
    
    // Pre-loaded UI Images
    let captureImage     = UIImage(named: "capture")
    let recordStartImage = UIImage(named: "record")
    let recordStopImage  = UIImage(named: "record_stop")
    let findBtnImage     = UIImage(named: "findBtn")
    
    // Camera's threshold values for detecting when the camera moves so that we can accumulate the points
    let cameraRotationThreshold = cos(5 * .degreesToRadian)
    let cameraTranslationThreshold: Float = pow(0.05, 2)   // (meter-squared)
    // Depth Data Sampling Rate ( current value is 1/256 )
    let sampleRate: Sampling = .div_256
    
    // ARKit Session
    var session: ARSession!
    
    // Metal Renderer
    var renderer: Renderer!
    
    // App state (include UI) related variable
    var recording: Bool = false
    var recorded: Bool = false;
    var currentPixelRadius: Float = 64.0
    var currentPixelLocation: CGPoint =  CGPoint(x: 0.0, y: 0.0)
    var currentProbeRatio: Float = 0.25 // <-> probeSlider: UISlider
    
    // Depth data related Variables
    var smoothDepth: Bool = true // <-> smoothSelector: UISegmentedControl
    var depthGrid: [GridElement] = []
    let pointcloud_queue = DispatchQueue(label: "PointCloud", attributes: [], autoreleaseFrequency: .workItem) // serial queue
    var pointBuffer: UnsafeMutableRawPointer = UnsafeMutableRawPointer.allocate(byteCount: maxPoints * MemoryLayout<simd_float3>.stride, alignment: 1)
    var currentPointIndex = 0
    var currentPointCount = 0
    var lastCameraTransform = simd_float4x4(); // Camera's last transform value for detecting when the camera moves.
    
    // FindSurface related Variables
    var isFindSurfaceRunning: Bool = false
    var findType: FS_FEATURE_TYPE = .FS_TYPE_PLANE // <-> findTypeSelector: UISegmentedControl
    let findsurface_queue = DispatchQueue(label: "FindSurface", attributes: [], autoreleaseFrequency: .workItem) // serial queue
    // FindSurface Parameters
    var paramMA : Float    = 0.02 // Measurement Accuracy
    var paramMD : Float    = 0.2  // Mean Distance
    var paramLAT: FS_SEARCH_LEVEL = FS_SEARCH_LEVEL.defaultLevel
    var paramRAD: FS_SEARCH_LEVEL = FS_SEARCH_LEVEL.defaultLevel
    // FindSurface Requestor
    let fsRequestor: FindSurfaceWeb = FindSurfaceWeb()
    
    // MARK: - ViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Disable DarkMode
        if #available(iOS 13.0, *) { overrideUserInterfaceStyle = .light }
        
        let myDelegate = UIApplication.shared.delegate as! AppDelegate
        myDelegate.myViewController = self
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Set the view's delegate
        session = ARSession()
        session.delegate = self
        
        // Sync FindType Variable with UISegment
        onChangeType(findTypeSelector)
        
        // Sync Probe Slider
        probeSlider.value = currentProbeRatio
        
        // Sync Smooth
        smoothSelector.selectedSegmentIndex = smoothDepth ? 1 : 0
        
        // Set the view to use the default metal device
        if let view = self.view as? MTKView {
            view.device = MTLCreateSystemDefaultDevice()
            view.backgroundColor = UIColor.clear
            view.delegate = self
            
            guard view.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            
            // Set Touch Event
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(onPinchGesture))
            view.addGestureRecognizer( pinchGesture )
            
            // Configure the renderer to draw to the view
            renderer = Renderer(session: session, metalDevice: view.device!, renderDestination: view)
            renderer.drawRectResized(size: view.bounds.size)
            
            // Reset View UI
            resetSomeView()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onForeground()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onBackground()
    }
    
    override func didReceiveMemoryWarning() {
        print("Low Memory Warning!!!")
    }
    
    func onForeground() {
        runSession()
        // Load Configuration File
        loadConfigFromFile()
    }
    
    func onBackground() {
        resetSomeView()
        // Pause the view's session
        session.pause()
        
        // Save Configuration File
        saveConfigToFile()
    }
    
    // MARK: - MTKViewDelegate
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        // Update
        updateFrameData()
        
        // Render
        renderer.render()
    }
    
    func updateFrameData() {
        guard !recorded,
              let frame = session.currentFrame else { return }
        
        if recording {
            if shouldAccumulate(frame: frame) {
                accumulatePoints(frame: frame)
            }
        }
        else {
            // Collect Vertices Everty Time
            currentPointIndex = 0;
            currentPointCount = 0; // Reset Accumulate Buffer
            accumulatePoints(frame: frame)
        }
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.runSession(withReset: true)
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        runSession(withReset: true)
    }
    
    // MARK: - private functions: related with Configuration (also see: ConfigAlertViewController.swift)
    
    private func getConfigFilePathURL() -> URL {
        let fm  = FileManager.default
        let docURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docURL.appendingPathComponent("fs_param.plist")
    }
    
    private func loadConfigFromFile() {
        let pathURL = getConfigFilePathURL()
        if let settings = NSDictionary(contentsOf: pathURL) {
            let ma  = settings.object(forKey: KEY_MEASUREMENT_ACCURACY) as! NSNumber
            let md  = settings.object(forKey: KEY_MEAN_DISTANCE) as! NSNumber
            let lat = settings.object(forKey: KEY_LATERAL_EXTENSION) as! NSNumber
            let rad = settings.object(forKey: KEY_RADIAL_EXPANSION) as! NSNumber
            
            paramMA = ma.floatValue
            paramMD = md.floatValue
            paramLAT = FS_SEARCH_LEVEL( rawValue: lat.uint8Value )!
            paramRAD = FS_SEARCH_LEVEL( rawValue: rad.uint8Value )!
        }
    }
    
    private func saveConfigToFile() {
        let pathURL = getConfigFilePathURL()
        let settings :NSDictionary = [
            KEY_MEASUREMENT_ACCURACY : NSNumber(value: paramMA),
            KEY_MEAN_DISTANCE        : NSNumber(value: paramMD),
            KEY_LATERAL_EXTENSION    : NSNumber(value: paramLAT.rawValue),
            KEY_RADIAL_EXPANSION     : NSNumber(value: paramRAD.rawValue)
        ]
        do { try settings.write(to: pathURL) }
        catch let error {
            print(error)
        }
    }
    
    private func showConfigDialog() {
        guard let sb = self.storyboard else { return }
        
        let dlg = UIAlertController(title: "Configuration", message: nil, preferredStyle: .alert)
        
        // View Setting
        let configView = sb.instantiateViewController(identifier: "ConfigAlert") as! ConfigAlertViewController
        configView.preferredContentSize = CGSize(width: 300, height: 400)
        dlg.setValue(configView, forKey: "contentViewController")
        
        // Button Setting
        let cancelAction = UIAlertAction(title: "Close", style: .cancel, handler: nil)
        let okAction     = UIAlertAction(title: "Update", style: .default, handler: { _ in
            configView.resetTextFieldStatus()
            
            // Get & Check Config. Values
            let ma = configView.measurementAccuracy
            if ma <= 0.0 {
                self.present(dlg, animated: true, completion: {
                    configView.focusToMeasurementAccuracy()
                })
                return
            }
            
            let md = configView.meanDistance
            if md <= 0.0 {
                self.present(dlg, animated: true, completion: {
                    configView.focusToMeanDistance()
                })
                return
            }
            
            let lat = FS_SEARCH_LEVEL( rawValue: configView.lateralExtension )!
            let rad = FS_SEARCH_LEVEL( rawValue: configView.radialExpension )!
            
            // Update
            self.paramMA = ma
            self.paramMD = md
            self.paramLAT = lat
            self.paramRAD = rad
        })
        dlg.addAction(okAction)
        dlg.addAction(cancelAction)
        
        present(dlg, animated: true, completion: {
            configView.setInitialValue(self.paramMA, self.paramMD, self.paramLAT.rawValue, self.paramRAD.rawValue)
            configView.enableViews(true)
        })
    }
    
    // MARK: - private functions: UI Element handling related functions
    
    private func showCircleView(_ isShow: Bool)
    {
        probeView.isHidden = !isShow;
        circleView.isHidden = !isShow;
        cubeView.isHidden = !isShow;
        
        if(isShow) {
            probeView.alpha = 0;
            circleView.alpha = 0;
            cubeView.alpha = 0;
            
            UIView.animate(withDuration: 0.05, animations: {
                self.probeView.alpha = 1;
                self.circleView.alpha = 1
                self.cubeView.alpha = 0.5
            }, completion: { (done) in
                if done { self.moveCircleView() }
            })
        }
    }
    
    private func moveCircleView()
    {
        let size = CGFloat( currentPixelRadius < 32.0 ? 32.0 : currentPixelRadius )
        let half = size / 2.0
        
        circleView.frame = CGRect(x: currentPixelLocation.x - half, y: currentPixelLocation.y - half, width: size, height: size)
        circleView.layer.cornerRadius = half;
        circleView.layer.borderWidth = 2.0
        circleView.layer.borderColor = UIColor.white.cgColor
        
        let probeSize = (size * CGFloat(currentProbeRatio)) < 5.0 ? 5.0 : (size * CGFloat(currentProbeRatio))
        let probeHalf = probeSize / 2.0
        
        probeView.frame = CGRect(x: currentPixelLocation.x - probeHalf, y: currentPixelLocation.y - probeHalf, width: probeSize, height: probeSize)
        probeView.layer.cornerRadius = probeHalf;
        probeView.layer.borderWidth = 2.0
        probeView.layer.borderColor = UIColor.red.cgColor
        
        let cubeSize = CGFloat(32.0)
        let cubeHalf = cubeSize / 2.0
        
        cubeView.frame = CGRect(origin: CGPoint(x: currentPixelLocation.x - cubeHalf, y: currentPixelLocation.y - cubeHalf),
                                size: CGSize(width: cubeSize, height: cubeSize))
    }
    
    private func updateTypeSegmentView(){
        switch findType
        {
        case .FS_TYPE_PLANE:    findTypeSelector.selectedSegmentIndex = 0
        case .FS_TYPE_SPHERE:   findTypeSelector.selectedSegmentIndex = 1
        case .FS_TYPE_CYLINDER: findTypeSelector.selectedSegmentIndex = 2
        case .FS_TYPE_CONE:     findTypeSelector.selectedSegmentIndex = 3
        case .FS_TYPE_TORUS:    findTypeSelector.selectedSegmentIndex = 4
        }
    }
    
    private func resetSomeView()
    {
        // Clear Every States, Properties, and so on.
        self.recording = false
        self.recorded = false
        self.renderer.clearMeshList()
        
        self.currentPixelRadius = Float((view.bounds.width < view.bounds.height) ? view.bounds.width : view.bounds.height) / ( 5.0 )
        self.currentPixelLocation = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        self.moveCircleView()
        self.showCircleView(false)
        
        self.resetMotionButton.isEnabled = true
        self.captureButton.isEnabled = true
        self.clrButton.isEnabled = false
        self.undoButton.isEnabled = false
        self.mainActionButton.isEnabled = false
        
        self.mainActionButton.setImage(findBtnImage, for: .normal)
        self.statusTextField.text = nil
        self.pointCountLabel.text = "0"
        
        self.pointShowButton.setTitle("Hide", for: .normal)
        self.renderer.showPointcloud = true
    }
    
    private func _enableMainButtons(_ isEnable: Bool)
    {
        resetMotionButton.isEnabled = isEnable
        mainActionButton.isEnabled  = isEnable
        captureButton.isEnabled     = isEnable
        clrButton.isEnabled         = isEnable
    }
    
    // MARK: - private functions: ARKit
    
    private func runSession(withReset _reset: Bool = false)
    {
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [] // Disable Embeded Plane Detection
        configuration.frameSemantics = [ .sceneDepth, .smoothedSceneDepth ]
        
        if _reset {
            DispatchQueue.main.async { self.resetSomeView() }
        }
        
        let options: ARSession.RunOptions = _reset ? [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction] : []
        session.run(configuration, options: options)
        
        // The screen shouldn't dim during AR experiecnes.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    // MARK: - private functions: ARKit Depth data handling related functions
    
    private func shouldAccumulate(frame: ARFrame) -> Bool {
        let cameraTransform = frame.camera.transform
        return currentPointCount == 0
            || dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
            || distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold
    }
    
    private func accumulatePoints(frame: ARFrame) {
        guard let frame = session.currentFrame,
              let sceneDepth = smoothDepth ? frame.smoothedSceneDepth : frame.sceneDepth,
              let confidenceMap = sceneDepth.confidenceMap else { return }
        
        let camera = frame.camera
        let localToWorld = camera.viewMatrix(for: .landscapeRight).inverse
                         * CameraHelper.makeRotateToARCameraMatrix(orientation: .landscapeRight) // mat4x4
        
        let depthMap = sceneDepth.depthMap
        
        let depthWidth  = CVPixelBufferGetWidthOfPlane(depthMap, 0)  // 256
        let depthHeight = CVPixelBufferGetHeightOfPlane(depthMap, 0) // 192
        
        let maxCount = depthWidth * depthHeight
        let sampleCount = maxCount / sampleRate.denominator()
        
        // let confidenceWidth = CVPixelBufferGetWidthOfPlane(confidenceMap, 0) // must be same with depthWidth
        // let confidenceHeight = CVPixelBufferGetHeightOfPlane(confidenceMap, 0) // must be same with depthHeight
        
        if(depthGrid.count != maxCount) {
            let cameraIntrinsicsInversed = camera.intrinsics.inverse // mat3x3
            let cameraResolution = camera.imageResolution
            depthGrid = GridElement.makeDepthGrid(depthWidth, depthHeight, cameraIntrinsicsInversed: cameraIntrinsicsInversed, cameraResolution: cameraResolution);
        }
        
        // Access to Depth Map
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        
        let depthStride = CVPixelBufferGetBytesPerRowOfPlane(depthMap, 0)
        let confidenceStride = CVPixelBufferGetBytesPerRowOfPlane(confidenceMap, 0)
        
        let depthData = CVPixelBufferGetBaseAddressOfPlane(depthMap, 0)!
        let confidenceData = CVPixelBufferGetBaseAddressOfPlane(confidenceMap, 0)!
        
        let gridList = depthGrid.sample(UInt(sampleCount)) // Sampling Depth Points
        
        var pointList: [simd_float3] = [];
        pointList.reserveCapacity(gridList.count)
        
        let pointBufferS = pointBuffer.assumingMemoryBound(to: simd_float3.self);
        var count = 0;
        
        // Depth Map to Point Cloud
        for g in gridList {
            let c = Int( (confidenceData.advanced(by: g.y * confidenceStride).assumingMemoryBound(to: UInt8.self))[g.x] )
            if c != ARConfidenceLevel.high.rawValue { continue } // Check Confidence Value
            
            let d = Float((depthData.advanced(by: g.y * depthStride).assumingMemoryBound(to: Float32.self))[g.x])
            let worldPoint = localToWorld * simd_make_float4(g.base * Float(d), 1)
            
            let newIndex = (currentPointIndex + count) % maxPoints;
            pointBufferS[newIndex] = simd_make_float3( worldPoint / worldPoint.w );
            count += 1;
        }
    
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        
        currentPointIndex = (currentPointIndex + count) % maxPoints;
        currentPointCount = min( maxPoints, currentPointCount + count );
        
        lastCameraTransform = frame.camera.transform
        
        pointCountLabel.text = "\(currentPointCount)"
        renderer.updatePointCloud( pointsRaw: pointBuffer, pointCount: currentPointCount, pointStride: MemoryLayout<simd_float3>.stride )
    }
    
    // Save Accumulated Point Cloud to File
    private func exportAccumulatedPoints() {
        guard recorded, currentPointCount > 0 else { return }
        
        _enableMainButtons(false)
        pointcloud_queue.async {
            let fm = FileManager.default
            let docURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let exportURL = docURL.appendingPathComponent( "export", isDirectory:  true )
            
            var isDir: ObjCBool = ObjCBool(false)
            do {
                // Create Target Directory (if does not exist)
                if !fm.fileExists(atPath: exportURL.path, isDirectory: &isDir) {
                    try fm.createDirectory(at: exportURL, withIntermediateDirectories: true, attributes: nil)
                }
                else if !isDir.boolValue {
                    throw RuntimeError.error("[\(exportURL.path)]: Target path is already exist as a regular file")
                }
                
                let df = DateFormatter();
                df.dateFormat = "yyyyMMdd_HHmmss";
                let nowStr = df.string(from: Date())
                let fileName = "points_\(nowStr).xyz"
                
                let fileURL = exportURL.appendingPathComponent( fileName )
                let points = self.pointBuffer.assumingMemoryBound(to: simd_float3.self)
                
                // Create Empty File First
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
                // Open Empty File for Writing
                let hFile = try FileHandle(forWritingTo: fileURL)
                for i in 0..<self.currentPointCount {
                    hFile.write( "\(points[i].x) \(points[i].y) \(points[i].z)\n".data(using: .utf8)! )
                }
                // Close after Writing
                try hFile.close()
                
                DispatchQueue.main.async {
                    self.statusTextField.text = "Export: \(fileName) success"
                }
            }
            catch {
                //print("Export Error: \(error)")
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "Export Error", message: "\(error)", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "Close", style:. cancel))
                    self.present(alertController, animated: true, completion: nil)
                }
            }
            
            DispatchQueue.main.async { self._enableMainButtons(true) }
        }
    }
    // MARK: - private functions: FindSurface Task related functions
    
    private func _pickPoint( rayDirection ray_dir: simd_float3, rayPosition ray_pos: simd_float3, vertices list: UnsafePointer<simd_float3>, count: Int, _ unitRadius: Float) -> Int {
        let UR_SQ_PLUS_ONE = unitRadius * unitRadius + 1.0
        var minLen: Float = Float.greatestFiniteMagnitude
        var maxCos: Float = -Float.greatestFiniteMagnitude
        
        var pickIdx   : Int = -1
        var pickIdxExt: Int = -1
        
        for idx in 0..<count {
            let sub = list[idx] - ray_pos
            let len1 = simd_dot( ray_dir, sub )
            
            if len1 < Float.ulpOfOne { continue; } // Float.ulpOfOne == FLT_EPSILON
            // 1. Inside ProbeRadius (Picking Cylinder Radius)
            if simd_length_squared(sub) < UR_SQ_PLUS_ONE * (len1 * len1) {
                if len1 < minLen { // find most close point to camera (in z-direction distance)
                    minLen = len1
                    pickIdx = idx
                }
            }
            // 2. Outside ProbeRadius
            else {
                let cosine = len1 / simd_length(sub)
                if cosine > maxCos { // find most close point to probe radius
                    maxCos = cosine
                    pickIdxExt = idx
                }
            }
        }
        
        return pickIdx < 0 ? pickIdxExt : pickIdx
    }

    
    private func runFindSurfaceAsync( onSuccess successHandler: FindSurfaceSuccessHandler?, onFail failHandler: FindSurfaceFailHandler?, onEnd endHandler: FindSurfaceEndHandler? )
    {
        guard currentPointCount > 0,
              let frame = self.session.currentFrame else { return }
        
        let vertices = pointBuffer.assumingMemoryBound(to: simd_float3.self)
        
        let _paramMA = self.paramMA
        let _paramMD = self.paramMD
        let _paramLAT = self.paramLAT
        let _paramRAD = self.paramRAD
        
        let pixelSize = CGFloat( self.currentPixelRadius )
        let probeSize = CGFloat( max( 5.0, (self.currentPixelRadius * self.currentProbeRatio) ) )
        
        isFindSurfaceRunning = true
        findsurface_queue.async {
            let invViewMat = simd_inverse( self.renderer.getViewMatrixFromARFrame(frame) )
            let projMat    = self.renderer.getProjectionMatrixFromARFrame(frame)
            
            // Picking Ray Always Towards to Center of Screen -> NDC of Center of Screen is (0, 0)
            let rayDir: simd_float3 = self.renderer.NDC2RayDirection(NDCPoint: simd_make_float2(0.0, 0.0), inverseViewMatrix: invViewMat, projectionMatrix: projMat)
            let rayPos: simd_float3 = simd_make_float3( invViewMat.columns.3 )
            
            let unitRadius = self.renderer.screenLength2WorldLength(length: pixelSize, projectionMatrix: projMat)
            let probeRadius = self.renderer.screenLength2WorldLength(length: probeSize, projectionMatrix: projMat)
            let _findType:FS_FEATURE_TYPE = self.findType
            
            let index = self._pickPoint(rayDirection: rayDir, rayPosition: rayPos, vertices: vertices, count: self.currentPointCount, probeRadius)
            
            // Start FindSurface
            if index >= 0 {
                let seed_point = vertices[index]
                let distance = abs( simd_dot( rayDir, (seed_point - rayPos) ) )
                
                // Algorithm Setting
                self.fsRequestor.setPointDataDescription( measurementAccuracy: Float32(_paramMA), meanDistance: Float32(_paramMD) )
                self.fsRequestor.setSeedRegion( seedPointIndex: UInt32(index), regionRadius: Float32(unitRadius * distance) )
                self.fsRequestor.setRadialExpansionLevel( searchLevel: _paramRAD )
                self.fsRequestor.setLateralExtensionLevel( searchLevel: _paramLAT )
                // Buffer Description Setting
                self.fsRequestor.setPointBufferDescription( pointCount: UInt32(self.currentPointCount), pointStride: UInt32(MemoryLayout<simd_float3>.stride) )
                
                do {
                    if let result = try self.fsRequestor.requestFindSurface( findType: _findType, withPointData: vertices, requestInliers: true) {
                        if _findType == .FS_TYPE_CONE || _findType == .FS_TYPE_TORUS {
                            result.reinterpreteFeature()
                        }
                        
                        if let onSuccess = successHandler {
                            onSuccess( result, ExtraInformation(rayPosition: rayPos, rayDirection: rayDir, seedPoint: seed_point) )
                        }
                    }
                    else {
                        if let onFail = failHandler {
                            onFail(nil)
                        }
                    }
                }
                catch {
                    if let onFail = failHandler {
                        onFail(error)
                    }
                }
            }
            else {
                if let onFail = failHandler {
                    onFail( FsReqestError.RequestError(desc: "No picked points for seed region") )
                }
            }
            
            // Cleanup
            DispatchQueue.main.async { self.isFindSurfaceRunning = false }
            
            // After all task is done (either success or fail)
            if let onEnd = endHandler {
                onEnd()
            }
        }
    }
    
    // MARK: - Touch Event
    
    @objc func onPinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard !circleView.isHidden && mainActionButton.isEnabled else { return }
        
        if gesture.state == .began {
        } else if gesture.state == .changed {
            let velocity = Float(gesture.velocity);
            let factor: Float = 10;
            
            let MIN: Float = 32.0
            let MAX: Float = Float( self.view.bounds.width < self.view.bounds.height ? self.view.bounds.width : self.view.bounds.height )
            currentPixelRadius = simd_clamp( currentPixelRadius + (velocity * factor), MIN, MAX)
            moveCircleView()
        } else if gesture.state == .ended {
        } else {
        }
    }
    
    // MARK: - UI Event
    
    @IBAction func onClickMainActionButton(_ sender: Any) {
        guard !recording, recorded, currentPointCount > 0, !isFindSurfaceRunning else { return }
        
        // Lock Buttons
        _enableMainButtons(false)
        statusTextField.text = "Request FindSurface"
        
        // Run FindSurfaceWeb
        runFindSurfaceAsync(
            // If Succeed
            onSuccess: { (result, extra) -> Void in
                let vertices = self.pointBuffer.assumingMemoryBound(to: simd_float3.self)
                let isConvex = result.convexTest(withRayPosition: extra.rayPosition, andRayDirection: extra.rayDirection, andHitPoint: extra.seedPoint)
                
                // Get Inliers if Exists
                if let inliers = result.getInliers( fromPointBuffer: vertices, pointCount: self.currentPointCount) {
                    var torus_ext_param: simd_float4? = nil
                    if result.type == .FS_TYPE_TORUS {
                        torus_ext_param = RenderObjectFactory.getTorusExtraParam( withCenter: result.torusCenter, normal: result.torusNormal,
                                                                                  inliers: inliers.bufferFloat, count: UInt32(inliers.count), stride: UInt32(inliers.stride) )
                    }
                    
                    // Append Mesh with Inliers
                    DispatchQueue.main.async {
                        self.renderer.appendMesh(withFindSurfaceResult: result, andInliers: inliers.buffer, inliersCount: inliers.count, extParam: torus_ext_param, convexFlag: isConvex)
                        self.statusTextField.text = "Find a \(result.type.name) | RMS: \(String(format: "%g", result.rms))"
                        self.undoButton.isEnabled = true
                    }
                }
                else {
                    // Just Append Mesh
                    DispatchQueue.main.async {
                        self.renderer.appendMesh(withFindSurfaceResult: result, extParam: nil, convexFlag: isConvex)
                        self.statusTextField.text = "Find a \(result.type.name) | RMS: \(String(format: "%g", result.rms))"
                        self.undoButton.isEnabled = true
                    }
                }
            },
            // If Failed
            onFail: { (error) -> Void in
                DispatchQueue.main.async {
                    if let err = error { // Failed with Unexpected Error
                        self.statusTextField.text = "Request Error: \(err)"
                    }
                    else { // Just Not Found
                        self.statusTextField.text = "Not Found"
                    }
                }
            },
            // After all task is done (either succeed or failed)
            onEnd: { () -> Void in
                // Unlock Buttons
                DispatchQueue.main.async { self._enableMainButtons(true) }
            }
        )
    }
    
    @IBAction func onClickCaptureButton(_ sender: UIButton) {
        recording = !recording
        if recording {
            currentPointIndex = 0;
            currentPointCount = 0;
            renderer.clearPointCloud();
            
            captureButton.setImage(recordStopImage, for: .normal)
            resetMotionButton.isEnabled = false
            mainActionButton.isEnabled = false
            
            recorded = false
            clrButton.isEnabled = false
        }
        else {
            resetMotionButton.isEnabled = true
            captureButton.setImage(recordStartImage, for: .normal)
            
            if currentPointCount > 0 {
                recorded = true
                mainActionButton.isEnabled = true
                clrButton.isEnabled = true
                showCircleView(true)
            }
        }
    }
    
    @IBAction func onClickClearButton(_ sender: UIButton) {
        if !renderer.isMeshEmpty() { renderer.clearMeshList() }
        
        captureButton.setImage(recordStartImage, for: .normal)
        clrButton.isEnabled = false
        undoButton.isEnabled = false
        
        pointShowButton.setTitle("Hide", for: .normal)
        renderer.showPointcloud = true
        
        recorded = false
        showCircleView(false)
        
        statusTextField.text = nil
        pointCountLabel.text = "0"
    }
    
    @IBAction func onClickResetMotionTracking(_ sender: Any) {
        let alertController = UIAlertController(title: "Reset Motion Tracking", message: "You will lose your current session. Are you sure?", preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.runSession(withReset: true)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style:. cancel)
        
        alertController.addAction(restartAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func onClickConfigButton(_ sender: UIButton) {
        showConfigDialog()
    }
    
    @IBAction func onChangeType(_ sender: UISegmentedControl!) {
        switch sender.selectedSegmentIndex
        {
        case 0: findType = .FS_TYPE_PLANE
        case 1: findType = .FS_TYPE_SPHERE
        case 2: findType = .FS_TYPE_CYLINDER
        case 3: findType = .FS_TYPE_CONE
        case 4: findType = .FS_TYPE_TORUS
        default: return
        }
    }
    
    @IBAction func onChangeSmooth(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex
        {
        case 0: smoothDepth = false
        case 1: smoothDepth = true
        default: return
        }
    }
    
    @IBAction func onTogglePointViewButton(_ sender: UIButton!) {
        if recorded {
            if pointShowButton.title(for: .normal) == "Hide" {
                pointShowButton.setTitle("Show", for: .normal)
                renderer.showPointcloud = false
            }
            else {
                pointShowButton.setTitle("Hide", for: .normal)
                renderer.showPointcloud = true
            }
        }
    }
    
    @IBAction func onClickUndoButton(_ sender: UIButton!) {
        if !renderer.isMeshEmpty() {
            renderer.removeLatestMesh()
        }
        
        if renderer.isMeshEmpty() {
            sender.isEnabled = false
        }
    }
    
    @IBAction func onChangeProbeRatio(_ sender: Any) {
        currentProbeRatio = probeSlider.value
        moveCircleView()
    }
    
    @IBAction func onClickExportButton(_ sender: UIButton!) {
        guard recorded, currentPointCount > 0 else { return }
        let alertController = UIAlertController(title: "Export", message: "Are you sure?", preferredStyle: .alert)
        let exportAction = UIAlertAction(title: "Export", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.exportAccumulatedPoints()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style:. cancel)
        
        alertController.addAction(exportAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
}
