import SwiftUI

struct CameraPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_camera_title",
            systemImage: "camera",
            description: Text("placeholder_camera_description")
        )
    }
}
