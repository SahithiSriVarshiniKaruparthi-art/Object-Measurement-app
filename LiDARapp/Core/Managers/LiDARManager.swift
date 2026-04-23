//
//  LiDARManager.swift
//
//  Utility class for LiDAR detection and measurement calculations
//  Note: AR session management is now handled by ARCameraViewController
//

import Foundation
import ARKit
import Combine

// MARK: - Constants
/// Configuration constants for LiDAR depth processing
struct LiDARConstants {
    static let maxDepthRange: Float = 5.0
    static let minDepthRange: Float = 0.0
    static let surfaceThreshold: Float = 0.1
    static let neighborhoodRadius = 1
    static let flatSurfaceThreshold: Float = 0.1
    static let depthSampleRate = 1
}

// MARK: - LiDAR Manager
/// Utility class for LiDAR availability detection and measurement calculations
/// AR session management is handled by ARCameraViewController
class LiDARManager: ObservableObject {
    
    @Published var isLiDARAvailable: Bool = false
    
    // MARK: - Initialization
    init() {
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

    
    // MARK: - Measurement Helpers
    /// Gets the depth point at a specific normalized screen coordinate
    /// This properly handles the coordinate transformation pipeline:
    /// Screen tap (normalized) → Image pixel → Depth map pixel → 3D world point
    /// - Parameters:
    ///   - normalizedPoint: The screen coordinate (normalized 0-1 relative to displayed image)
    ///   - depthData: The depth data to query
    ///   - imageSize: The actual displayed image size (accounting for scaling/letterboxing)
    /// - Returns: The depth point at that location, or nil if not available
    func getDepthPoint(at normalizedPoint: CGPoint, in depthData: DepthData, imageSize: CGSize) -> DepthPoint? {
        // Clamp normalized coordinates to valid range
        let normalizedX = max(0, min(1, normalizedPoint.x))
        let normalizedY = max(0, min(1, normalizedPoint.y))
        
        print("[LiDARManager] === Starting coordinate transformation ===")
        print("[LiDARManager] Input: Normalized screen point (\(String(format: "%.3f", normalizedX)), \(String(format: "%.3f", normalizedY)))")
        
        // Step 1: Convert normalized coordinates to image pixel coordinates
        // The normalized point is relative to the displayed image bounds
        let imagePixelX = Float(normalizedX) * Float(depthData.imageResolution.width)
        let imagePixelY = Float(normalizedY) * Float(depthData.imageResolution.height)
        
        print("[LiDARManager] Step 1: Image pixel (\(String(format: "%.1f", imagePixelX)), \(String(format: "%.1f", imagePixelY))) in \(Int(depthData.imageResolution.width))x\(Int(depthData.imageResolution.height))")
        
        // Step 2: Find the closest depth point using the new method
        // This handles the mapping from image space to depth space internally
        guard let closestPoint = depthData.findClosestPoint(toImagePixel: imagePixelX, imageY: imagePixelY, searchRadius: 3) else {
            print("[LiDARManager] ❌ No depth point found near image pixel (\(String(format: "%.1f", imagePixelX)), \(String(format: "%.1f", imagePixelY)))")
            return nil
        }
        
        print("[LiDARManager] Step 2: Found depth point at depth pixel (\(closestPoint.pixelX), \(closestPoint.pixelY))")
        
        // Step 3: Get neighborhood points for surface averaging
        var neighborPoints: [DepthPoint] = []
        let radius = 2
        
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = closestPoint.pixelX + dx
                let ny = closestPoint.pixelY + dy
                
                if let point = depthData.point(at: nx, y: ny) {
                    neighborPoints.append(point)
                }
            }
        }
        
        guard !neighborPoints.isEmpty else {
            print("[LiDARManager] ❌ No neighbor points found")
            return nil
        }
        
        print("[LiDARManager] Step 3: Found \(neighborPoints.count) neighbor points")
        
        // Step 4: Calculate median depth for robust surface detection
        let depths = neighborPoints.map { $0.z }.sorted()
        let medianDepth = depths[depths.count / 2]
        
