//
//  CameraView.swift
//  Camera interface for capturing photos and videos with LiDAR data
//  Now uses ARKit for both camera and depth capture for better accuracy
//

import SwiftUI
import ARKit
import AVFoundation

// MARK: - Camera View
/// Main camera interface with capture controls
struct CameraView: View {
    // Access to the managers
    @StateObject private var lidarManager = LiDARManager()
    @ObservedObject var dataStore = DataStore.shared
    
    // Camera state
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isCapturing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // LiDAR Status Indicator
                LiDARStatusView(isAvailable: lidarManager.isLiDARAvailable)
                
                Spacer()
                
                // Camera Preview or Placeholder
                if showCamera {
                    CameraPreviewView(
                        capturedImage: $capturedImage,
                        isCapturing: $isCapturing,
                        lidarManager: lidarManager
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Placeholder when camera is not active
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("Tap 'Open Camera' to start")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Spacer()
                
                // Camera Controls
                VStack(spacing: 15) {
                    if !showCamera {
                        // Open Camera Button
                        Button(action: openCamera) {
                            Label("Open Camera", systemImage: "camera")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    
                    // Info text
                    if lidarManager.isLiDARAvailable {
                        Text("✓ LiDAR enabled - depth data will be captured")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("⚠️ LiDAR not available on this device")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Camera")
            .onAppear {
                // Check LiDAR availability when view appears
                lidarManager.checkLiDARAvailability()
            }
        }
    }
    
    private func openCamera() {
        showCamera = true
    }
}

// MARK: - LiDAR Status View
/// Shows whether LiDAR is available on the device
struct LiDARStatusView: View {
    let isAvailable: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isAvailable ? .green : .red)
            
            Text(isAvailable ? "LiDAR Available" : "LiDAR Not Available")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isAvailable ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(20)
        .padding(.top)
    }
}

// MARK: - Camera Preview View
/// ARKit camera preview wrapped in SwiftUI
struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var isCapturing: Bool
    let lidarManager: LiDARManager
    
    func makeUIViewController(context: Context) -> ARCameraViewController {
        let controller = ARCameraViewController()
        controller.delegate = context.coordinator
        controller.lidarManager = lidarManager
        return controller
    }
    
    func updateUIViewController(_ uiViewController: ARCameraViewController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARCameraViewControllerDelegate {
        let parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
        
        func didCapturePhoto(_ image: UIImage, depthData: DepthData?) {
            parent.capturedImage = image
            parent.isCapturing = false
            
            // Save to data store
            DataStore.shared.addMediaItem(
                image: image,
                type: .photo,
                depthData: depthData
            )
        }
        
        func didCaptureVideo(_ url: URL, depthData: DepthData?) {
            parent.isCapturing = false
            
            // Save to data store
            DataStore.shared.addMediaItem(
                videoURL: url,
                type: .video,
                depthData: depthData
            )
        }
    }
}

// MARK: - AR Camera View Controller Delegate
protocol ARCameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ image: UIImage, depthData: DepthData?)
    func didCaptureVideo(_ url: URL, depthData: DepthData?)
}

// MARK: - AR Camera View Controller
/// UIKit view controller that uses ARKit for both camera and depth capture
class ARCameraViewController: UIViewController {
    
    weak var delegate: ARCameraViewControllerDelegate?
    var lidarManager: LiDARManager?
    
    // ARKit components
    private var arSession: ARSession!
    private var arView: ARSCNView!
    
    // Video recording
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var recordingStartTime: CMTime?
    private var videoURL: URL?
    private var depthDataBuffer: [DepthData] = []
    
    // UI Elements
    private var captureButton: UIButton!
    private var switchModeButton: UIButton!
    private var closeButton: UIButton!
    private var recordingIndicator: UIView!
    
