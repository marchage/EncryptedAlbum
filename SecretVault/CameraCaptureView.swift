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
                    Spacer()
                    Button {
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

class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published var isAuthorized = false
    
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
        
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            print("❌ Cannot add camera input to session")
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
            return
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            print("❌ Cannot add photo output to session")
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
            if !self.session.isRunning {
                print("❌ Camera session failed to start")
                DispatchQueue.main.async {
                    self.isAuthorized = false
                }
            }
        }
    }
    
    func stopSession() {
        session.stopRunning()
    }
    
    func capturePhoto(vaultManager: VaultManager, completion: @escaping () -> Void) {
        let settings = AVCapturePhotoSettings()
        self.photoCompletion = completion
        self.vaultManager = vaultManager
        output.capturePhoto(with: settings, delegate: self)
    }
    
    private var photoCompletion: (() -> Void)?
    private var vaultManager: VaultManager?
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
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
