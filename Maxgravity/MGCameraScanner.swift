import SwiftUI
import AVFoundation

struct MGCameraScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        var onScan: (String) -> Void
        var onError: (String) -> Void

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func scannerDidFindCode(_ code: String) {
            onScan(code)
        }

        func scannerDidFailWithError(_ message: String) {
            onError(message)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func scannerDidFindCode(_ code: String)
    func scannerDidFailWithError(_ message: String)
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var torchEnabled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = MGTheme.backgroundUIColor
        checkCameraPermissions()
    }

    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.delegate?.scannerDidFailWithError("Camera permission denied")
                    }
                }
            }
        case .denied, .restricted:
            delegate?.scannerDidFailWithError("Camera permission denied")
        @unknown default:
            delegate?.scannerDidFailWithError("Unknown camera permission status")
        }
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        self.captureSession = session

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.scannerDidFailWithError("No video capture device found")
            return
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.scannerDidFailWithError("Could not initialize video input: \(error.localizedDescription)")
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            delegate?.scannerDidFailWithError("Could not add video input to session")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            delegate?.scannerDidFailWithError("Could not add metadata output to session")
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        // Add Scanner Overlay Frame
        addScannerOverlay()

        // Run session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func addScannerOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = MGTheme.backgroundUIColor.withAlphaComponent(0.34)

        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(view.bounds)

        // Bounding box frame
        let width = view.bounds.width * 0.65
        let x = (view.bounds.width - width) / 2
        let y = (view.bounds.height - width) / 2
        let scanRect = CGRect(x: x, y: y, width: width, height: width)

        path.addRoundedRect(in: scanRect, cornerWidth: 24, cornerHeight: 24)
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer
        view.addSubview(overlayView)

        // Draw green focus frame corners
        let frameView = UIView(frame: scanRect)
        frameView.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        frameView.layer.borderWidth = 3
        frameView.layer.cornerRadius = 24
        view.addSubview(frameView)

        // Add Flashlight Toggle Button
        let flashButton = UIButton(type: .system)
        flashButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = MGTheme.backgroundUIColor.withAlphaComponent(0.58)
        flashButton.frame = CGRect(x: (view.bounds.width - 50) / 2, y: y + width + 30, width: 50, height: 50)
        flashButton.layer.cornerRadius = 25
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        view.addSubview(flashButton)
    }

    @objc private func toggleFlash() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            torchEnabled.toggle()
            device.torchMode = torchEnabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            torchEnabled = false
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            if let session = captureSession, session.isRunning {
                session.stopRunning()
            }
            delegate?.scannerDidFindCode(stringValue)
        }
    }
}
