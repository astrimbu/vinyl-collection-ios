import SwiftUI
import AVFoundation
import UIKit

struct BarcodeScannerView: View {
    @Binding var scannedBarcodes: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            BarcodeScannerRepresentable(scannedBarcodes: $scannedBarcodes)
                .navigationTitle("Scan Barcodes")
                .navigationBarItems(
                    trailing: Button("Done") {
                        dismiss()
                    }
                )
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedBarcodes: [String]
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let viewController = BarcodeScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, BarcodeScannerViewControllerDelegate {
        let parent: BarcodeScannerRepresentable
        
        init(_ parent: BarcodeScannerRepresentable) {
            self.parent = parent
        }
        
        func didScanBarcode(_ barcode: String) {
            if !parent.scannedBarcodes.contains(barcode) {
                parent.scannedBarcodes.append(barcode)
            }
        }
    }
}

protocol BarcodeScannerViewControllerDelegate: AnyObject {
    func didScanBarcode(_ barcode: String)
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeScannerViewControllerDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var highlightView: UIView?
    private var scannedBarcodes = Set<String>() // Keep track of scanned barcodes to avoid duplicates
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        feedbackGenerator.prepare() // Prepare the feedback generator
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let captureSession = captureSession, !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let captureSession = captureSession, captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    private func setupCaptureSession() {
        let captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce] // Common barcode types for vinyl records
            }
            
            setupPreviewLayer(with: captureSession)
            setupHighlightView()
            
            self.captureSession = captureSession
            
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
            return
        }
    }
    
    private func setupPreviewLayer(with captureSession: AVCaptureSession) {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }
    
    private func setupHighlightView() {
        let highlightView = UIView()
        highlightView.layer.borderColor = UIColor.green.cgColor
        highlightView.layer.borderWidth = 3
        highlightView.isHidden = true
        view.addSubview(highlightView)
        self.highlightView = highlightView
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            
            // Only process if this is a new barcode
            if !scannedBarcodes.contains(stringValue) {
                scannedBarcodes.insert(stringValue)
                
                // Provide haptic feedback
                feedbackGenerator.notificationOccurred(.success)
                
                // Convert barcode coordinates to view coordinates
                if let barcodeObject = previewLayer?.transformedMetadataObject(for: metadataObject) {
                    highlightView?.frame = barcodeObject.bounds
                    highlightView?.isHidden = false
                    
                    // Hide highlight view after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.highlightView?.isHidden = true
                    }
                }
                
                // Notify delegate of scanned barcode
                delegate?.didScanBarcode(stringValue)
            }
        }
    }
} 