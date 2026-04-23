
//  DataStore.swift
//  LiDARapp

//  Simple data persistence manager using UserDefaults and FileManager
//  POC implementation


import Foundation
import UIKit
import Combine

// MARK: - Data Store
/// Manages all data persistence for the app
/// Uses UserDefaults for metadata and FileManager for actual files
class DataStore: ObservableObject {
    
    static let shared = DataStore()

    @Published var mediaItems: [MediaItem] = []

    private let mediaItemsKey = "mediaItems"

    private let mediaDirectory: URL
  
    private let depthDirectory: URL
    
    // MARK: - Initialization
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        mediaDirectory = documentsPath.appendingPathComponent("Media", isDirectory: true)
        depthDirectory = documentsPath.appendingPathComponent("DepthData", isDirectory: true)
        
        createDirectoriesIfNeeded()
        loadMediaItems()
    }
    
    // MARK: - Directory Management
    /// Creates the media and depth data directories if they don't exist
    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: mediaDirectory.path) {
            try? fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            print("[DataStore] Created media directory at: \(mediaDirectory.path)")
        }
        
        if !fileManager.fileExists(atPath: depthDirectory.path) {
            try? fileManager.createDirectory(at: depthDirectory, withIntermediateDirectories: true)
            print("[DataStore] Created depth data directory at: \(depthDirectory.path)")
        }
    }
    
    // MARK: - Load Data
    /// Loads all media items from UserDefaults
    private func loadMediaItems() {
        guard let data = UserDefaults.standard.data(forKey: mediaItemsKey) else {
            print("[DataStore] No saved media items found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            mediaItems = try decoder.decode([MediaItem].self, from: data)
            print("[DataStore] Loaded \(mediaItems.count) media items")
        } catch {
            print("[LiDARManager] Error loading media items: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Save Data
    /// Saves all media items to UserDefaults
    private func saveMediaItems() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(mediaItems)
            UserDefaults.standard.set(data, forKey: mediaItemsKey)
            print("[DataStore] Saved \(mediaItems.count) media items")
        } catch {
            print("[LiDARManager] Error saving media items: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Add Media Item
    /// Adds a new media item to the store
    /// - Parameters:
    ///   - image: The captured image (for photos)
    ///   - videoURL: The video file URL (for videos)
    ///   - type: Type of media (photo or video)
    ///   - depthData: Optional depth data from LiDAR
    /// - Returns: The created MediaItem, or nil if save failed
    @discardableResult
    func addMediaItem(image: UIImage? = nil,
                      videoURL: URL? = nil,
                      type: MediaType,
                      depthData: DepthData? = nil) -> MediaItem? {
        
        let id = UUID()
        let timestamp = Date()
        
        // Generate file names
        let mediaFileName: String
        let mediaFileURL: URL
        
        switch type {
        case .photo:
            guard let image = image else {
                print("[LiDARManager] No image provided for photo")
                return nil
            }
            mediaFileName = "photo_\(id.uuidString).jpg"
            mediaFileURL = mediaDirectory.appendingPathComponent(mediaFileName)
            
            // Save image to file
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("[LiDARManager] Failed to convert image to JPEG")
                return nil
            }
            
            do {
                try imageData.write(to: mediaFileURL)
                print("[CameraView] Saved photo to: \(mediaFileURL.lastPathComponent)")
            } catch {
                print("[LiDARManager] Error saving photo: \(error.localizedDescription)")
                return nil
            }
            
        case .video:
            guard let videoURL = videoURL else {
                print("[LiDARManager] No video URL provided")
                return nil
            }
            mediaFileName = "video_\(id.uuidString).mov"
            mediaFileURL = mediaDirectory.appendingPathComponent(mediaFileName)
            
            // Copy video file
            do {
                try FileManager.default.copyItem(at: videoURL, to: mediaFileURL)
                print("[CameraView] Saved video to: \(mediaFileURL.lastPathComponent)")
            } catch {
                print("[LiDARManager] Error saving video: \(error.localizedDescription)")
                return nil
            }
        }
        
        // Save depth data if available
        var depthDataFileName: String?
        if let depthData = depthData {
            depthDataFileName = "depth_\(id.uuidString).json"
            let depthFileURL = depthDirectory.appendingPathComponent(depthDataFileName!)
            
            do {
                let encoder = JSONEncoder()
                let depthJSON = try encoder.encode(depthData)
                try depthJSON.write(to: depthFileURL)
                print("[LiDARManager] Saved depth data to: \(depthFileURL.lastPathComponent)")
            } catch {
                print("[LiDARManager] Warning: Failed to save depth data: \(error.localizedDescription)")
                depthDataFileName = nil
            }
        }
        
        // Create media item
        let mediaItem = MediaItem(
            id: id,
            fileName: mediaFileName,
            type: type,
            createdAt: timestamp,
            hasLiDARData: depthData != nil,
            depthDataFileName: depthDataFileName,
            measurements: []
        )
        
        // Add to array and save
        mediaItems.append(mediaItem)
        saveMediaItems()
        
        return mediaItem
    }
    
    // MARK: - Update Media Item
    /// Updates an existing media item (to add measurements, etc)
    /// - Parameter mediaItem: The updated media item
    func updateMediaItem(_ mediaItem: MediaItem) {
        if let index = mediaItems.firstIndex(where: { $0.id == mediaItem.id }) {
            mediaItems[index] = mediaItem
            saveMediaItems()
            print("✏️ Updated media item: \(mediaItem.fileName)")
        }
    }
    
    // MARK: - Delete Media Item
    /// Deletes a media item and its associated files
    /// - Parameter mediaItem: The media item to delete
    func deleteMediaItem(_ mediaItem: MediaItem) {
        // Delete media file
        let mediaFileURL = mediaDirectory.appendingPathComponent(mediaItem.fileName)
        try? FileManager.default.removeItem(at: mediaFileURL)
        
        // Delete depth data file if exists
        if let depthFileName = mediaItem.depthDataFileName {
            let depthFileURL = depthDirectory.appendingPathComponent(depthFileName)
            try? FileManager.default.removeItem(at: depthFileURL)
        }
        
        // Remove from array
        mediaItems.removeAll { $0.id == mediaItem.id }
        saveMediaItems()
        
        print("[DataStore] Deleted media item: \(mediaItem.fileName)")
    }
    
    // MARK: - Get File URLs
    /// - Parameter mediaItem: The media item
    /// - Returns: URL to the media file
    func getMediaURL(for mediaItem: MediaItem) -> URL {
        return mediaDirectory.appendingPathComponent(mediaItem.fileName)
    }
    
    /// Loads the image for a photo media item
    /// - Parameter mediaItem: The media item (must be a photo)
    /// - Returns: UIImage if successful, nil otherwise
    func loadImage(for mediaItem: MediaItem) -> UIImage? {
        guard mediaItem.type == .photo else { return nil }
        let url = getMediaURL(for: mediaItem)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    /// Loads depth data for a media item
    /// - Parameter mediaItem: The media item
    /// - Returns: DepthData if available, nil otherwise
    func loadDepthData(for mediaItem: MediaItem) -> DepthData? {
        guard let depthFileName = mediaItem.depthDataFileName else { return nil }
        let url = depthDirectory.appendingPathComponent(depthFileName)
        
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(DepthData.self, from: data)
        } catch {
            print("[LiDARManager] Error loading depth data: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Add Measurement
    /// Adds a measurement to a media item
    /// - Parameters:
    ///   - measurement: The measurement to add
    ///   - mediaItem: The media item to add it to
    func addMeasurement(_ measurement: Measurement, to mediaItem: MediaItem) {
        if let index = mediaItems.firstIndex(where: { $0.id == mediaItem.id }) {
            mediaItems[index].measurements.append(measurement)
            saveMediaItems()
            print("[LiDARManager] Added measurement to: \(mediaItem.fileName)")
        }
    }
}

