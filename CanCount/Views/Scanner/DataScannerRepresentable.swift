import SwiftUI
import UIKit
import AVFoundation
import Vision
import VisionKit
import os

// MARK: - VisionKit DataScanner wrapper

/// Wraps `DataScannerViewController` for live EAN-13 / EAN-8 / UPC-E recognition.
/// Use only when `DataScannerViewController.isSupported && .isAvailable`;
/// otherwise fall back to `FallbackScannerView`.
@MainActor
struct DataScannerRepresentable: UIViewControllerRepresentable {
    /// When false, recognition is frozen (result card is up).
    var isActive: Bool
    var onScan: @MainActor @Sendable (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        scanner.view.backgroundColor = .black
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if isActive {
            if !controller.isScanning {
                try? controller.startScanning()
            }
        } else if controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: @MainActor @Sendable (String) -> Void

        init(onScan: @escaping @MainActor @Sendable (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}

// MARK: - AVFoundation fallback

/// Owns an `AVCaptureSession` off the main actor. `@unchecked Sendable` because all
/// session configuration and mutation is confined to `sessionQueue`, and the pause
/// flag is guarded by a lock.
nonisolated final class ScanCaptureSessionController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.cancount.scanner.session")
    private let onCode: @MainActor @Sendable (String) -> Void
    /// Touched only on `sessionQueue`.
    private var configured = false
    private let paused = OSAllocatedUnfairLock(initialState: false)

    init(onCode: @escaping @MainActor @Sendable (String) -> Void) {
        self.onCode = onCode
    }

    /// When true, recognized codes are dropped (the sheet has a result card up).
    var isPaused: Bool {
        get { paused.withLock { $0 } }
        set { paused.withLock { $0 = newValue } }
    }

    func start() {
        sessionQueue.async { [self] in
            configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)

        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused else { return }
        guard let code = metadataObjects
            .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
            .first
        else { return }

        // Debounce: pause ourselves immediately; the sheet unpauses when it
        // returns to the scanning phase.
        isPaused = true
        let deliver = onCode
        Task { @MainActor in
            deliver(code)
        }
    }
}

/// Backing view whose layer is an `AVCaptureVideoPreviewLayer`.
final class ScanCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// AVFoundation `AVCaptureMetadataOutput` fallback, used when VisionKit's
/// DataScanner is unsupported or unavailable on this device.
@MainActor
struct FallbackScannerView: UIViewRepresentable {
    /// When false, recognized codes are dropped (result card is up).
    var isActive: Bool
    var onScan: @MainActor @Sendable (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    @MainActor
    final class Coordinator {
        let controller: ScanCaptureSessionController

        init(onScan: @escaping @MainActor @Sendable (String) -> Void) {
            controller = ScanCaptureSessionController(onCode: onScan)
        }
    }

    func makeUIView(context: Context) -> ScanCameraPreviewView {
        let view = ScanCameraPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = context.coordinator.controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.controller.isPaused = !isActive
        context.coordinator.controller.start()
        return view
    }

    func updateUIView(_ uiView: ScanCameraPreviewView, context: Context) {
        context.coordinator.controller.isPaused = !isActive
    }

    static func dismantleUIView(_ uiView: ScanCameraPreviewView, coordinator: Coordinator) {
        coordinator.controller.stop()
    }
}
