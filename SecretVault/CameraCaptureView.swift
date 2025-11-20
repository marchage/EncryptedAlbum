import AVKit
import SwiftUI

#if os(iOS)
    import UIKit

    struct CameraCaptureView: UIViewControllerRepresentable {
        @Environment(\.dismiss) var dismiss
        @EnvironmentObject var vaultManager: VaultManager

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
                                try await self.parent.vaultManager.hidePhoto(
                                    mediaSource: mediaSource,
                                    filename: filename,
                                    dateTaken: Date(),
                                    sourceAlbum: "Captured to Vault",
                                    assetIdentifier: nil,
                                    mediaType: mediaType,
                                    duration: duration,
                                    location: nil,
                                    isFavorite: nil
                                )
                                print("✅ Captured to vault: \(filename)")
                            } catch {
                                print("❌ Failed to save to vault: \(error)")
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
        @EnvironmentObject var vaultManager: VaultManager
        @StateObject private var model = CameraModel()

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                if model.isAuthorized {
                    CameraPreview(session: model.session)
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
                                    model.stopRecording(vaultManager: vaultManager) {
                                        dismiss()
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
                                model.capturePhoto(vaultManager: vaultManager) {
                                    dismiss()
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
                model.checkPermissions()
            }
            .onDisappear {
                model.stopSession()
            }
        }
    }

    enum CaptureMode {
        case photo
        case video
    }

    class CameraModel: NSObject, ObservableObject {
        let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private let movieOutput = AVCaptureMovieFileOutput()
        private let sessionQueue = DispatchQueue(label: "com.secretvault.camera.session")
        @Published var isAuthorized = false
        @Published var captureMode: CaptureMode = .photo
        @Published var isRecording = false
        @Published var recordingDuration: TimeInterval? = nil

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

        func setupSession() {
            sessionQueue.async {
                guard let device = AVCaptureDevice.default(for: .video) else {
                    print("❌ No camera device available")
                    DispatchQueue.main.async {
                        self.isAuthorized = false
                    }
                    return
                }

                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    print("❌ Failed to create camera input")
                    DispatchQueue.main.async {
                        self.isAuthorized = false
                    }
                    return
                }

                self.session.beginConfiguration()

                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                } else {
                    print("❌ Cannot add camera input to session")
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.isAuthorized = false
                    }
                    return
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                } else {
                    print("❌ Cannot add photo output to session")
                }

                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                } else {
                    print("❌ Cannot add movie output to session")
                }

                self.session.commitConfiguration()

                self.session.startRunning()

                DispatchQueue.main.async {
                    if !self.session.isRunning {
                        print("❌ Camera session failed to start")
                        self.isAuthorized = false
                    }
                }
            }
        }

        func stopSession() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }
                self.session.commitConfiguration()

                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.recordingStartTime = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = false
                self?.recordingDuration = nil
            }
        }

        func capturePhoto(vaultManager: VaultManager, completion: @escaping () -> Void) {
            let settings = AVCapturePhotoSettings()
            self.photoCompletion = completion
            self.vaultManager = vaultManager
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

        func stopRecording(vaultManager: VaultManager, completion: @escaping () -> Void) {
            self.videoCompletion = completion
            self.vaultManager = vaultManager
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
        private var vaultManager: VaultManager?
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
                    try await vaultManager?.hidePhoto(
                        mediaSource: .data(data),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Vault",
                        assetIdentifier: nil,
                        mediaType: .photo,
                        duration: nil,
                        location: nil,
                        isFavorite: nil
                    )
                } catch {
                    print("Failed to save capture: \(error)")
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
                print("Video recording error: \(error)")
                return
            }

            let filename = "Video_\(Date().timeIntervalSince1970).mov"

            Task {
                do {
                    let asset = AVAsset(url: outputFileURL)
                    var duration: TimeInterval?
                    if #available(macOS 13.0, *) {
                        if let loadedDuration = try? await asset.load(.duration) {
                            duration = loadedDuration.seconds
                        }
                    } else {
                        duration = asset.duration.seconds
                    }

                    try await vaultManager?.hidePhoto(
                        mediaSource: .fileURL(outputFileURL),
                        filename: filename,
                        dateTaken: Date(),
                        sourceAlbum: "Captured to Vault",
                        assetIdentifier: nil,
                        mediaType: .video,
                        duration: duration,
                        location: nil,
                        isFavorite: nil
                    )

                    // Clean up temp file
                    try? FileManager.default.removeItem(at: outputFileURL)
                } catch {
                    print("Failed to save video: \(error)")
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
            self.layer?.frame = self.bounds
        }
    }

    struct CameraPreview: NSViewRepresentable {
        let session: AVCaptureSession

        func makeNSView(context: Context) -> NSView {
            let view = PreviewView()
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer = layer
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            // Session is already set on the layer
        }
    }
#endif
