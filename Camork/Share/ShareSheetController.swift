import SwiftUI
import UIKit

/// Thin SwiftUI bridge for the system share sheet.
///
/// `SharePreparer` owns file/text preparation and cleanup decisions. This wrapper only
/// presents `UIActivityViewController` and reports completion/cancel back to SwiftUI.
struct ShareSheetController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onCompletion: @Sendable () -> Void

    init(
        activityItems: [Any],
        onCompletion: @escaping @Sendable () -> Void
    ) {
        self.activityItems = activityItems
        self.onCompletion = onCompletion
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onCompletion()
        }
        return controller
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}
