//
//  ContentView.swift
//  LiDARapp
//
//  Created by LiDAR Team on 2026
//  Copyright © 2026 LiDAR Measurement App. All rights reserved.
//
//  Main app interface with Camera and Gallery tabs
//

import SwiftUI

// MARK: - Content View
/// Main app view with tab navigation
struct ContentView: View {
    // Track the selected tab
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Camera Tab
            CameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(0)
            
            // Gallery Tab
            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
                .tag(1)
        }
        .accentColor(.blue)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
