//
//  MeasurementView.swift
//  LiDARapp
//
//  Interactive view for measuring distances and bounding boxes on photos
//

import SwiftUI

// MARK: - Measurement View
/// Interactive overlay for taking measurements on photos
struct MeasurementView: View {
    let mediaItem: MediaItem
    let image: UIImage
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var lidarManager = LiDARManager()
    
    // Measurement state
    @State private var measurementMode: MeasurementMode = .distance
    @State private var selectedPoints: [CGPoint] = []
    @State private var showResult = false
    @State private var measurementResult: String = ""
    @State private var isMeasuring = false
    
    // Depth data
    @State private var depthData: DepthData?
    
    var body: some View {
    NavigationView {
        ZStack {
            // LAYER 1: Image with tap detection (BOTTOM)
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.blue.opacity(0.1))  // Debug: see the tappable area
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                print("[LiDARManager] Tap at: \(value.location)")
                                handleTap(at: value.location, in: geometry.size)
                            }
                    )
                    .overlay(
                        MeasurementOverlay(
                            points: selectedPoints,
                            mode: measurementMode,
                            imageSize: geometry.size
                        )
                        .allowsHitTesting(false)  // Overlay shouldn't block taps
                    )
            }
            
            // LAYER 2: Controls (TOP) - with specific hit testing
            VStack {
                HStack {
                    Picker("Mode", selection: $measurementMode) {
                        Text("Distance").tag(MeasurementMode.distance)
                        Text("Box").tag(MeasurementMode.boundingBox)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                    .onChange(of: measurementMode) { newValue in
                        print("[LiDARManager] Mode changed to: \(newValue)")
                        resetMeasurement()
                    }
                    
                    Spacer()
                    
                    if !selectedPoints.isEmpty {
                        Button(action: resetMeasurement) {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                
                Spacer()
                    .allowsHitTesting(false)  // Spacer shouldn't block taps
                
                InstructionsView(
                    mode: measurementMode,
                    pointsCount: selectedPoints.count
                )
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding()
            }
            
            // LAYER 3: Result overlay (if showing)
            if showResult {
                ResultOverlay(
                    result: measurementResult,
                    onSave: saveMeasurement,
                    onDismiss: {
                        showResult = false
                        resetMeasurement()
                    }
                )
            }
        }
        .navigationTitle("Measure")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    print("[LiDARManager] Cancel tapped")
                    dismiss()
                }
            }
        }
        .onAppear {
            print("[LiDARManager] MeasurementView appeared!")
            loadDepthData()
        }
    }
}

    
    // MARK: - Load Depth Data
    /// Loads the depth data for this media item
    private func loadDepthData() {
        depthData = DataStore.shared.loadDepthData(for: mediaItem)
        if depthData != nil {
            print("[LiDARManager] Loaded depth data for measurement")
        } else {
            print("[LiDARManager] No depth data available")
        }
    }
    
    // MARK: - Handle Tap
    /// Handles user taps to add measurement points
    private func handleTap(at location: CGPoint, in size: CGSize) {
        print("[LiDARManager] Tap detected at: \(location) in size: \(size)")
        guard !isMeasuring else { return }
        
        // Normalize coordinates to 0-1 range
        let normalizedPoint = CGPoint(
            x: location.x / size.width,
            y: location.y / size.height
        )
        
        print("[MeasurementView] Normalized: (\(String(format: "%.3f", normalizedPoint.x)), \(String(format: "%.3f", normalizedPoint.y)))")
        
        selectedPoints.append(normalizedPoint)
        
        // Check if we have enough points to calculate
        let requiredPoints = measurementMode == .distance ? 2 : 4
        
        if selectedPoints.count == requiredPoints {
            calculateMeasurement()
        }
    }

    
    // MARK: - Calculate Measurement
    /// Calculates the measurement based on selected points
    private func calculateMeasurement() {
        guard let depthData = depthData else {
            measurementResult = "❌ No depth data available"
            showResult = true
            return
        }
        
        isMeasuring = true
        
        // Small delay to show the last point being drawn
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            switch measurementMode {
            case .distance:
                calculateDistance(depthData: depthData)
            case .boundingBox:
                calculateBoundingBox(depthData: depthData)
            }
            
            isMeasuring = false
            showResult = true
        }
    }

    
    /// Calculates distance between two points
    private func calculateDistance(depthData: DepthData) {
        guard selectedPoints.count == 2 else { return }
        
        if let distance = lidarManager.calculateDistance(
            from: selectedPoints[0],
            to: selectedPoints[1],
            using: depthData
        ) {
            measurementResult = String(format: "Distance: %.2f meters\n(%.0f cm)", distance, distance * 100)
        } else {
            measurementResult = "❌ Could not calculate distance"
        }
    }
    
    /// Calculates bounding box dimensions
    private func calculateBoundingBox(depthData: DepthData) {
        guard selectedPoints.count == 4 else { return }
        
        if let dimensions = lidarManager.calculateBoundingBox(
            topLeft: selectedPoints[0],
            topRight: selectedPoints[1],
            bottomLeft: selectedPoints[3],
            bottomRight: selectedPoints[2],
            using: depthData
        ) {
            measurementResult = String(format: "Width: %.2f m (%.0f cm)\nHeight: %.2f m (%.0f cm)",
                                      dimensions.width, dimensions.width * 100,
                                      dimensions.height, dimensions.height * 100)
        } else {
            measurementResult = "❌ Could not calculate dimensions"
        }
    }
    
    // MARK: - Save Measurement
    /// Saves the measurement to the media item
    private func saveMeasurement() {
        guard let depthData = depthData else { return }
        
        let measurement: Measurement
        
        switch measurementMode {
        case .distance:
            guard selectedPoints.count == 2,
                  let distance = lidarManager.calculateDistance(
                    from: selectedPoints[0],
                    to: selectedPoints[1],
                    using: depthData
                  ) else { return }
            
            measurement = Measurement(
                type: .distance,
                value: distance,
                screenPoints: selectedPoints
            )
            
        case .boundingBox:
            guard selectedPoints.count == 4,
                  let dimensions = lidarManager.calculateBoundingBox(
                    topLeft: selectedPoints[0],
                    topRight: selectedPoints[1],
                    bottomLeft: selectedPoints[3],
                    bottomRight: selectedPoints[2],
                    using: depthData
                  ) else { return }
            
            measurement = Measurement(
                type: .boundingBox,
                value: dimensions.width,
                secondaryValue: dimensions.height,
                screenPoints: selectedPoints
            )
        }
        
        // Save to data store
        DataStore.shared.addMeasurement(measurement, to: mediaItem)
        
        print("[LiDARManager] Measurement saved: \(measurement.description)")

        // Auto-dismiss after successful save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
    
    // MARK: - Reset
    /// Resets the current measurement
    private func resetMeasurement() {
        selectedPoints.removeAll()
        showResult = false
        measurementResult = ""
    }
}

