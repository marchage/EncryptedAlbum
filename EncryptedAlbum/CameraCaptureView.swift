import AVKit
import SwiftUI

#if os(iOS)
    import UIKit
    import Photos

    /// Custom camera view using AVFoundation for proper landscape support.
    /// UIImagePickerController has known issues with landscape orientation on iOS,
    /// so we use AVCaptureSession directly for reliable camera preview in all orientations.
    struct CameraCaptureView: View {
        @Environment(\.dismiss) var dismiss
        @EnvironmentObject var albumManager: AlbumManager
        @StateObject private var model = iOSCameraModel()
        @State private var showCaptureFlash = false
        @State private var captureCount = 0

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if model.isAuthorized, let session = model.session {
                        iOSCameraPreview(session: session)
                            .ignoresSafeArea()
                    } else if !model.isAuthorized && model.authorizationChecked {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.gray)
                            Text("Camera access required")
                                .foregroundStyle(.white)
                            Text("Please enable camera access in Settings")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }

                    // Capture flash overlay
                    if showCaptureFlash {
                        Color.white
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    // Camera controls overlay
                    VStack {
                        // Top bar with close button
                        HStack {
                            Spacer()

                            // Flash toggle
                            if model.flashAvailable {
                                Button {
                                    model.cycleFlashMode()
                                } label: {
                                    Image(systemName: model.flashIconName)
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .padding(12)
                                }
                            }

                            Button {
                                model.stopSession()
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .padding()
                            }
                        }
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 8)

                        Spacer()

                        // Bottom controls
                        HStack(alignment: .center, spacing: 40) {
                            // Camera flip button
                            Button {
                                model.switchCamera()
                            } label: {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(width: 50, height: 50)
                            }

                            // Capture button
                            if model.captureMode == .video {
                                Button {
                                    if model.isRecording {
                                        model.stopRecording(albumManager: albumManager)
                                        captureCount += 1
                                    } else {
                                        model.startRecording()
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(model.isRecording ? .red : .white)
                                            .frame(width: 64, height: 64)
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 72, height: 72)
                                        if model.isRecording {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(.white)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                }
                            } else {
                                Button {
                                    model.capturePhoto(albumManager: albumManager)
                                    // Visual feedback: brief flash
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        showCaptureFlash = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeIn(duration: 0.15)) {
                                            showCaptureFlash = false
                                        }
                                    }
                                    captureCount += 1
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 64, height: 64)
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 72, height: 72)
                                    }
                                }
                            }

                            // Mode toggle (photo/video)
                            Button {
                                model.captureMode = model.captureMode == .photo ? .video : .photo
                            } label: {
                                Image(systemName: model.captureMode == .photo ? "video.fill" : "camera.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(width: 50, height: 50)
                            }
                        }
                        .padding(.bottom, 30)

                        // Recording duration indicator
                        if model.isRecording, let duration = model.recordingDuration {
                            Text(String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60))
                                .font(.system(.headline, design: .monospaced))
                                .foregroundStyle(.red)
                                .padding(.bottom, 8)
                        }

                        // Capture count badge
                        if captureCount > 0 {
                            Text("\(captureCount) saved")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.8))
                                .clipShape(Capsule())
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .statusBarHidden(true)
            .onAppear {
                model.checkPermissions()
            }
            .onDisappear {
                model.stopSession()
            }
        }
    }

    // MARK: - iOS Camera Model

    enum iOSCaptureMode {
        case photo
        case video
    }

    class iOSCameraModel: NSObject, ObservableObject {
        @Published var isAuthorized = false
        @Published var authorizationChecked = false
        @Published var captureMode: iOSCaptureMode = .photo
        @Published var isRecording = false
        @Published var recordingDuration: TimeInterval?
        @Published var flashAvailable = false
        @Published var flashMode: AVCaptureDevice.FlashMode = .auto

        var session: AVCaptureSession?
        private let photoOutput = AVCapturePhotoOutput()
        private let movieOutput = AVCaptureMovieFileOutput()
        private let sessionQueue = DispatchQueue(label: "biz.front-end.encryptedalbum.ios.camera")
        private var currentDevice: AVCaptureDevice?
        private var currentPosition: AVCaptureDevice.Position = .back

        private var recordingTimer: Timer?
        private var recordingStartTime: Date?
        private var albumManager: AlbumManager?

        var flashIconName: String {
            switch flashMode {
            case .auto: return "bolt.badge.automatic.fill"
            case .on: return "bolt.fill"
            case .off: return "bolt.slash.fill"
            @unknown default: return "bolt.fill"
            }
        }

        func checkPermissions() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    self.authorizationChecked = true
                }
                setupSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        self.isAuthorized = granted
                        self.authorizationChecked = true
                        if granted { self.setupSession() }
                    }
                }
            default:
                DispatchQueue.main.async {
                    self.isAuthorized = false
                    self.authorizationChecked = true
                }
            }

            // Also request microphone for video
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
        }

        func setupSession() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                let session = AVCaptureSession()
                session.beginConfiguration()
                session.sessionPreset = .photo

                // Add video input
                guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                    let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
                else {
                    session.commitConfiguration()
                    return
                }

                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    self.currentDevice = videoDevice
                }

                // Add photo output
                if session.canAddOutput(self.photoOutput) {
                    session.addOutput(self.photoOutput)
                }

                // Add movie output
                if session.canAddOutput(self.movieOutput) {
                    session.addOutput(self.movieOutput)
                }

                // Add audio input for video recording
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    let audioDevice = AVCaptureDevice.default(for: .audio),
                    let audioInput = try? AVCaptureDeviceInput(device: audioDevice)
                {
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                    }
                }

                session.commitConfiguration()
                session.startRunning()

                self.session = session

                DispatchQueue.main.async {
                    self.flashAvailable = videoDevice.hasFlash
                }
            }
        }

        func stopSession() {
            recordingTimer?.invalidate()
            recordingTimer = nil

            sessionQueue.async { [weak self] in
                self?.session?.stopRunning()
            }
        }

        func switchCamera() {
            sessionQueue.async { [weak self] in
                guard let self = self, let session = self.session else { return }

                session.beginConfiguration()

                // Remove current video input
                if let currentInput = session.inputs.first(where: {
                    ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true
                }) {
                    session.removeInput(currentInput)
                }

                // Switch position
                let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back

                guard
                    let newDevice = AVCaptureDevice.default(
                        .builtInWideAngleCamera, for: .video, position: newPosition),
                    let newInput = try? AVCaptureDeviceInput(device: newDevice)
                else {
                    session.commitConfiguration()
                    return
                }

                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    self.currentDevice = newDevice
                    self.currentPosition = newPosition

                    DispatchQueue.main.async {
                        self.flashAvailable = newDevice.hasFlash
                    }
                }

                session.commitConfiguration()
            }
        }

        func cycleFlashMode() {
            switch flashMode {
            case .auto:
                flashMode = .on
            case .on:
                flashMode = .off
            case .off:
                flashMode = .auto
            @unknown default:
                flashMode = .auto
            }
        }

        func capturePhoto(albumManager: AlbumManager) {
            self.albumManager = albumManager

            let settings = AVCapturePhotoSettings()
            if flashAvailable {
                settings.flashMode = flashMode
            }

            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        func startRecording() {
            guard !movieOutput.isRecording else { return }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("video_\(Date().timeIntervalSince1970).mov")

            movieOutput.startRecording(to: tempURL, recordingDelegate: self)

            recordingStartTime = Date()
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let start = self.recordingStartTime else { return }
                    self.recordingDuration = Date().timeIntervalSince(start)
                }
            }
        }

        func stopRecording(albumManager: AlbumManager) {
            self.albumManager = albumManager
            movieOutput.stopRecording()

            recordingTimer?.invalidate()
            recordingTimer = nil

            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingDuration = nil
            }
        }
    }

    // MARK: - Photo Capture Delegate

    extension iOSCameraModel: AVCapturePhotoCaptureDelegate {
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?)
        {
            guard let data = photo.fileDataRepresentation(),
                let albumManager = albumManager
            else {
                AppLog.error("iOSCameraModel: Failed to get photo data")
                return
            }

            let filename = "Capture_\(Date().timeIntervalSince1970).jpg"

            Task {
                do {
                    try await albumManager.handleCapturedMedia(
                        mediaSource: .data(data),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Album",
                        assetIdentifier: nil,
                        mediaType: .photo,
                        duration: nil,
                        location: nil,
                        isFavorite: nil
                    )
                    AppLog.debugPublic("Captured photo saved: \(filename)")
                } catch {
                    AppLog.error("Failed to save captured photo: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Video Recording Delegate

    extension iOSCameraModel: AVCaptureFileOutputRecordingDelegate {
        func fileOutput(
            _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
            from connections: [AVCaptureConnection], error: Error?
        ) {
            if let error = error {
                AppLog.error("Video recording error: \(error.localizedDescription)")
                return
            }

            guard let albumManager = albumManager else { return }

            let filename = "Video_\(Date().timeIntervalSince1970).mov"

            Task {
                let asset = AVAsset(url: outputFileURL)
                var duration: TimeInterval?
                if #available(iOS 16.0, *) {
                    if let loaded = try? await asset.load(.duration) {
                        duration = loaded.seconds
                    }
                } else {
                    duration = asset.duration.seconds
                }

                do {
                    try await albumManager.handleCapturedMedia(
                        mediaSource: .fileURL(outputFileURL),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Album",
                        assetIdentifier: nil,
                        mediaType: .video,
                        duration: duration,
                        location: nil,
                        isFavorite: nil
                    )
                    AppLog.debugPublic("Captured video saved: \(filename)")
                } catch {
                    AppLog.error("Failed to save captured video: \(error.localizedDescription)")
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        }
    }

    // MARK: - iOS Camera Preview (AVCaptureSession based)

    struct iOSCameraPreview: UIViewRepresentable {
        let session: AVCaptureSession

        func makeUIView(context: Context) -> iOSPreviewView {
            let view = iOSPreviewView()
            view.session = session
            return view
        }

        func updateUIView(_ uiView: iOSPreviewView, context: Context) {
            // Preview layer updates automatically with device orientation
        }
    }

    class iOSPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                previewLayer.session = newValue
                previewLayer.videoGravity = .resizeAspectFill
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // Update video orientation based on device orientation
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                let orientation = UIDevice.current.orientation
                switch orientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeRight
                case .landscapeRight:
                    connection.videoOrientation = .landscapeLeft
                default:
                    // Keep current orientation for face up/down/unknown
                    break
                }
            }
        }
    }

#endif

#if os(macOS)
    import AppKit
    import AVFoundation

    struct CameraCaptureView: View {
        @Environment(\.dismiss) var dismiss
        @EnvironmentObject var albumManager: AlbumManager
        @StateObject private var model = CameraModel()
        @State private var cameraErrorMessage: String?
        @State private var showCaptureFlash = false
        @State private var captureCount = 0

        var body: some View {
            ZStack {
                PrivacyOverlayBackground(asBackground: true)

                if model.isAuthorized, let session = model.session {
                    CameraPreview(session: session)
                        .ignoresSafeArea()
                } else {
                    Text("Camera access required")
                        .foregroundStyle(.white)
                }

                // Capture flash overlay
                if showCaptureFlash {
                    Color.white
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                VStack {
                    HStack {
                        // Mode toggle
                        Picker("", selection: $model.captureMode) {
                            Label("Photo", systemImage: "camera.fill").tag(CaptureMode.photo)
                            Label("Video", systemImage: "video.fill").tag(CaptureMode.video)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .padding(.leading)

                        Spacer()

                        // Capture count badge
                        if captureCount > 0 {
                            Text("\\(captureCount) saved")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        // Torch (flash) toggle — some cameras support a torch mode
                        // that can be toggled while previewing. Expose that control
                        // here so users don't have to reach for a small system control
                        // that might be hidden at the top of the preview.
                        if model.torchAvailable {
                            Button {
                                model.toggleTorch()
                            } label: {
                                Image(systemName: model.torchOn ? "bolt.fill" : "bolt")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                        }

                        Button {
                            model.stopSession()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding()
                    }

                    Spacer()

                    HStack {
                        Spacer()

                        if model.captureMode == .video {
                            VStack(spacing: 12) {
                                if model.isRecording, let duration = model.recordingDuration {
                                    Text(String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60))
                                        .font(.system(.title2, design: .monospaced))
                                        .foregroundStyle(.white)
                                }

                                // Video recording button
                                Button {
                                    if model.isRecording {
                                        model.stopRecording(albumManager: albumManager) {
                                            // Keep camera open after recording
                                        }
                                        captureCount += 1
                                    } else {
                                        model.startRecording()
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(model.isRecording ? .red : .white)
                                            .frame(width: 64, height: 64)
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 72, height: 72)
                                        if model.isRecording {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(.white)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.bottom, 30)
                        } else {
                            // Photo capture button
                            Button {
                                model.capturePhoto(albumManager: albumManager) {
                                    // Keep camera open after capture
                                }
                                // Visual feedback: brief flash
                                withAnimation(.easeOut(duration: 0.1)) {
                                    showCaptureFlash = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        showCaptureFlash = false
                                    }
                                }
                                captureCount += 1
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 64, height: 64)
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 72, height: 72)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 30)
                        }

                        Spacer()
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .onAppear {
                MacPrivacyCoordinator.shared.beginTrustedModal()
                model.checkPermissions()
            }
            .onDisappear {
                MacPrivacyCoordinator.shared.endTrustedModal()
                model.stopSession()
            }
            .onReceive(model.$cameraError) { error in
                cameraErrorMessage = error
            }
            .alert(
                "Camera Unavailable",
                isPresented: Binding(
                    get: { cameraErrorMessage != nil },
                    set: { newValue in
                        if !newValue {
                            cameraErrorMessage = nil
                            model.cameraError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    cameraErrorMessage = nil
                    model.cameraError = nil
                }
            } message: {
                Text(cameraErrorMessage ?? "The camera cannot be used right now.")
            }
        }
    }

    enum CaptureMode {
        case photo
        case video
    }

    class CameraModel: NSObject, ObservableObject {
        let session: AVCaptureSession? = AVCaptureSession()

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(deviceDisconnected),
                name: .AVCaptureDeviceWasDisconnected,
                object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceWasDisconnected, object: nil)
        }
        private let photoOutput = AVCapturePhotoOutput()
        private let movieOutput = AVCaptureMovieFileOutput()
        // Use a static queue to ensure serial access across all CameraModel instances
        private static let sharedSessionQueue = DispatchQueue(label: "biz.front-end.encryptedalbum.camera.session")
        private var sessionQueue: DispatchQueue { Self.sharedSessionQueue }

        @Published var isAuthorized = false
        @Published var captureMode: CaptureMode = .photo
        @Published var isRecording = false
        @Published var recordingDuration: TimeInterval? = nil
        @Published var cameraError: String?
        @Published var torchAvailable: Bool = false
        @Published var torchOn: Bool = false

        private var recordingTimer: Timer?
        private var recordingStartTime: Date?

        func checkPermissions() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.isAuthorized = true
                setupSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        self.isAuthorized = granted
                        if granted { self.setupSession() }
                    }
                }
            default:
                self.isAuthorized = false
            }
            // Check audio (microphone) permissions separately so we can
            // request permission and include audio input in the session when
            // possible. Add defensive logging to help diagnose macOS 'Cannot Record' issues.
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                AppLog.debugPrivate("CameraModel: microphone access authorized")
            case .notDetermined:
                AppLog.debugPrivate("CameraModel: microphone access notDetermined; requesting access")
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        AppLog.debugPrivate("CameraModel: microphone access request finished granted=\(granted)")
                        // If we already had camera authorization and we just obtained audio
                        // permission, try to reconfigure the session to add audio input.
                        if granted {
                            self.sessionQueue.async { [weak self] in
                                guard let self = self else { return }
                                if let s = self.session, s.inputs.isEmpty == false {
                                    // re-run setupSession to add audio input if possible
                                    self.setupSession()
                                }
                            }
                        }
                    }
                }
            default:
                AppLog.debugPrivate("CameraModel: microphone access denied or restricted")
            }
        }

        // MARK: - Notification Handlers
        @objc private func deviceDisconnected(notification: Notification) {
            guard let device = notification.object as? AVCaptureDevice else { return }
            AppLog.debugPublic("Camera device disconnected: \(device.localizedName)")
            handleCameraError("Camera device disconnected. Please reconnect your camera.")
        }

        func setupSession() {
            sessionQueue.async {
                guard let session = self.session else { return }

                if !session.inputs.isEmpty {
                    if !session.isRunning {
                        session.startRunning()
                    }
                    return
                }

                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.handleCameraError("No camera device is available. Connect one and try again.")
                    return
                }

                // Keep a reference to the selected device so we can toggle torch later
                self.selectedDevice = device

                // Add this check to ensure the device is connected
                guard device.isConnected else {
                    self.handleCameraError("Camera device is not connected. Please check your camera.")
                    return
                }

                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    self.handleCameraError("Failed to create a camera input. Check permissions.")
                    return
                }

                session.beginConfiguration()

                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    session.commitConfiguration()
                    self.handleCameraError("Cannot add the camera input to this session.")
                    return
                }

                if session.canAddOutput(self.photoOutput) {
                    session.addOutput(self.photoOutput)
                } else {
                    self.handleCameraError("Cannot add photo output to the capture session.")
                }

                // Attempt to include audio input into the session when microphone
                // access is authorized. This avoids failing later when recording
                // expects audio input.
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                    if let audioDevice = AVCaptureDevice.default(for: .audio) {
                        if let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                            if session.canAddInput(audioInput) {
                                session.addInput(audioInput)
                                AppLog.debugPrivate(
                                    "CameraModel: added audio input \(audioDevice.localizedName) to session")
                            } else {
                                AppLog.debugPrivate("CameraModel: cannot add audio input to session")
                            }
                        } else {
                            AppLog.debugPrivate(
                                "CameraModel: failed to create audio input for device \(audioDevice.localizedName)")
                        }
                    } else {
                        AppLog.debugPrivate("CameraModel: no default audio device available to add")
                    }
                } else {
                    AppLog.debugPrivate("CameraModel: microphone access not authorized - skipping audio input")
                }

                if session.canAddOutput(self.movieOutput) {
                    session.addOutput(self.movieOutput)
                } else {
                    self.handleCameraError("Cannot add video output to the capture session.")
                }

                session.commitConfiguration()

                // Publish torch availability initial state on main thread
                DispatchQueue.main.async {
                    self.torchAvailable = device.hasTorch
                    if device.hasTorch {
                        self.torchOn = device.isTorchActive
                    } else {
                        self.torchOn = false
                    }
                }

                session.startRunning()

                DispatchQueue.main.async {
                    if !session.isRunning {
                        self.handleCameraError("The camera session failed to start.")
                    } else {
                        self.cameraError = nil
                        self.isAuthorized = true
                    }
                }
            }
        }

        func stopSession() {
            guard let session = self.session else { return }

            // Invalidate timer on Main immediately, as it was created on Main
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingStartTime = nil

            // Keep session alive until async block finishes
            sessionQueue.async { [weak self] in
                if self?.movieOutput.isRecording == true {
                    self?.movieOutput.stopRecording()
                }

                if session.isRunning {
                    session.stopRunning()
                }

                // We do not need to explicitly remove inputs/outputs here.
                // If the session is deallocated, they are removed.
                // If the session is reused, we want them to stay.
                // Removing them explicitly can cause race conditions if another session is starting up on the same device.
            }

            DispatchQueue.main.async { [weak self] in
                self?.isRecording = false
                self?.recordingDuration = nil
            }
        }

        private func handleCameraError(_ message: String) {
            DispatchQueue.main.async {
                self.cameraError = message
                self.isAuthorized = false
            }
        }

        private var selectedDevice: AVCaptureDevice? = nil

        /// Toggle torch/flash state if the current device supports it.
        func toggleTorch() {
            sessionQueue.async { [weak self] in
                guard let self = self, let device = self.selectedDevice, device.hasTorch else { return }
                do {
                    try device.lockForConfiguration()
                    if device.isTorchActive {
                        device.torchMode = .off
                    } else {
                        // Default to level 1.0 (full) if available
                        if device.isTorchModeSupported(.on) {
                            try device.setTorchModeOn(level: 1.0)
                        } else {
                            device.torchMode = .on
                        }
                    }
                    device.unlockForConfiguration()
                    DispatchQueue.main.async {
                        self.torchOn = device.isTorchActive
                    }
                } catch {
                    AppLog.debugPrivate("CameraModel: failed to toggle torch: \(error.localizedDescription)")
                }
            }
        }

        func capturePhoto(albumManager: AlbumManager, completion: @escaping () -> Void) {
            let settings = AVCapturePhotoSettings()
            self.photoCompletion = completion
            self.albumManager = albumManager
            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        func startRecording() {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "video_\(Date().timeIntervalSince1970).mov")
            AppLog.debugPrivate("CameraModel: starting recording to temp URL: \(tempURL.path)")
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)

            // Quick confirmation check; this may not change until delegate callbacks, but useful for diagnostics
            // surface this boolean as public debug so it's visible in Console
            AppLog.debugPublic("CameraModel: movieOutput.isRecording after start call = \(movieOutput.isRecording)")

            // Diagnostics: log audio permission and inputs so we can better interpret
            // 'Cannot Record' failures that appear to come from lower level audio stack.
            let audioAuth = AVCaptureDevice.authorizationStatus(for: .audio)
            // Surface authorization status as public debug so it's visible in Console
            // during diagnostics; it does not contain sensitive user data.
            AppLog.debugPublic("CameraModel: microphone authorization status = \(audioAuth.rawValue)")
            if let session = session {
                let inputNames = session.inputs.compactMap { (inp) -> String? in
                    if let deviceInput = inp as? AVCaptureDeviceInput {
                        return deviceInput.device.localizedName
                    }
                    return String(describing: type(of: inp))
                }
                // Device names are not secrets and are helpful for debug; publish
                // them so Console shows which inputs were attached.
                AppLog.debugPublic("CameraModel: session inputs = \(inputNames)")
            }

            recordingStartTime = Date()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                DispatchQueue.main.async {
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }

            DispatchQueue.main.async {
                self.isRecording = true
            }
        }

        func stopRecording(albumManager: AlbumManager, completion: @escaping () -> Void) {
            self.videoCompletion = completion
            self.albumManager = albumManager
            AppLog.debugPrivate("CameraModel: requesting stopRecording (isRecording=\(movieOutput.isRecording))")
            movieOutput.stopRecording()

            recordingTimer?.invalidate()
            recordingTimer = nil
            recordingStartTime = nil

            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingDuration = nil
            }
        }

        private var photoCompletion: (() -> Void)?
        private var videoCompletion: (() -> Void)?
        private var albumManager: AlbumManager?
    }

    extension CameraModel: AVCapturePhotoCaptureDelegate {
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?)
        {
            defer {
                DispatchQueue.main.async {
                    self.photoCompletion?()
                }
            }

            guard let data = photo.fileDataRepresentation() else {
                AppLog.error("CameraModel: photoOutput did not produce file data")
                return
            }

            let filename = "Capture_\(Date().timeIntervalSince1970).jpg"

            Task {
                do {
                    guard let albumManager = albumManager else {
                        AppLog.error("No albumManager available to handle captured photo")
                        return
                    }
                    AppLog.debugPrivate("CameraModel: saving captured photo via albumManager")
                    try await albumManager.handleCapturedMedia(
                        mediaSource: .data(data),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Album",
                        assetIdentifier: nil,
                        mediaType: .photo,
                        duration: nil,
                        location: nil,
                        isFavorite: nil
                    )
                } catch {
                    AppLog.error("Failed to handle captured photo: \(error.localizedDescription)")
                }
            }
        }
    }

    extension CameraModel: AVCaptureFileOutputRecordingDelegate {
        func fileOutput(
            _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
            from connections: [AVCaptureConnection], error: Error?
        ) {
            defer {
                DispatchQueue.main.async {
                    self.videoCompletion?()
                }
            }

            if let error = error {
                let nsErr = error as NSError
                AppLog.error(
                    "Video recording error: \(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) userInfo=\(nsErr.userInfo)"
                )

                if FileManager.default.fileExists(atPath: outputFileURL.path) {
                    if let attr = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
                        let size = attr[.size]
                    {
                        AppLog.debugPrivate(
                            "CameraModel: recorded file present despite error — size=\(size) path=\(outputFileURL.path)"
                        )
                    } else {
                        AppLog.debugPrivate(
                            "CameraModel: recorded file present despite error — path=\(outputFileURL.path)")
                    }
                } else {
                    AppLog.debugPrivate("CameraModel: no recorded file exists at path \(outputFileURL.path)")
                }

                return
            }

            // macOS recording path: we always receive an outputFileURL
            // (no UIImagePicker-style `info` dictionary), so skip any
            // imageURL handling here and process the recorded file below.

            let filename = "Video_\(Date().timeIntervalSince1970).mov"

            Task {
                guard let albumManager = albumManager else {
                    AppLog.error("No albumManager available to handle captured video")
                    return
                }
                AppLog.debugPrivate("CameraModel: saving recorded video via albumManager")
                let asset = AVAsset(url: outputFileURL)
                var duration: TimeInterval?
                if #available(macOS 13.0, *) {
                    if let loadedDuration = try? await asset.load(.duration) {
                        duration = loadedDuration.seconds
                    }
                } else {
                    duration = asset.duration.seconds
                }

                do {
                    try await albumManager.handleCapturedMedia(
                        mediaSource: .fileURL(outputFileURL),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Album",
                        assetIdentifier: nil,
                        mediaType: .video,
                        duration: duration,
                        location: nil,
                        isFavorite: nil
                    )
                } catch {
                    AppLog.error("Failed to handle captured video: \(error.localizedDescription)")
                }
                // Always attempt to remove the temporary file
                do {
                    try FileManager.default.removeItem(at: outputFileURL)
                    AppLog.debugPrivate("CameraModel: removed temporary recorded file at \(outputFileURL.path)")
                } catch {
                    AppLog.debugPrivate(
                        "CameraModel: failed to remove temp recorded file: \(error.localizedDescription)")
                }
                // No outer error handler needed; inner do/catch blocks handle failures.
            }
        }

        func fileOutput(
            _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]
        ) {
            // Keep the recorded file path private (it may include user-specific
            // paths) but publish a public message so we can see recording start
            // events in Console without special filtering.
            AppLog.debugPublic("CameraModel: didStartRecording")

            // Log whether the file is actually being written yet and attempt to
            // detect early failures due to file permissions or audio device issues.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path), let size = attr[.size] {
                    AppLog.debugPrivate(
                        "CameraModel: recording file exists at start — size=\(size) path=\(fileURL.path)")
                } else {
                    AppLog.debugPrivate("CameraModel: recording file exists at start — path=\(fileURL.path)")
                }
            } else {
                AppLog.debugPrivate(
                    "CameraModel: recording file did not exist immediately at start (this can be normal) — path=\(fileURL.path)"
                )
            }

            // Log connection ports available (helpful to see audio/video presence)
            let portNames = connections.flatMap { conn -> [String] in
                conn.inputPorts.map { "\($0.mediaType.rawValue)" }
            }
            AppLog.debugPrivate("CameraModel: connection ports = \(portNames)")
        }
    }

    class PreviewView: NSView {
        override func layout() {
            super.layout()
            // Keep the preview layer fully sized to the view bounds.
            // Setting bounds and position avoids partial clipping when window changes size
            // (fixes issue where only the top half was visible when rotated/resized).
            // Ensure the preview sublayer (if present) always matches view bounds.
            if let previewLayer = self.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.frame = self.bounds
                previewLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
                previewLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
                previewLayer.needsDisplayOnBoundsChange = true
                // Ensure video orientation follows view aspect (portrait vs. landscape)
                if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                    let bounds = self.bounds
                    if bounds.width >= bounds.height {
                        connection.videoOrientation = .landscapeRight
                    } else {
                        connection.videoOrientation = .portrait
                    }
                }
                CATransaction.commit()
            }
        }
    }

    struct CameraPreview: NSViewRepresentable {
        let session: AVCaptureSession

        func makeNSView(context: Context) -> NSView {
            let view = PreviewView()
            view.wantsLayer = true

            // Create a preview layer and add it as a sublayer so we can safely
            // keep the view's own layer for other system-managed content.
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

            view.layer?.addSublayer(previewLayer)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            // Ensure the preview sublayer (if present) matches the view's bounds during layout updates
            if let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.frame = nsView.bounds
                previewLayer.position = CGPoint(x: nsView.bounds.midX, y: nsView.bounds.midY)
                previewLayer.needsDisplayOnBoundsChange = true
                // Align preview orientation with view aspect ratio so it doesn't remain landscape-only
                if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                    let b = nsView.bounds
                    connection.videoOrientation = (b.width >= b.height) ? .landscapeRight : .portrait
                }
                CATransaction.commit()
            }
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
            // Remove the preview sublayer if we added it.
            if let previewLayer = nsView.layer?.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) {
                previewLayer.removeFromSuperlayer()
            }
        }
    }
#endif
