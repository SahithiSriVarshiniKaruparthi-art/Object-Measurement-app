//
//  CameraView.swift
//  LiDARapp
//
//  Created by LiDAR Team on 2026
//  Copyright © 2026 LiDAR Measurement App. All rights reserved.
//
//  Camera interface for capturing photos and videos with LiDAR data
//

import SwiftUI
import AVFoundation

// MARK: - Camera View
/// Main camera interface with capture controls
struct CameraView: View {
    // Access to our managers
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
        // Start LiDAR session if available
        //     lidarManager.startSession()
        // }
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
/// UIKit camera preview wrapped in SwiftUI
struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var isCapturing: Bool
    let lidarManager: LiDARManager
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.lidarManager = lidarManager
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
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

// MARK: - Camera View Controller Delegate
protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(_ image: UIImage, depthData: DepthData?)
    func didCaptureVideo(_ url: URL, depthData: DepthData?)
}

// MARK: - Camera View Controller
/// UIKit view controller that handles the actual camera functionality
class CameraViewController: UIViewController {
    
    weak var delegate: CameraViewControllerDelegate?
    var lidarManager: LiDARManager?
    
    // AVFoundation components
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // UI Elements
    private var captureButton: UIButton!
    private var switchModeButton: UIButton!
    private var closeButton: UIButton!
    
    // State
    private var isPhotoMode = true
    private var isRecording = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {

        // Stop AR session if running
        lidarManager?.stopSession()

        // Create capture session
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        
        // Get back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[LiDARManager] No camera available")
            return
        }
        
        do {
            // Add camera input
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            // Add photo output
            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput, captureSession?.canAddOutput(photoOutput) == true {
                captureSession?.addOutput(photoOutput)
            }

            // Create video output but DON'T add it yet
            videoOutput = AVCaptureMovieFileOutput()
            // We'll add/remove outputs when switching modes


            
            // Setup preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = view.bounds
            view.layer.addSublayer(previewLayer!)
            
            // Start session
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
            
            print("[CameraView] Camera setup complete")
            
        } catch {
            print("[LiDARManager] Error setting up camera: \(error.localizedDescription)")
        }
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
        captureSession?.stopRunning()
        lidarManager?.pauseSession()
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
        
        // Switch outputs
        captureSession?.beginConfiguration()
        
        if isPhotoMode {
            // Remove video, add photo
            if let videoOutput = videoOutput {
                captureSession?.removeOutput(videoOutput)
            }
            if let photoOutput = photoOutput, captureSession?.canAddOutput(photoOutput) == true {
                captureSession?.addOutput(photoOutput)
            }
            captureButton.backgroundColor = .white
        } else {
            // Remove photo, add video
            if let photoOutput = photoOutput {
                captureSession?.removeOutput(photoOutput)
            }
            if let videoOutput = videoOutput, captureSession?.canAddOutput(videoOutput) == true {
                captureSession?.addOutput(videoOutput)
            }
            captureButton.backgroundColor = .red
        }
        
        captureSession?.commitConfiguration()
    }

    
    // MARK: - Photo Capture
    private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        // PAUSE AR session during capture to avoid conflict
        lidarManager?.pauseSession()
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
        
        // Flash animation
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        view.addSubview(flashView)
        UIView.animate(withDuration: 0.2, animations: {
            flashView.alpha = 0
        }) { _ in
            flashView.removeFromSuperview()
        }
        
        print("[CameraView] Capturing photo...")
    }

    
    // MARK: - Video Recording
    private func startRecording() {
        guard let videoOutput = videoOutput else { return }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        videoOutput.startRecording(to: tempURL, recordingDelegate: self)
        
        isRecording = true
        captureButton.backgroundColor = .red
        captureButton.layer.borderColor = UIColor.red.cgColor
        
        print("[CameraView] Started recording...")
    }
    
    private func stopRecording() {
        videoOutput?.stopRecording()
        isRecording = false
        captureButton.backgroundColor = .white
        captureButton.layer.borderColor = UIColor.white.cgColor
        
        print("[LiDARManager] Stopped recording")
    }
}

// MARK: - Photo Capture Delegate
extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error = error {
                print("[LiDARManager] Error capturing photo: \(error.localizedDescription)")
                return
            }
            
            guard let imageData = photo.fileDataRepresentation(),
                let image = UIImage(data: imageData) else {
                print("[LiDARManager] Failed to convert photo to image")
                return
            }
            
            // NOW start AR session briefly to capture depth
            if lidarManager?.isLiDARAvailable == true {
                lidarManager?.startSession()
                // Wait a moment for AR to initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    let depthData = self?.lidarManager?.captureDepthData()
                    self?.lidarManager?.stopSession()
                    self?.delegate?.didCapturePhoto(image, depthData: depthData)
                }
            } else {
                delegate?.didCapturePhoto(image, depthData: nil)
            }
            
            print("[LiDARManager] Photo captured successfully")
        }
}

// MARK: - Video Capture Delegate
extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("[LiDARManager] Error recording video: \(error.localizedDescription)")
            return
        }
        
        // Capture depth data at the end of recording
        let depthData = lidarManager?.captureDepthData()
        
        // Notify delegate
        delegate?.didCaptureVideo(outputFileURL, depthData: depthData)
        
        print("[LiDARManager] Video recorded successfully")
    }
}

// MARK: - Preview
#Preview {
    CameraView()
}