        print("[LiDARManager] Step 4: Median depth = \(String(format: "%.3f", medianDepth))m")
        
        // Step 5: Filter points on the same surface (within threshold)
        let surfacePoints = neighborPoints.filter { abs($0.z - medianDepth) < LiDARConstants.surfaceThreshold }
        
        guard !surfacePoints.isEmpty else {
            print("[LiDARManager] ❌ No consistent surface found (threshold: \(LiDARConstants.surfaceThreshold)m)")
            return nil
        }
        
        // Step 6: Average the surface points for final 3D world position
        let avgX = surfacePoints.map { $0.x }.reduce(0, +) / Float(surfacePoints.count)
        let avgY = surfacePoints.map { $0.y }.reduce(0, +) / Float(surfacePoints.count)
        let avgZ = surfacePoints.map { $0.z }.reduce(0, +) / Float(surfacePoints.count)
        
        // Get average pixel coordinates for the result
        let avgPixelX = surfacePoints.map { $0.pixelX }.reduce(0, +) / surfacePoints.count
        let avgPixelY = surfacePoints.map { $0.pixelY }.reduce(0, +) / surfacePoints.count
        
        let finalPoint = DepthPoint(x: avgX, y: avgY, z: avgZ, pixelX: avgPixelX, pixelY: avgPixelY)
        
        print("[LiDARManager] Step 6: Averaged \(surfacePoints.count) surface points")
        print("[LiDARManager] ✅ Final 3D camera point: x=\(String(format: "%.3f", finalPoint.x))m, y=\(String(format: "%.3f", finalPoint.y))m, z=\(String(format: "%.3f", finalPoint.z))m (depth)")
        print("[LiDARManager] === Transformation complete ===")
        
