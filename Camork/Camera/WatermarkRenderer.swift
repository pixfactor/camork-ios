import UIKit
import CoreLocation

enum WatermarkRenderer {
    static func applyWatermark(
        to imageData: Data,
        date: Date,
        location: CLLocation? = nil
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        let result = renderer.image { ctx in
            image.draw(at: .zero)

            let fontSize = max(14, image.size.width * 0.025)
            let margin = max(10, image.size.width * 0.022)
            let lineSpacing: CGFloat = max(4, image.size.width * 0.006)

            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
            shadow.shadowOffset = CGSize(width: 1, height: 1)
            shadow.shadowBlurRadius = 3

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.white,
                .shadow: shadow
            ]

            let dateString = DateFormatter.watermark.string(from: date)
            let dateSize = (dateString as NSString).size(withAttributes: attrs)
            let datePoint = CGPoint(
                x: image.size.width - dateSize.width - margin,
                y: image.size.height - dateSize.height - margin
            )
            (dateString as NSString).draw(at: datePoint, withAttributes: attrs)

            // Location line
            if let location = location {
                let locationString = formatLocation(location)
                let locSize = (locationString as NSString).size(withAttributes: attrs)
                let locPoint = CGPoint(
                    x: image.size.width - locSize.width - margin,
                    y: datePoint.y - locSize.height - lineSpacing
                )
                (locationString as NSString).draw(at: locPoint, withAttributes: attrs)
            }
        }

        return result.jpegData(compressionQuality: 0.92)
    }

    private static func formatLocation(_ location: CLLocation) -> String {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f°%@ %.4f°%@", abs(lat), latDir, abs(lon), lonDir)
    }
}
