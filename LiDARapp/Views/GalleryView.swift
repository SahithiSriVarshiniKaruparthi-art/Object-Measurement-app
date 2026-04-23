//
//  GalleryView.swift
//  
//  Gallery view to display all captured photos and videos
//

import SwiftUI
import AVFoundation

// MARK: - Gallery View
/// Main gallery view showing all captured media in a grid
struct GalleryView: View {
    @ObservedObject var dataStore = DataStore.shared
    @State private var selectedItem: MediaItem?
    
    // Grid layout - 3 columns
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            Group {
                if dataStore.mediaItems.isEmpty {
                    // Empty state
                    EmptyGalleryView()
                } else {
                    // Grid of media items
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(dataStore.mediaItems) { item in
                                MediaThumbnailView(mediaItem: item)
                                    .aspectRatio(1, contentMode: .fill)
                                    .onTapGesture {
                                        selectedItem = item
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(dataStore.mediaItems.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .sheet(item: $selectedItem) { item in
                // Show detail card when item is tapped
                MediaDetailView(mediaItem: item)
            }
        }
    }
}

// MARK: - Empty Gallery View
/// Shown when no media has been captured yet
struct EmptyGalleryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("No Photos or Videos")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Capture photos and videos using the camera tab")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Media Thumbnail View
/// Displays a thumbnail for a media item in the grid
struct MediaThumbnailView: View {
    let mediaItem: MediaItem
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                // Loading placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                    )
            }
            
            // Media type indicator
            HStack(spacing: 4) {
                // Video icon
                if mediaItem.type == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                
                // LiDAR indicator
                if mediaItem.hasLiDARData {
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(6)
            .padding(4)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    /// Loads the thumbnail image for this media item
    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb: UIImage?
            
            switch mediaItem.type {
            case .photo:
                // For photos, load the actual image
                thumb = DataStore.shared.loadImage(for: mediaItem)
                
            case .video:
                // For videos, generate a thumbnail from the first frame
                thumb = generateVideoThumbnail(for: mediaItem)
            }
            
            DispatchQueue.main.async {
                self.thumbnail = thumb
            }
        }
    }
    
    /// Generates a thumbnail from a video file
    private func generateVideoThumbnail(for mediaItem: MediaItem) -> UIImage? {
        let url = DataStore.shared.getMediaURL(for: mediaItem)
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("[LiDARManager] Error generating video thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Media Detail View
/// Full-screen detail view for a media item with measurements
struct MediaDetailView: View {
    let mediaItem: MediaItem
    @Environment(\.dismiss) var dismiss
    @State private var showMeasurementView = false
    @State private var fullImage: UIImage?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Media preview
                    MediaPreviewView(mediaItem: mediaItem, fullImage: $fullImage)
                        .frame(height: 400)
                        .clipped()
                    
                    // Metadata section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        DetailRow(icon: "calendar", title: "Created", value: formatDate(mediaItem.createdAt))
                        DetailRow(icon: "photo", title: "Type", value: mediaItem.type.rawValue.capitalized)
                        DetailRow(
                            icon: mediaItem.hasLiDARData ? "cube.fill" : "cube",
                            title: "LiDAR Data",
                            value: mediaItem.hasLiDARData ? "Available" : "Not Available",
                            valueColor: mediaItem.hasLiDARData ? .green : .secondary
                        )
                    }
                    .padding(.vertical)
                    
                    Divider()
                    
                    // Measurements section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Measurements")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(mediaItem.measurements.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        if mediaItem.measurements.isEmpty {
                            Text("No measurements yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(mediaItem.measurements) { measurement in
                                MeasurementRow(measurement: measurement)
                            }
                        }
                    }
                    .padding(.vertical)
                    
                    // Measure button
                    Button(action: { 
                        // Only show measurement if image is already loaded
                        print("[LiDARManager] Measure button tapped")
                        print("[CameraView] fullImage exists: \(fullImage != nil)")
                        if fullImage != nil {
                            showMeasurementView = true
                            print("[LiDARManager] Setting showMeasurementView = true")
                        }
                    }) {
                        Label("Measure", systemImage: "ruler")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(mediaItem.hasLiDARData && fullImage != nil ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!mediaItem.hasLiDARData || fullImage == nil)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Media Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showMeasurementView) {
                if let image = fullImage {
                    MeasurementView(mediaItem: mediaItem, image: image)
                        .onAppear {
                            print("[GalleryView] MeasurementView sheet appeared with image")
                        }
                } else {
                    VStack {
                        Text("Image not loaded")
                        ProgressView()
                    }
                    .onAppear {
                        print("[LiDARManager] Sheet appeared but no image")
                    }
                }
            }

            .onAppear {
                loadFullImage()
            }
        }
    }
    
    /// Loads the full resolution image
    private func loadFullImage() {
        if mediaItem.type == .photo {
            fullImage = DataStore.shared.loadImage(for: mediaItem)
            print("[CameraView] Loaded image for measurement: \(fullImage != nil)")
        }
    }

    
    /// Formats a date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Media Preview View
/// Shows the media (photo or video) in the detail view
struct MediaPreviewView: View {
    let mediaItem: MediaItem
    @Binding var fullImage: UIImage?
    
    var body: some View {
        ZStack {
            if mediaItem.type == .photo {
                // Photo preview
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            } else {
                // Video preview (thumbnail with play icon)
                VideoPreviewView(mediaItem: mediaItem)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Video Preview View
/// Shows a video thumbnail with play button
struct VideoPreviewView: View {
    let mediaItem: MediaItem
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
            
            // Play button overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .shadow(radius: 10)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = DataStore.shared.getMediaURL(for: mediaItem)
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                DispatchQueue.main.async {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("[LiDARManager] Error generating video thumbnail: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Detail Row
/// A row showing a detail field (icon, title, value)
struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(valueColor)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
    }
}

// MARK: - Measurement Row
/// Displays a single measurement in the list
struct MeasurementRow: View {
    let measurement: Measurement
    
    var body: some View {
        HStack {
            Image(systemName: measurement.type == .distance ? "ruler" : "square.dashed")
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.description)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(formatDate(measurement.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview {
    GalleryView()
}

