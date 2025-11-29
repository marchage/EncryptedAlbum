import AVKit
import SwiftUI

#if os(iOS)
    import UIKit

    struct CameraCaptureView: UIViewControllerRepresentable {
        @Environment(\.dismiss) var dismiss
        @EnvironmentObject var albumManager: AlbumManager

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.allowsEditing = false
            picker.modalPresentationStyle = .fullScreen

            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
            // No updates needed
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: CameraCaptureView

            init(_ parent: CameraCaptureView) {
                self.parent = parent
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                parent.dismiss()

                DispatchQueue.global(qos: .userInitiated).async {
                    var mediaSource: MediaSource?
                    var filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                    var mediaType: MediaType = .photo
                    var duration: TimeInterval?

                    if let image = info[.originalImage] as? UIImage,
                        let imageData = image.jpegData(compressionQuality: 0.9)
                    {
                        mediaSource = .data(imageData)
                        filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                        mediaType = .photo
                    } else if let videoURL = info[.mediaURL] as? URL {
                        mediaSource = .fileURL(videoURL)
                        filename = "Video_\(Date().timeIntervalSince1970).mov"
                        mediaType = .video

                        let asset = AVAsset(url: videoURL)
                        if #available(iOS 16.0, macOS 13.0, *) {
                            Task {
                                if let loadedDuration = try? await asset.load(.duration) {
                                    duration = loadedDuration.seconds
                                }
                            }
                        } else {
                            duration = asset.duration.seconds
                        }
                    }

                    if let mediaSource = mediaSource {
                        Task {
                            do {
                                // Forward capture handling to AlbumManager helper which centralises
                                // the save-to-album vs save-to-photos behaviour and is testable.
                                try await self.parent.albumManager.handleCapturedMedia(
                                    mediaSource: mediaSource,
                                    filename: filename,
                                    dateTaken: Date(),
                                    sourceAlbum: "Captured to Album",
                                    assetIdentifier: nil,
                                    mediaType: mediaType,
                                    duration: duration,
                                    location: nil,
                                    isFavorite: nil
                                )
                                AppLog.debugPublic("Handled captured media: \(filename)")
                            } catch {
                                AppLog.error("Failed to handle captured media: \(error.localizedDescription)")
                            }
                        }
                    }
                }

                }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                parent.dismiss()
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
                            // Video recording button
                            Button {
                                if model.isRecording {
                                    model.stopRecording(albumManager: albumManager) {
                                        // Keep camera open after recording
                                    }
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
                            .padding(.bottom, 30)

                            if model.isRecording, let duration = model.recordingDuration {
                                Text(String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60))
                                    .font(.system(.title2, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.bottom, 30)
                            }
                        } else {
                            // Photo capture button
                            Button {
                                model.capturePhoto(albumManager: albumManager) {
                                    // Keep camera open after capture
                                }
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

                if session.canAddOutput(self.movieOutput) {
                    session.addOutput(self.movieOutput)
                } else {
                    self.handleCameraError("Cannot add video output to the capture session.")
                }

                session.commitConfiguration()

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

        func capturePhoto(albumManager: AlbumManager, completion: @escaping () -> Void) {
            let settings = AVCapturePhotoSettings()
            self.photoCompletion = completion
            self.albumManager = albumManager
            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        func startRecording() {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "video_\(Date().timeIntervalSince1970).mov")
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)

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

            guard let data = photo.fileDataRepresentation() else { return }

            let filename = "Capture_\(Date().timeIntervalSince1970).jpg"

                    Task {
                        do {
                            guard let albumManager = albumManager else {
                                AppLog.error("No albumManager available to handle captured photo")
                                return
                            }
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
                AppLog.error("Video recording error: \(error.localizedDescription)")
                return
            }

            let filename = "Video_\(Date().timeIntervalSince1970).mov"

                    Task {
                do {
                    guard let albumManager = albumManager else {
                        AppLog.error("No albumManager available to handle captured video")
                        return
                    }
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
                    try? FileManager.default.removeItem(at: outputFileURL)
                } catch {
                    AppLog.error("Failed to save video: \(error.localizedDescription)")
                }
            }
        }

        func fileOutput(
            _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]
        ) {
            // Started recording
        }
    }

    class PreviewView: NSView {
        override func layout() {
            super.layout()
            // Keep the preview layer fully sized to the view bounds.
            // Setting bounds and position avoids partial clipping when window changes size
            // (fixes issue where only the top half was visible when rotated/resized).
            if let layer = self.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.bounds = self.bounds
                layer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
                layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
                layer.needsDisplayOnBoundsChange = true
                CATransaction.commit()
            }
        }
    }

    struct CameraPreview: NSViewRepresentable {
        let session: AVCaptureSession

        func makeNSView(context: Context) -> NSView {
            let view = PreviewView()
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            // Allow the preview layer to resize with the view
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer = previewLayer
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            // Ensure the preview layer matches the view's bounds during layout updates
            if let layer = nsView.layer as? AVCaptureVideoPreviewLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.bounds = nsView.bounds
                layer.position = CGPoint(x: nsView.bounds.midX, y: nsView.bounds.midY)
                layer.needsDisplayOnBoundsChange = true
                CATransaction.commit()
            }
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
            nsView.layer = nil
        }
    }
#endif