    // State
    private var isPhotoMode = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupUI()
        startARSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()
    }
    
    // MARK: - AR Setup
    private func setupARView() {
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.session.delegate = self
        view.addSubview(arView)
        
        arSession = arView.session
        
        print("[ARCameraView] ARView setup complete")
    }
    
    private func startARSession() {
        let configuration = ARWorldTrackingConfiguration()
        
        // Enable scene depth for LiDAR
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = .sceneDepth
            print("[ARCameraView] LiDAR depth enabled")
        } else {
            print("[ARCameraView] LiDAR not available on this device")
        }
        
        arSession.run(configuration)
        print("[ARCameraView] AR session started")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Close button (top left)
        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 25
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        // Recording indicator (top center)
        recordingIndicator = UIView()
        recordingIndicator.backgroundColor = .red
        recordingIndicator.layer.cornerRadius = 8
        recordingIndicator.isHidden = true
        recordingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordingIndicator)
        
        // Add pulsing animation to recording indicator
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.duration = 1.0
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 0.3
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        recordingIndicator.layer.add(pulseAnimation, forKey: "pulse")
        
        // Capture button (bottom center)
        captureButton = UIButton(type: .system)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureButton)
        
        // Switch mode button (bottom right)
        switchModeButton = UIButton(type: .system)
        switchModeButton.setTitle("📷 Photo", for: .normal)
        switchModeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        switchModeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        switchModeButton.layer.cornerRadius = 20
        switchModeButton.addTarget(self, action: #selector(switchModeTapped), for: .touchUpInside)
        switchModeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(switchModeButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 50),
            closeButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Recording indicator
            recordingIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            recordingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordingIndicator.widthAnchor.constraint(equalToConstant: 16),
            recordingIndicator.heightAnchor.constraint(equalToConstant: 16),
            
            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Switch mode button
            switchModeButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            switchModeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            switchModeButton.widthAnchor.constraint(equalToConstant: 100),
            switchModeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        if isRecording {
            stopRecording()
        }
        arSession.pause()
        dismiss(animated: true)
    }
    
    @objc private func captureTapped() {
        if isPhotoMode {
            capturePhoto()
        } else {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
    }
    
    @objc private func switchModeTapped() {
        isPhotoMode.toggle()
        let title = isPhotoMode ? "📷 Photo" : "🎥 Video"
        switchModeButton.setTitle(title, for: .normal)
        captureButton.backgroundColor = isPhotoMode ? .white : .red
    }
    
    // MARK: - Photo Capture
    private func capturePhoto() {
        guard let frame = arSession.currentFrame else {
            print("[ARCameraView] No AR frame available")
            return
        }
        
        // Capture the camera image
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("[ARCameraView] Failed to create CGImage")
            return
        }
        
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // Capture depth data
        let depthData = captureDepthDataFromFrame(frame)
        
        // Flash animation
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        view.addSubview(flashView)
        UIView.animate(withDuration: 0.2, animations: {
            flashView.alpha = 0
        }) { _ in
            flashView.removeFromSuperview()
        }
        
        // Notify delegate
        delegate?.didCapturePhoto(image, depthData: depthData)
        
        print("[ARCameraView] Photo captured with depth data")
    }
    
    // MARK: - Video Recording
    private func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        videoURL = tempURL
        depthDataBuffer.removeAll()
        
        // Setup video writer
        do {
            videoWriter = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1440
            ]
            
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1440
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if let input = videoWriterInput, videoWriter!.canAdd(input) {
                videoWriter!.add(input)
            }
            
            videoWriter!.startWriting()
            recordingStartTime = nil
            isRecording = true
            
            // Update UI
            captureButton.backgroundColor = .red
            captureButton.layer.borderColor = UIColor.red.cgColor
            recordingIndicator.isHidden = false
            
            print("[ARCameraView] Started recording")
            
        } catch {
            print("[ARCameraView] Failed to setup video writer: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        captureButton.backgroundColor = .white
        captureButton.layer.borderColor = UIColor.white.cgColor
        recordingIndicator.isHidden = true
        
        videoWriterInput?.markAsFinished()
        
        videoWriter?.finishWriting { [weak self] in
            guard let self = self, let url = self.videoURL else { return }
            
            // Calculate average depth data from buffer
            let averageDepthData = self.calculateAverageDepthData()
            
            DispatchQueue.main.async {
                self.delegate?.didCaptureVideo(url, depthData: averageDepthData)
                print("[ARCameraView] Video saved with depth data")
            }
            
            self.videoWriter = nil
            self.videoWriterInput = nil
            self.pixelBufferAdaptor = nil
            self.depthDataBuffer.removeAll()
        }
    }
    
    // MARK: - Depth Capture Helpers
    private func captureDepthDataFromFrame(_ frame: ARFrame) -> DepthData? {
        guard let depthMap = frame.sceneDepth?.depthMap else {
            print("[ARCameraView] No depth data in frame")
            return nil
        }
        
        return convertDepthMap(depthMap, frame: frame)
    }
    
    private func convertDepthMap(_ depthMap: CVPixelBuffer, frame: ARFrame) -> DepthData? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        let intrinsics = frame.camera.intrinsics
        let imageResolution = frame.camera.imageResolution
        
        let scaleX = Float(imageResolution.width) / Float(depthWidth)
        let scaleY = Float(imageResolution.height) / Float(depthHeight)
        
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]
        
        var points: [DepthPoint] = []
        let sampleRate = 1
        
        print("[CameraView] Converting depth map: \(depthWidth)x\(depthHeight)")
        print("[CameraView] Camera intrinsics: fx=\(fx), fy=\(fy), cx=\(cx), cy=\(cy)")
        
        for y in stride(from: 0, to: depthHeight, by: sampleRate) {
            for x in stride(from: 0, to: depthWidth, by: sampleRate) {
                let index = y * depthWidth + x
                let depth = depthPointer[index]
                
                guard depth > 0.0 && depth < 5.0 else { continue }
                
                // Map depth pixel to image pixel coordinates
                let imageX = Float(x) * scaleX
                let imageY = Float(y) * scaleY
                
                // Convert to camera coordinates (3D point relative to camera)
                // This is the correct coordinate system for photo measurements
                let cameraX = (imageX - cx) / fx * depth
                let cameraY = (imageY - cy) / fy * depth
                let cameraZ = depth
                
                // Store CAMERA coordinates (not world coordinates)
                // For photo measurements, we want coordinates relative to the camera
                // that took the photo, not world space coordinates
                points.append(DepthPoint(
                    x: cameraX,
                    y: cameraY,
                    z: cameraZ,
                    pixelX: x,
                    pixelY: y
                ))
            }
        }
        
        print("[CameraView] Converted \(points.count) depth points")
        
        // Create camera intrinsics object
        let cameraIntrinsics = CameraIntrinsics(from: intrinsics)
        
        return DepthData(
            points: points,
            width: depthWidth / sampleRate,
            height: depthHeight / sampleRate,
            cameraIntrinsics: cameraIntrinsics,
            imageResolution: CGSize(width: imageResolution.width, height: imageResolution.height),
            depthResolution: CGSize(width: depthWidth, height: depthHeight),
            capturedAt: Date()
        )
    }
    
    private func calculateAverageDepthData() -> DepthData? {
        guard !depthDataBuffer.isEmpty else { return nil }
        
        // Return the most recent depth data (or could average multiple frames)
        return depthDataBuffer.last
    }
}

