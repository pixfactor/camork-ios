import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "placeholder_settings_title",
            systemImage: "gearshape",
            description: Text("placeholder_settings_description")
        )
    }
}