// MARK: - Measurement Mode
/// Types of measurements available
enum MeasurementMode {
    case distance      // Point-to-point distance
    case boundingBox   // Width and height of a box
}

// MARK: - Measurement Overlay
/// Draws the measurement points and lines on the image
struct MeasurementOverlay: View {
    let points: [CGPoint]
    let mode: MeasurementMode
    let imageSize: CGSize
    
    var body: some View {
        Canvas { context, size in
            // Convert normalized points to actual coordinates
            let actualPoints = points.map { point in
                CGPoint(
                    x: point.x * imageSize.width,
                    y: point.y * imageSize.height
                )
            }
            
            // Draw based on mode
            switch mode {
            case .distance:
                drawDistanceMode(context: context, points: actualPoints)
            case .boundingBox:
                drawBoundingBoxMode(context: context, points: actualPoints)
            }
        }
    }
    
    /// Draws distance measurement (line between two points)
    private func drawDistanceMode(context: GraphicsContext, points: [CGPoint]) {
        // Draw points
        for point in points {
            let circle = Circle()
                .path(in: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            context.fill(circle, with: .color(.blue))
            context.stroke(circle, with: .color(.white), lineWidth: 2)
        }
        
        // Draw line between points
        if points.count == 2 {
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            context.stroke(path, with: .color(.blue), lineWidth: 3)
        }
    }
    
    /// Draws bounding box measurement (rectangle with four corners)
    private func drawBoundingBoxMode(context: GraphicsContext, points: [CGPoint]) {
        // Draw points
        for point in points {
            let circle = Circle()
                .path(in: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            context.fill(circle, with: .color(.green))
            context.stroke(circle, with: .color(.white), lineWidth: 2)
        }
        
        // Draw box if we have all 4 points
        if points.count == 4 {
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.addLine(to: points[3])
            path.closeSubpath()
            
            context.stroke(path, with: .color(.green), lineWidth: 3)
            context.fill(path, with: .color(.green.opacity(0.2)))
        } else if points.count > 1 {
            // Draw lines between existing points
            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
        }
    }
}

// MARK: - Instructions View
/// Shows instructions for the current measurement mode
struct InstructionsView: View {
    let mode: MeasurementMode
    let pointsCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: mode == .distance ? "ruler" : "square.dashed")
                    .foregroundColor(.white)
                
                Text(mode == .distance ? "Distance Mode" : "Bounding Box Mode")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Text(instructionText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private var instructionText: String {
        switch mode {
        case .distance:
            if pointsCount == 0 {
                return "Tap to select the first point"
            } else if pointsCount == 1 {
                return "Tap to select the second point"
            } else {
                return "Calculating distance..."
            }
            
        case .boundingBox:
            switch pointsCount {
            case 0:
                return "Tap to select top-left corner"
            case 1:
                return "Tap to select top-right corner"
            case 2:
                return "Tap to select bottom-right corner"
            case 3:
                return "Tap to select bottom-left corner"
            default:
                return "Calculating dimensions..."
            }
        }
    }
}

// MARK: - Result Overlay
/// Shows the measurement result with save/dismiss options
struct ResultOverlay: View {
    let result: String
    let onSave: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 16) {
                Text("Measurement Result")
                    .font(.headline)
                
                Text(result)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Retry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .cornerRadius(12)
                    }
                    
                    Button(action: onSave) {
                        Text("Save")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(24)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .background(Color.black.opacity(0.5))
    }
}

// MARK: - Preview
#Preview {
    if let image = UIImage(systemName: "photo") {
        MeasurementView(
            mediaItem: MediaItem(fileName: "test.jpg", type: .photo, hasLiDARData: true),
            image: image
        )
    }
}

