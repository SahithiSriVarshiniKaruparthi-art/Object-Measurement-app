//
//  Models.swift

//  Data models for the LiDAR app
//

import Foundation
import CoreGraphics
import simd

// MARK: - Media Type Enum
/// Defines the type of media captured
enum MediaType: String, Codable {
    case photo = "photo"
    case video = "video"
}

// MARK: - Media Item Model
/// Represents a single photo or video captured by the app
struct MediaItem: Identifiable, Codable {

    let id: UUID

    let fileName: String

    let type: MediaType

    let createdAt: Date

    let hasLiDARData: Bool

    let depthDataFileName: String?

    var measurements: [Measurement]
    
    /// Initializer with default values
    init(id: UUID = UUID(),
         fileName: String,
         type: MediaType,
         createdAt: Date = Date(),
         hasLiDARData: Bool = false,
         depthDataFileName: String? = nil,
         measurements: [Measurement] = []) {
        self.id = id
        self.fileName = fileName
        self.type = type
        self.createdAt = createdAt
        self.hasLiDARData = hasLiDARData
        self.depthDataFileName = depthDataFileName
        self.measurements = measurements
    }
}

// MARK: - Measurement Type Enum
/// Defines the type of measurement taken
enum MeasurementType: String, Codable {
    case distance = "distance"        // Point-to-point distance
    case boundingBox = "boundingBox"  // Width and height of a box
}

// MARK: - Measurement Model
struct Measurement: Identifiable, Codable {

    let id: UUID

    let type: MeasurementType
 
    let value: Double
    
    /// For bounding box measurements, stores the height in meters
    let secondaryValue: Double?
    
    /// The 2D screen coordinates where user tapped/drew
    /// For distance: 2 points [start, end]
    /// For bounding box: 4 points [topLeft, topRight, bottomRight, bottomLeft]
    let screenPoints: [CGPoint]
    
    /// When this measurement was taken
    let createdAt: Date
    
    /// Human-readable description of the measurement
    var description: String {
        switch type {
        case .distance:
            // Value is stored in cm
            let meters = value / 100.0
            return String(format: "Distance: %.1f cm (%.2f m)", value, meters)
        case .boundingBox:
            // Values are stored in cm
            let height = secondaryValue ?? 0
            let widthM = value / 100.0
            let heightM = height / 100.0
            return String(format: "Box: %.1f cm × %.1f cm (%.2f m × %.2f m)", value, height, widthM, heightM)
        }
    }
    
    /// Initializer
    init(id: UUID = UUID(),
         type: MeasurementType,
         value: Double,
         secondaryValue: Double? = nil,
         screenPoints: [CGPoint],
         createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.value = value
        self.secondaryValue = secondaryValue
        self.screenPoints = screenPoints
        self.createdAt = createdAt
    }
}

// MARK: - Depth Point Model
/// Represents a 3D point in space with depth information from LiDAR
struct DepthPoint: Codable {

    let x: Float

    let y: Float

    /// This is the distance from the camera to the point
    let z: Float
    
    /// Original pixel coordinates in depth map (for reverse lookup)
    let pixelX: Int
    let pixelY: Int
    
    /// Calculate Euclidean distance to another point
    func distance(to other: DepthPoint) -> Float {
        let dx = other.x - x
        let dy = other.y - y
        let dz = other.z - z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}

// MARK: - Camera Intrinsics Model
/// Camera intrinsic parameters for coordinate transformations
struct CameraIntrinsics: Codable {
    let fx: Float  // Focal length X
    let fy: Float  // Focal length Y
    let cx: Float  // Principal point X
    let cy: Float  // Principal point Y
    
    init(fx: Float, fy: Float, cx: Float, cy: Float) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
    }
    
    /// Initialize from simd_float3x3 matrix
    init(from matrix: simd_float3x3) {
        self.fx = matrix[0, 0]
        self.fy = matrix[1, 1]
        self.cx = matrix[2, 0]
        self.cy = matrix[2, 1]
    }
}

// MARK: - Depth Data Model
/// Container for depth data captured from LiDAR sensor
/// This stores the 3D point cloud data with camera metadata for accurate measurements
struct DepthData: Codable {
    /// Array of 3D points captured by the LiDAR sensor (in world coordinates)
    let points: [DepthPoint]
    
    /// Width of the depth map (in pixels)
    let width: Int
    
    /// Height of the depth map (in pixels)
    let height: Int
    
    /// Camera intrinsic parameters (focal length, principal point)
    let cameraIntrinsics: CameraIntrinsics
    
    /// Original camera image resolution
    let imageResolution: CGSize
    
    /// Depth map resolution
    let depthResolution: CGSize
    
    /// When this depth data was captured
    let capturedAt: Date
    
    /// Get depth point at specific depth map pixel coordinates
    /// - Parameters:
    ///   - x: Depth map x coordinate (0 to width-1)
    ///   - y: Depth map y coordinate (0 to height-1)
    /// - Returns: The depth point at that location, or nil if out of bounds
    func point(at x: Int, y: Int) -> DepthPoint? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let index = y * width + x
        guard index < points.count else { return nil }
        return points[index]
    }
    
    /// Find the closest depth point to a given image pixel coordinate
    /// This properly handles the mapping from image space to depth space
    /// - Parameters:
    ///   - imageX: X coordinate in image space (0 to imageResolution.width)
    ///   - imageY: Y coordinate in image space (0 to imageResolution.height)
    ///   - searchRadius: Radius in pixels to search for valid depth points
    /// - Returns: The closest valid depth point, or nil if none found
    func findClosestPoint(toImagePixel imageX: Float, imageY: Float, searchRadius: Int = 3) -> DepthPoint? {
        // Map image coordinates to depth map coordinates
        let scaleX = Float(depthResolution.width) / Float(imageResolution.width)
        let scaleY = Float(depthResolution.height) / Float(imageResolution.height)
        
        let depthX = Int(imageX * scaleX)
        let depthY = Int(imageY * scaleY)
        
        // Search in a neighborhood for valid points
        var candidates: [(point: DepthPoint, distance: Float)] = []
        
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let x = depthX + dx
                let y = depthY + dy
                
                if let point = self.point(at: x, y: y) {
                    // Calculate distance from target pixel
                    let pixelDist = sqrt(Float(dx * dx + dy * dy))
                    candidates.append((point, pixelDist))
                }
            }
        }
        
        // Return closest point by pixel distance
        return candidates.min(by: { $0.distance < $1.distance })?.point
    }
}

