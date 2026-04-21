# LiDAR Measurement App

A professional iOS application for capturing photos and videos with LiDAR depth data, enabling real-world distance and dimensional measurements.

## 📱 Features

- **LiDAR Detection**: Automatic detection of LiDAR-capable devices
- **Photo & Video Capture**: Capture media with synchronized depth data
- **Distance Measurements**: Measure point-to-point distances in real-world units
- **Bounding Box Measurements**: Calculate width and height of objects
- **Persistent Storage**: Save all captures and measurements locally
- **Gallery View**: Browse and manage captured media
- **Interactive Measurement Tools**: Intuitive tap-based measurement interface

## 🔧 Requirements

- **iOS**: 14.0 or later
- **Device**: LiDAR-equipped device required for depth features
  - iPhone 12 Pro / Pro Max or later
  - iPhone 13 Pro / Pro Max or later
  - iPhone 14 Pro / Pro Max or later
  - iPhone 15 Pro / Pro Max or later
  - iPad Pro (4th generation) 11-inch or later
  - iPad Pro (5th generation) 12.9-inch or later
- **Xcode**: 14.0 or later
- **Swift**: 5.7 or later

## 🚀 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/LiDARapp.git
   cd LiDARapp
   ```

2. Open the project in Xcode:
   ```bash
   open LiDARapp.xcodeproj
   ```

3. Select your development team in the project settings

4. Build and run on a LiDAR-capable device (Simulator will not have LiDAR functionality)

## 📖 Usage

### Capturing Media

1. Open the app and navigate to the **Camera** tab
2. Tap **Open Camera** to start the camera session
3. The LiDAR status indicator shows if depth capture is available
4. Tap the capture button to take a photo
5. Switch to video mode using the mode toggle button

### Taking Measurements

1. Navigate to the **Gallery** tab
2. Tap on any photo with LiDAR data (indicated by the cube icon)
3. Tap the **Measure** button
4. Choose measurement mode:
   - **Distance**: Tap two points to measure the distance between them
   - **Bounding Box**: Tap four corners to measure width and height
5. Review the measurement result and tap **Save** to store it

## 🏗️ Architecture

The app follows a clean architecture pattern with clear separation of concerns:

```
LiDARapp/
├── App/                    # App entry point
│   └── LiDARappApp.swift
├── Core/                   # Core business logic
│   ├── Managers/          # Service layer
│   │   ├── LiDARManager.swift    # LiDAR & ARKit integration
│   │   └── DataStore.swift       # Data persistence
│   └── Models/            # Data models
│       └── Models.swift
├── Views/                  # UI layer
│   ├── CameraView.swift
│   ├── GalleryView.swift
│   ├── MeasurementView.swift
│   └── ContentView.swift
└── Resources/             # Assets and resources
    └── Assets.xcassets/
```


## Technical Details

### LiDAR Integration

The app uses ARKit's `ARWorldTrackingConfiguration` with `.sceneDepth` frame semantics to capture depth data. The depth map is converted to a 3D point cloud for accurate measurements.

### Measurement Algorithms

- **Distance**: Calculates 3D Euclidean distance between two points
- **Bounding Box**: Averages edge lengths for width and height
- **Depth Filtering**: Uses median filtering and surface detection for accuracy

### Data Storage

- **Media Files**: Stored in app's Documents directory
- **Depth Data**: Saved as JSON for easy parsing
- **Metadata**: Persisted using UserDefaults with Codable