// MARK: - ARSession Delegate
extension ARCameraViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Handle video recording
        if isRecording, let videoWriterInput = videoWriterInput, videoWriterInput.isReadyForMoreMediaData {
            let pixelBuffer = frame.capturedImage
            let timestamp = frame.timestamp
            
            if recordingStartTime == nil {
                recordingStartTime = CMTime(seconds: timestamp, preferredTimescale: 600)
                videoWriter?.startSession(atSourceTime: recordingStartTime!)
            }
            
            let presentationTime = CMTime(seconds: timestamp, preferredTimescale: 600)
            
            // Convert and append pixel buffer
            if let convertedBuffer = convertPixelBuffer(pixelBuffer) {
                pixelBufferAdaptor?.append(convertedBuffer, withPresentationTime: presentationTime)
            }
            
            // Capture depth data periodically (every 10 frames to reduce memory)
            if depthDataBuffer.count < 100 {
                if let depthData = captureDepthDataFromFrame(frame) {
                    depthDataBuffer.append(depthData)
                }
            }
        }
    }
    
    private func convertPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        var outputBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1440
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1440, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &outputBuffer)
        
        if let output = outputBuffer {
            context.render(ciImage, to: output)
        }
        
        return outputBuffer
    }
}

// MARK: - Preview
#Preview {
    CameraView()
}