        return finalPoint
    }

    
    /// Calculates distance between two screen points using depth data
    /// - Parameters:
    ///   - point1: First screen point (normalized 0-1)
    ///   - point2: Second screen point (normalized 0-1)
    ///   - depthData: The depth data to use
    ///   - imageSize: The displayed image size
    /// - Returns: Distance in centimeters, or nil if points don't have depth data
    func calculateDistance(from point1: CGPoint, to point2: CGPoint, using depthData: DepthData, imageSize: CGSize) -> Double? {
        guard let depthPoint1 = getDepthPoint(at: point1, in: depthData, imageSize: imageSize),
            let depthPoint2 = getDepthPoint(at: point2, in: depthData, imageSize: imageSize) else {
            print("[LiDARManager] ❌ Could not get depth points for measurement")
            return nil
        }
        
        print("[LiDARManager] === Distance Calculation ===")
        print("[LiDARManager] Point 1 (camera): x=\(String(format: "%.3f", depthPoint1.x))m, y=\(String(format: "%.3f", depthPoint1.y))m, z=\(String(format: "%.3f", depthPoint1.z))m (depth)")
        print("[LiDARManager] Point 2 (camera): x=\(String(format: "%.3f", depthPoint2.x))m, y=\(String(format: "%.3f", depthPoint2.y))m, z=\(String(format: "%.3f", depthPoint2.z))m (depth)")
        
        // Check if points are on the same surface (depth difference < 50cm)
        let depthDifference = abs(depthPoint1.z - depthPoint2.z)
        if depthDifference > 0.5 {
            print("[LiDARManager] ⚠️ WARNING: Large depth difference (\(String(format: "%.2f", depthDifference))m)")
            print("[LiDARManager] ⚠️ Points may be on different surfaces!")
            print("[LiDARManager] ⚠️ This could indicate poor LiDAR data quality")
        }
        
        // Calculate 3D Euclidean distance in camera coordinates
        let dx = depthPoint2.x - depthPoint1.x
        let dy = depthPoint2.y - depthPoint1.y
        let dz = depthPoint2.z - depthPoint1.z
        
        let distanceMeters = sqrt(dx*dx + dy*dy + dz*dz)
        let distanceCm = Double(distanceMeters) * 100.0
        
        print("[LiDARManager] Delta: dx=\(String(format: "%.3f", dx))m, dy=\(String(format: "%.3f", dy))m, dz=\(String(format: "%.3f", dz))m")
        print("[LiDARManager] ✅ 3D Euclidean distance: \(String(format: "%.3f", distanceMeters))m = \(String(format: "%.1f", distanceCm))cm")
        
        // If points are on same surface (small depth diff), also show 2D distance
        if depthDifference < 0.1 {
            let distance2D = sqrt(dx*dx + dy*dy)
            print("[LiDARManager] 📏 2D distance (ignoring depth): \(String(format: "%.1f", Double(distance2D) * 100))cm")
        }
        
        return distanceCm
    }

    
    /// Calculates bounding box dimensions from four corner points
    /// - Parameters:
    ///   - topLeft: Top-left corner (normalized 0-1)
    ///   - topRight: Top-right corner (normalized 0-1)
    ///   - bottomLeft: Bottom-left corner (normalized 0-1)
    ///   - bottomRight: Bottom-right corner (normalized 0-1)
    ///   - depthData: The depth data to use
    ///   - imageSize: The displayed image size
    /// - Returns: Tuple of (width, height) in centimeters, or nil if calculation fails
    func calculateBoundingBox(topLeft: CGPoint,
                             topRight: CGPoint,
                             bottomLeft: CGPoint,
                             bottomRight: CGPoint,
                             using depthData: DepthData,
                             imageSize: CGSize) -> (width: Double, height: Double)? {
        
        print("[LiDARManager] === Bounding Box Calculation ===")
        
        // Get depth points for all corners
        guard let tlPoint = getDepthPoint(at: topLeft, in: depthData, imageSize: imageSize),
              let trPoint = getDepthPoint(at: topRight, in: depthData, imageSize: imageSize),
              let blPoint = getDepthPoint(at: bottomLeft, in: depthData, imageSize: imageSize),
              let brPoint = getDepthPoint(at: bottomRight, in: depthData, imageSize: imageSize) else {
            print("[LiDARManager] ❌ Could not get depth points for bounding box")
            return nil
        }
        
        print("[LiDARManager] Bounding box corners (world coordinates):")
        print("  TL: (\(String(format: "%.3f", tlPoint.x)), \(String(format: "%.3f", tlPoint.y)), \(String(format: "%.3f", tlPoint.z)))")
        print("  TR: (\(String(format: "%.3f", trPoint.x)), \(String(format: "%.3f", trPoint.y)), \(String(format: "%.3f", trPoint.z)))")
        print("  BL: (\(String(format: "%.3f", blPoint.x)), \(String(format: "%.3f", blPoint.y)), \(String(format: "%.3f", blPoint.z)))")
        print("  BR: (\(String(format: "%.3f", brPoint.x)), \(String(format: "%.3f", brPoint.y)), \(String(format: "%.3f", brPoint.z)))")
        
        // Calculate width (average of top and bottom edges) in meters
        let topWidthM = tlPoint.distance(to: trPoint)
        let bottomWidthM = blPoint.distance(to: brPoint)
        let widthM = (topWidthM + bottomWidthM) / 2.0
        let widthCm = Double(widthM) * 100.0
        
        // Calculate height (average of left and right edges) in meters
        let leftHeightM = tlPoint.distance(to: blPoint)
        let rightHeightM = trPoint.distance(to: brPoint)
        let heightM = (leftHeightM + rightHeightM) / 2.0
        let heightCm = Double(heightM) * 100.0
        
        print("[LiDARManager] Edge measurements:")
        print("  Top width: \(String(format: "%.1f", Double(topWidthM) * 100))cm, Bottom width: \(String(format: "%.1f", Double(bottomWidthM) * 100))cm")
        print("  Left height: \(String(format: "%.1f", Double(leftHeightM) * 100))cm, Right height: \(String(format: "%.1f", Double(rightHeightM) * 100))cm")
        print("[LiDARManager] ✅ Final bounding box: \(String(format: "%.1f", widthCm))cm × \(String(format: "%.1f", heightCm))cm")
        
        return (width: widthCm, height: heightCm)
    }
}

