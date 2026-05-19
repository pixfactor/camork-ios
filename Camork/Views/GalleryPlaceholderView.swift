import SwiftUI

struct GalleryPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_gallery_title",
            systemImage: "square.grid.2x2",
            description: Text("placeholder_gallery_description")
        )
    }
}
