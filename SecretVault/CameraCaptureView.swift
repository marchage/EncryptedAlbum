import SwiftUI
import AVKit
#if os(iOS)
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vaultManager: VaultManager
    
    func makeUIViewController(context: Context) -> CameraHostingController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        
        let host = CameraHostingController()
        host.cameraController = picker
        return host
    }
    
    func updateUIViewController(_ uiViewController: CameraHostingController, context: Context) {
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
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.dismiss()
            
            // Show warning about vault-only storage
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = UIAlertController(
                    title: "Captured to Vault Only",
                    message: "This photo/video is stored ONLY in the encrypted vault. It will NOT be in your Photos Library or iCloud Photos. Make sure your vault is backed up!",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {
                    rootVC.present(alert, animated: true)
                }
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                var data: Data?
                var filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                var mediaType: MediaType = .photo
                var duration: TimeInterval?
                
                if let image = info[.originalImage] as? UIImage,
                   let imageData = image.jpegData(compressionQuality: 0.9) {
                    data = imageData
                    filename = "Capture_\(Date().timeIntervalSince1970).jpg"
                    mediaType = .photo
                } else if let videoURL = info[.mediaURL] as? URL {
                    do {
                        data = try Data(contentsOf: videoURL)
                        filename = "Video_\(Date().timeIntervalSince1970).mov"
                        mediaType = .video
                        
                        // Get video duration
                        let asset = AVAsset(url: videoURL)
                        duration = asset.duration.seconds
                    } catch {
                        print("Failed to read video data: \(error)")
                    }
                }
                
                if let data = data {
                    do {
                        try self.parent.vaultManager.hidePhoto(
                            imageData: data,
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
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// Custom hosting controller that locks orientation to portrait while camera is active
class CameraHostingController: UIViewController {
    var cameraController: UIImagePickerController?
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let camera = cameraController, camera.parent == nil {
            addChild(camera)
            view.addSubview(camera.view)
            camera.view.frame = view.bounds
            camera.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            camera.didMove(toParent: self)
        }
    }
}
#endif
