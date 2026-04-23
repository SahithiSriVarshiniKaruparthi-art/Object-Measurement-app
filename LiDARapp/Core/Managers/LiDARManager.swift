//
//  LiDARManager.swift
//  LiDARapp
//  Manages LiDAR sensor detection and depth data capture using ARKit
//

import Foundation
import ARKit
import Combine

// MARK: - Constants
/// Configuration constants for LiDAR depth processing
private struct LiDARConstants {
    
    static let maxDepthRange: Float = 5.0
    static let minDepthRange: Float = 0.0
    static let surfaceThreshold: Float = 0.1
    static let neighborhoodRadius = 1
    static let flatSurfaceThreshold: Float = 0.1
    static let depthSampleRate = 1
}

// MARK: - LiDAR Manager
/// Manages LiDAR availability detection and depth data capture
class LiDARManager: NSObject, ObservableObject {
    
    @Published var isLiDARAvailable: Bool = false

    @Published var isSessionRunning: Bool = false

    @Published var currentDepthData: DepthData?

    private var arSession: ARSession?
    
    /// Configuration for the AR session
    private var configuration: ARWorldTrackingConfiguration?
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkLiDARAvailability()
    }
    
    // MARK: - LiDAR Detection
    /// Checks if the device supports LiDAR (scene depth)
    func checkLiDARAvailability() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        
        if isLiDARAvailable {
            print("[LiDARManager] LiDAR is available on this device")
        } else {
            print("[LiDARManager] LiDAR is NOT available on this device")
        }
    }
    
    // MARK: - Session Management
    /// Starts the AR session to begin capturing depth data
    func startSession() {
        guard isLiDARAvailable else {
            print("[LiDARManager] Cannot start session - LiDAR not available")
            return
        }
        
        if arSession == nil {
            arSession = ARSession()
            arSession?.delegate = self
        }
        
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        
        arSession?.run(config)
        isSessionRunning = true
        
        print("[LiDARManager] AR session started with LiDAR depth capture")
    }
    
    /// Pauses the AR session
    func pauseSession() {
        arSession?.pause()
        isSessionRunning = false
        print("[LiDARManager] AR session paused")
    }
    
    /// Stops and cleans up the AR session
    func stopSession() {
        arSession?.pause()
        arSession = nil
        isSessionRunning = false
        currentDepthData = nil
        print("[LiDARManager] AR session stopped")
    }
    
    // MARK: - Depth Data Capture
    /// Captures the current depth data from the AR session
    func captureDepthData() -> DepthData? {
        guard let frame = arSession?.currentFrame,
              let depthMap = frame.sceneDepth?.depthMap else {
            print("[LiDARManager] No depth data available in current frame")
            return nil
        }
        
        let depthData = convertDepthMap(depthMap, frame: frame)
        currentDepthData = depthData
        
        if let data = depthData {
            print("[LiDARManager] Captured depth data: \(data.points.count) points")
        }
        
        return depthData
    }
    
    // MARK: - Depth Map Conversion
    /// Converts ARKit's depth map (CVPixelBuffer) to our DepthData format
    private func convertDepthMap(
        _ depthMap: CVPixelBuffer,
        frame: ARFrame
    ) -> DepthData? {

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("[LiDARManager] Failed to get depth buffer base address")
            return nil
        }

        let depthWidth  = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Camera info
        let intrinsics = frame.camera.intrinsics
        let cameraTransform = frame.camera.transform
        let imageResolution = frame.camera.imageResolution

        // Scale factors
        let scaleX = Float(imageResolution.width)  / Float(depthWidth)
        let scaleY = Float(imageResolution.height) / Float(depthHeight)

        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        var points: [DepthPoint] = []
        let sampleRate = LiDARConstants.depthSampleRate

        for y in stride(from: 0, to: depthHeight, by: sampleRate) {
            for x in stride(from: 0, to: depthWidth, by: sampleRate) {

                let index = y * depthWidth + x
                let depth = depthPointer[index]

                // Skip invalid depth
                guard depth > LiDARConstants.minDepthRange && depth < LiDARConstants.maxDepthRange else { continue }


                // Map depth pixel → camera image pixel
                let imageX = Float(x) * scaleX
                let imageY = Float(y) * scaleY

                // Camera‑space projection (intrinsics applied)
                let cameraX = (imageX - cx) / fx * depth
                let cameraY = (imageY - cy) / fy * depth
                let cameraZ = depth

                let cameraPoint = simd_float4(
                    cameraX,
                    cameraY,
                    cameraZ,
                    1.0
                )

                // Camera space → World space (CRITICAL FIX)
                let worldPoint = cameraTransform * cameraPoint

                points.append(
                    DepthPoint(
                        x: worldPoint.x,
                        y: worldPoint.y,
                        z: worldPoint.z
                    )
                )
            }
        }

        return DepthData(
            points: points,
            width: depthWidth / sampleRate,
            height: depthHeight / sampleRate,
            capturedAt: Date()
        )
    }

    
    // MARK: - Measurement Helpers
    /// Gets the depth value at a specific screen point
    /// - Parameters:
    ///   - point: The screen coordinate (normalized 0-1)
    ///   - depthData: The depth data to query
    /// - Returns: The depth point at that location, or nil if not available
    func getDepthPoint(at point: CGPoint, in depthData: DepthData) -> DepthPoint? {
        let normalizedX = max(0, min(1, point.x))
        let normalizedY = max(0, min(1, point.y))
        
        let x = Int(normalizedX * CGFloat(depthData.width - 1))
        let y = Int(normalizedY * CGFloat(depthData.height - 1))
        
        print("[LiDARManager] Mapping tap (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y))) -> pixel (\(x), \(y))")
        
        // Get surrounding points for averaging (3x3 neighborhood)
        var neighborPoints: [DepthPoint] = []
        
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx
                let ny = y + dy
                
                if let point = depthData.point(at: nx, y: ny) {
                    neighborPoints.append(point)
                }
            }
        }
        
        guard !neighborPoints.isEmpty else {
            print("[LiDARManager] No depth points in neighborhood of (\(x), \(y))")
            return nil
        }
        
        // Calculate median depth 
        let depths = neighborPoints.map { $0.z }.sorted()
        let medianDepth = depths[depths.count / 2]
        
        // Filter points within surface threshold of median depth (same surface)
        let surfacePoints = neighborPoints.filter { abs($0.z - medianDepth) < LiDARConstants.surfaceThreshold }
        
        guard !surfacePoints.isEmpty else {
            print("[LiDARManager] No consistent surface found")
            return nil
        }
        
        // Average the surface points
        let avgX = surfacePoints.map { $0.x }.reduce(0, +) / Float(surfacePoints.count)
        let avgY = surfacePoints.map { $0.y }.reduce(0, +) / Float(surfacePoints.count)
        let avgZ = surfacePoints.map { $0.z }.reduce(0, +) / Float(surfacePoints.count)
        
        let depthPoint = DepthPoint(x: avgX, y: avgY, z: avgZ)
        
        print("[LiDARManager] Averaged \(surfacePoints.count) surface points")
        print("[LiDARManager] Depth point: x=\(String(format: "%.3f", depthPoint.x)), y=\(String(format: "%.3f", depthPoint.y)), z=\(String(format: "%.3f", depthPoint.z))m")
        
        return depthPoint
    }

    
    /// Calculates distance between two screen points using depth data
    /// - Parameters:
    ///   - point1: First screen point (normalized 0-1)
    ///   - point2: Second screen point (normalized 0-1)
    ///   - depthData: The depth data to use
    /// - Returns: Distance in meters, or nil if points don't have depth data
    func calculateDistance(from point1: CGPoint, to point2: CGPoint, using depthData: DepthData) -> Double? {
        guard let depthPoint1 = getDepthPoint(at: point1, in: depthData),
            let depthPoint2 = getDepthPoint(at: point2, in: depthData) else {
            print("[LiDARManager] Could not get depth points for measurement")
            return nil
        }
        
        print("[LiDARManager] Point 1: (\(String(format: "%.3f", depthPoint1.x)), \(String(format: "%.3f", depthPoint1.y)), \(String(format: "%.3f", depthPoint1.z)))")
        print("[LiDARManager] Point 2: (\(String(format: "%.3f", depthPoint2.x)), \(String(format: "%.3f", depthPoint2.y)), \(String(format: "%.3f", depthPoint2.z)))")
        
        // Calculate 3D Euclidean distance
        let dx = depthPoint2.x - depthPoint1.x
        let dy = depthPoint2.y - depthPoint1.y
        let dz = depthPoint2.z - depthPoint1.z
        
        let distance3D = sqrt(dx*dx + dy*dy + dz*dz)
        
        // For objects roughly at the same depth, use XY distance
        // This gives the physical distance across the surface
        let depthDiff = abs(dz)
        
        let distance: Float
        if depthDiff < LiDARConstants.flatSurfaceThreshold {  // Points are on roughly the same plane
            // Use 2D distance in XY plane (physical distance across surface)
            distance = sqrt(dx*dx + dy*dy)
            print("[LiDARManager] Using XY distance (flat surface): \(distance)m")
        } else {
            // Points at different depths, use 3D distance
            distance = distance3D
            print("[LiDARManager] Using 3D distance (depth difference: \(depthDiff)m): \(distance)m")
        }
        
        print("[LiDARManager] Calculated distance: \(distance) meters (\(String(format: "%.1f", distance * 39.37)) inches)")
        
        return Double(distance)
    }

    
    /// Calculates bounding box dimensions from four corner points
    /// - Parameters:
    ///   - topLeft: Top-left corner (normalized 0-1)
    ///   - topRight: Top-right corner (normalized 0-1)
    ///   - bottomLeft: Bottom-left corner (normalized 0-1)
    ///   - bottomRight: Bottom-right corner (normalized 0-1)
    ///   - depthData: The depth data to use
    /// - Returns: Tuple of (width, height) in meters, or nil if calculation fails
    func calculateBoundingBox(topLeft: CGPoint,
                             topRight: CGPoint,
                             bottomLeft: CGPoint,
                             bottomRight: CGPoint,
                             using depthData: DepthData) -> (width: Double, height: Double)? {
        
        // Get depth points for all corners
        guard let tlPoint = getDepthPoint(at: topLeft, in: depthData),
              let trPoint = getDepthPoint(at: topRight, in: depthData),
              let blPoint = getDepthPoint(at: bottomLeft, in: depthData),
              let brPoint = getDepthPoint(at: bottomRight, in: depthData) else {
            print("[LiDARManager] Could not get depth points for bounding box")
            return nil
        }
        
        // Calculate width (average of top and bottom edges)
        let topWidth = tlPoint.distance(to: trPoint)
        let bottomWidth = blPoint.distance(to: brPoint)
        let width = Double((topWidth + bottomWidth) / 2.0)
        
        // Calculate height (average of left and right edges)
        let leftHeight = tlPoint.distance(to: blPoint)
        let rightHeight = trPoint.distance(to: brPoint)
        let height = Double((leftHeight + rightHeight) / 2.0)
        
        print("[LiDARManager] Calculated bounding box: \(width)m × \(height)m")
        
        return (width: width, height: height)
    }
}

// MARK: - ARSession Delegate
extension LiDARManager: ARSessionDelegate {
    /// Called when AR session updates with new frame
    /// We can use this to continuously monitor depth data if needed
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
    }
    
    /// Called when AR session fails
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[LiDARManager] AR session failed: \(error.localizedDescription)")
        isSessionRunning = false
    }
    
    /// Called when AR session is interrupted (e.g., app goes to background)
    func sessionWasInterrupted(_ session: ARSession) {
        print("[LiDARManager] AR session was interrupted")
        isSessionRunning = false
    }
    
    /// Called when AR session interruption ends
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[LiDARManager] AR session interruption ended")
    }
}

