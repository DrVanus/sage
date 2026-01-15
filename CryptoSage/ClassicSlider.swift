import SwiftUI
import UIKit

// UIKit slider subclass with custom appearance
class ClassicUISlider: UISlider {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearance()
    }
    
    private func setupAppearance() {
        // Remove the default shadow lines on dark backgrounds by setting a transparent track image
        let clearImage = UIImage()
        setMinimumTrackImage(clearImage, for: .normal)
        setMaximumTrackImage(clearImage, for: .normal)
        
        // Create a custom track layer with a single baseline line
        let trackLayer = CALayer()
        trackLayer.backgroundColor = UIColor.systemGray5.cgColor
        trackLayer.frame = CGRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 2)
        trackLayer.cornerRadius = 1
        layer.insertSublayer(trackLayer, at: 0)
        
        // Tint color for the minimum track (left side)
        minimumTrackTintColor = UIColor.systemBlue
        maximumTrackTintColor = UIColor.clear
        
        // Thumb styling
        thumbTintColor = UIColor.systemBlue
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update track layer frame if needed (since bounds can change)
        if let trackLayer = layer.sublayers?.first {
            trackLayer.frame = CGRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 2)
            trackLayer.cornerRadius = 1
        }
    }
}

// UIViewRepresentable wrapper for SwiftUI
struct ClassicSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    
    func makeUIView(context: Context) -> ClassicUISlider {
        let slider = ClassicUISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return slider
    }
    
    func updateUIView(_ uiView: ClassicUISlider, context: Context) {
        if Float(value) != uiView.value {
            uiView.value = Float(value)
        }
        uiView.minimumValue = Float(range.lowerBound)
        uiView.maximumValue = Float(range.upperBound)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ClassicSlider
        
        init(_ parent: ClassicSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
}
