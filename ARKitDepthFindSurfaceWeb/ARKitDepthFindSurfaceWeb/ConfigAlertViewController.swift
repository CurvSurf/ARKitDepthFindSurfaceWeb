//
//  ConfigAlertViewController.swift
//  ARKitDepthFindSurfaceWeb
//
//  Copyright © 2021 CurvSurf. All rights reserved.
//


import Foundation
import UIKit

class ConfigAlertViewController : UIViewController
{
    @IBOutlet weak var maTextField: UITextField!
    @IBOutlet weak var mdTextField: UITextField!
    @IBOutlet weak var latSlider: UISlider!
    @IBOutlet weak var latLabel: UILabel!
    @IBOutlet weak var radSlider: UISlider!
    @IBOutlet weak var radLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    private func _syncSliderAndLabel(_ slider: UISlider, _ label: UILabel) {
        slider.setValue(slider.value.rounded(.down), animated: false)
        label.text = "\( Int( slider.value ) )"
    }
    
    @IBAction func onSlideLatExt(_ sender: UISlider) {
        _syncSliderAndLabel(sender, latLabel)
    }

    @IBAction func onSlideRadExt(_ sender: UISlider) {
        _syncSliderAndLabel(sender, radLabel)
    }
    
    // MARK: - Computed Properties
    
    var measurementAccuracy: Float {
        return toFloatFromTextField(maTextField)
    }
    
    var meanDistance: Float {
        return toFloatFromTextField(mdTextField)
    }
    
    var lateralExtension: UInt8 {
        return UInt8( latSlider.value )
    }
    
    var radialExpension: UInt8 {
        return UInt8( radSlider.value )
    }
    
    private func toFloatFromTextField(_ tf: UITextField) -> Float {
        guard let txt = tf.text,
              let ret = Float(txt) else { return 0.0 }
        return ret
    }
    
    private func markErrorTextField(textField tf: UITextField, mark flag: Bool) {
        if flag {
            tf.layer.borderWidth = 2.0
            tf.layer.borderColor = UIColor.red.cgColor
        }
        else {
            tf.layer.borderWidth = 0.0
            tf.layer.borderColor = UIColor.clear.cgColor
        }
    }
    
    func setInitialValue(_ ma: Float, _ md: Float, _ lat: UInt8, _ rad: UInt8 ) {
        maTextField.text = "\(ma)"
        mdTextField.text = "\(md)"
        latSlider.setValue(Float(min(lat, 10)), animated: false)
        latLabel.text = "\(min(lat, 10))"
        radSlider.setValue(Float(min(rad, 10)), animated: false)
        radLabel.text = "\(min(rad, 10))"
    }
    
    func enableViews(_ enable: Bool) {
        if let mat = maTextField { mat.isEnabled = enable }
        if let mdt = mdTextField { mdt.isEnabled = enable }
        if let lat = latSlider   { lat.isEnabled = enable }
        if let rad = radSlider   { rad.isEnabled = enable }
    }
    
    func focusToMeasurementAccuracy() {
        maTextField.becomeFirstResponder()
        markErrorTextField(textField: maTextField, mark: true)
    }
    
    func focusToMeanDistance() {
        mdTextField.becomeFirstResponder()
        markErrorTextField(textField: mdTextField, mark: true)
    }
    
    func resetTextFieldStatus() {
        markErrorTextField(textField: maTextField, mark: false)
        markErrorTextField(textField: mdTextField, mark: false)
    }
}
