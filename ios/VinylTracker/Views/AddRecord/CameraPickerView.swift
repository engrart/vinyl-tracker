import SwiftUI
import UIKit

/// UIViewControllerRepresentable wrapper around UIImagePickerController.
/// Supports both .camera and .photoLibrary source types.
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    var sourceType: UIImagePickerController.SourceType = .camera

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate   = context.coordinator
        picker.allowsEditing = false
        // For label scans, portrait crop hints work well; leave unconstrained for covers
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Prefer the edited image if the user cropped; fall back to original
            if let edited = info[.editedImage] as? UIImage {
                parent.capturedImage = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.capturedImage = original
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
