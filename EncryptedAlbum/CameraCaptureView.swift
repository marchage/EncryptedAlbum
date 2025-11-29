import AVKit
import SwiftUI

#if os(iOS)
    import UIKit
    import Photos

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
            // Capture albumManager strongly in the coordinator so the async
            // save call can rely on it even after the picker / parent view is
            // dismissed. Avoids lost writes when the modal closes immediately.
            Coordinator(self, albumManager: albumManager)
        }

        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: CameraCaptureView
            // Strong reference to the environment object so async work can
            // continue after the parent view is dismissed
            let albumManagerRef: AlbumManager

            init(_ parent: CameraCaptureView, albumManager: AlbumManager) {
                self.parent = parent
                self.albumManagerRef = albumManager
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                // Handle the common case of file-backed media URLs synchronously so we
                // copy them to an app-owned temp file before dismissal. The picker may
                // remove its temporary files once dismissed, so we must materialize
                // a stable copy if we're handed a file URL.
                if let mediaURL = info[.mediaURL] as? URL {
                    let ext = mediaURL.pathExtension.isEmpty ? "mov" : mediaURL.pathExtension
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    do {
                        try FileManager.default.copyItem(at: mediaURL, to: tempURL)
                        // Proceed to process the copy asynchronously but only after we've
                        // made our own stable copy.
                        parent.dismiss()
                        Task.detached(priority: .userInitiated) {
                            do {
                                let mediaSource: MediaSource = .fileURL(tempURL)
                                let filename = "Video_\(Date().timeIntervalSince1970).\(ext)"
                                let asset = AVAsset(url: tempURL)
                                var duration: TimeInterval? = nil
                                if #available(iOS 16.0, *) {
                                    if let loaded = try? await asset.load(.duration) { duration = loaded.seconds }
                                } else {
                                    duration = asset.duration.seconds
                                }

                                try await self.albumManagerRef.handleCapturedMedia(
                                    mediaSource: mediaSource,
                                    filename: filename,
                                    dateTaken: Date(),
                                    sourceAlbum: "Captured to Album",
                                    assetIdentifier: nil,
                                    mediaType: .video,
                                    duration: duration,
                                    location: nil,
                                    isFavorite: nil,
                                    forceSaveToAlbum: true
                                )
                                AppLog.debugPublic("Handled captured media: \(filename)")
                                AppLog.debugPrivate("CameraCoordinator: Determined mediaSource=\(mediaSource) filename=\(filename) mediaType=video duration=\(String(describing: duration))")
                            } catch {
                                AppLog.error("Failed to handle captured media: \(error.localizedDescription)")
                                AppLog.debugPrivate("CameraCoordinator: Error handling captured video file at temp URL: \(tempURL.path)")
                            }
                        }
                    } catch {
                        AppLog.error("Failed to copy captured media to temp file: \(error.localizedDescription)")
                        parent.dismiss()
                    }
                    return
                }

                parent.dismiss()

                Task.detached(priority: .userInitiated) {
                    do {
                            AppLog.debugPrivate("CameraCoordinator: Received media info keys: \(info.keys)")
                        let (mediaSource, filename, mediaType, duration) = try await Self.makeMediaFromPickerInfo(info)

                        if let mediaSource = mediaSource {
                            do {
                                // Forward capture handling to AlbumManager helper which centralises
                                // the save-to-album vs save-to-photos behaviour and is testable.
                                try await self.albumManagerRef.handleCapturedMedia(
                                    mediaSource: mediaSource,
                                    filename: filename,
                                    dateTaken: Date(),
                                    sourceAlbum: "Captured to Album",
                                    assetIdentifier: nil,
                                    mediaType: mediaType,
                                    duration: duration,
                                    location: nil,
                                    isFavorite: nil,
                                    forceSaveToAlbum: true
                                )
                                AppLog.debugPublic("Handled captured media: \(filename)")
                                    AppLog.debugPrivate("CameraCoordinator: Determined mediaSource=\(mediaSource) filename=\(filename) mediaType=\(mediaType) duration=\(String(describing: duration))")
                            } catch {
                                    AppLog.error("Failed to handle captured media: \(error.localizedDescription)")
                                    // Record more context for debugging on-device
                                    AppLog.debugPrivate("CameraCoordinator: Error handling captured media for filename=\(filename) mediaType=\(mediaType) duration=\(String(describing: duration))")
                            }
                        }
                    } catch {
                        AppLog.error("Failed to extract captured media: \(error.localizedDescription)")
                    }
                }
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                parent.dismiss()
            }

            /// Extract a usable MediaSource / meta info from the UIImagePicker info dictionary.
            /// Returns a tuple containing mediaSource, filename, type and optional duration.
            static func makeMediaFromPickerInfo(_ info: [UIImagePickerController.InfoKey: Any]) async throws -> (MediaSource?, String, MediaType, TimeInterval?) {
                var mediaSource: MediaSource?
                var filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                var mediaType: MediaType = .photo
                var duration: TimeInterval?

                if let image = info[.originalImage] as? UIImage {
                    var imageData: Data? = image.jpegData(compressionQuality: 0.9)
                    if imageData == nil {
                        AppLog.debugPrivate("JPEG conversion failed for captured image; falling back to PNG")
                        imageData = image.pngData()
                    }
                    if let imageData = imageData {
                        mediaSource = .data(imageData)
                        filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                        mediaType = .photo
                    } else {
                        AppLog.error("Captured image had no usable data")
                    }

                } else if let videoURL = info[.mediaURL] as? URL {
                    mediaSource = .fileURL(videoURL)
                    filename = "Video_\(Date().timeIntervalSince1970).mov"
                    mediaType = .video

                    let asset = AVAsset(url: videoURL)
                    if #available(iOS 16.0, macOS 13.0, *) {
                        if let loadedDuration = try? await asset.load(.duration) {
                            duration = loadedDuration.seconds
                        }
                    } else {
                        duration = asset.duration.seconds
                    }

                } else if let imageURL = info[.imageURL] as? URL {
                    mediaSource = .fileURL(imageURL)
                    filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                    mediaType = .photo

                } else if let phAsset = info[.phAsset] as? PHAsset {
                    let dataFromAsset: Data? = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                        let options = PHImageRequestOptions()
                        options.isSynchronous = false
                        options.deliveryMode = .highQualityFormat
                        options.isNetworkAccessAllowed = true

                        PHImageManager.default().requestImageDataAndOrientation(for: phAsset, options: options) { data, _, _, _ in
                            cont.resume(returning: data)
                        }
                    }

                    if let assetData = dataFromAsset {
                        mediaSource = .data(assetData)
                        filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                        mediaType = .photo
                    } else {
                        AppLog.error("PHAsset returned no image data")
                    }

                } else {
                    AppLog.error("Captured media had no usable data")
                }

                return (mediaSource, filename, mediaType, duration)
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
                                AppLog.debugPrivate("CameraModel: added audio input \(audioDevice.localizedName) to session")
                            } else {
                                AppLog.debugPrivate("CameraModel: cannot add audio input to session")
                            }
                        } else {
                            AppLog.debugPrivate("CameraModel: failed to create audio input for device \(audioDevice.localizedName)")
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
                                isFavorite: nil,
                                forceSaveToAlbum: true
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
                AppLog.error("Video recording error: \(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) userInfo=\(nsErr.userInfo)")

                if FileManager.default.fileExists(atPath: outputFileURL.path) {
                    if let attr = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path), let size = attr[.size] {
                        AppLog.debugPrivate("CameraModel: recorded file present despite error — size=\(size) path=\(outputFileURL.path)")
                    } else {
                        AppLog.debugPrivate("CameraModel: recorded file present despite error — path=\(outputFileURL.path)")
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
                            isFavorite: nil,
                            forceSaveToAlbum: true
                        )
                    } catch {
                        AppLog.error("Failed to handle captured video: \(error.localizedDescription)")
                    }
                    // Always attempt to remove the temporary file
                    do {
                        try FileManager.default.removeItem(at: outputFileURL)
                        AppLog.debugPrivate("CameraModel: removed temporary recorded file at \(outputFileURL.path)")
                    } catch {
                        AppLog.debugPrivate("CameraModel: failed to remove temp recorded file: \(error.localizedDescription)")
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
                    AppLog.debugPrivate("CameraModel: recording file exists at start — size=\(size) path=\(fileURL.path)")
                } else {
                    AppLog.debugPrivate("CameraModel: recording file exists at start — path=\(fileURL.path)")
                }
            } else {
                AppLog.debugPrivate("CameraModel: recording file did not exist immediately at start (this can be normal) — path=\(fileURL.path)")
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
