//
//  Models.swift
//  LiDARapp
//
//  Created by LiDAR Team on 2026
//  Copyright © 2026 LiDAR Measurement App. All rights reserved.
//
//  Data models for the LiDAR app
//

import Foundation
import CoreGraphics

// MARK: - Media Type Enum
/// Defines the type of media captured
enum MediaType: String, Codable {
    case photo = "photo"
    case video = "video"
}

// MARK: - Media Item Model
/// Represents a single photo or video captured by the app
/// This is the main data structure that holds all information about captured media
struct MediaItem: Identifiable, Codable {
    /// Unique identifier for this media item
    let id: UUID
    
    /// File name where the media is stored (e.g., "photo_123.jpg")
    let fileName: String
    
    /// Type of media - either photo or video
    let type: MediaType
    
    /// When this media was captured
    let createdAt: Date
    
    /// Whether this media has associated LiDAR depth data
    /// This will be true only if captured on a LiDAR-capable device
    let hasLiDARData: Bool
    
    /// Optional file name for the depth data (e.g., "depth_123.json")
    /// Only present if hasLiDARData is true
    let depthDataFileName: String?
    
    /// Array of measurements taken on this media
    /// Starts empty and gets populated when user measures distances
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
/// Represents a single measurement taken on a media item
struct Measurement: Identifiable, Codable {
    /// Unique identifier for this measurement
    let id: UUID
    
    /// Type of measurement (distance or bounding box)
    let type: MeasurementType
    
    /// The calculated value in meters
    /// For distance: the distance between two points
    /// For bounding box: stored as width (we'll store height separately)
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
            return String(format: "Distance: %.2f m", value)
        case .boundingBox:
            let height = secondaryValue ?? 0
            return String(format: "Box: %.2f m × %.2f m", value, height)
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
    /// X coordinate in 3D space (meters)
    let x: Float
    
    /// Y coordinate in 3D space (meters)
    let y: Float
    
    /// Z coordinate (depth) in 3D space (meters)
    /// This is the distance from the camera to the point
    let z: Float
    
    /// Calculate Euclidean distance to another point
    func distance(to other: DepthPoint) -> Float {
        let dx = other.x - x
        let dy = other.y - y
        let dz = other.z - z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}

// MARK: - Depth Data Model
/// Container for depth data captured from LiDAR sensor
/// This stores the 3D point cloud data
struct DepthData: Codable {
    /// Array of 3D points captured by the LiDAR sensor
    let points: [DepthPoint]
    
    /// Width of the depth map (in pixels)
    let width: Int
    
    /// Height of the depth map (in pixels)
    let height: Int
    
    /// When this depth data was captured
    let capturedAt: Date
    
    /// Get depth point at specific screen coordinates
    /// - Parameters:
    ///   - x: Screen x coordinate (0 to width-1)
    ///   - y: Screen y coordinate (0 to height-1)
    /// - Returns: The depth point at that location, or nil if out of bounds
    func point(at x: Int, y: Int) -> DepthPoint? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let index = y * width + x
        guard index < points.count else { return nil }
        return points[index]
    }
}

