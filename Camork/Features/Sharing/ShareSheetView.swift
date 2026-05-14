import SwiftUI
import UIKit

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = [
        .assignToContact,
        .addToReadingList,
        .openInIBooks
    ]
    var onCompletion: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            onCompletion?(activityType, completed, returnedItems, error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Convenience modifier to present share sheet from any view
extension View {
    func shareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        onCompletion: ((UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            ShareSheetView(activityItems: items, onCompletion: onCompletion)
                .presentationDetents([.medium, .large])
        }
    }
}
