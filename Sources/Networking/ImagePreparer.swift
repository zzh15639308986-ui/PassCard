import UIKit

struct PreparedImage {
    let data: Data
    let mime: String
    let originalBytes: Int
    let sentBytes: Int
    let wasDownscaled: Bool
}

/// Phone screenshots are 2-4 MB. The vision model bills by image tokens, so
/// shrinking the long edge before upload cuts both latency and cost.
enum ImagePreparer {
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.85

    static func prepare(_ data: Data) -> PreparedImage {
        guard let image = UIImage(data: data) else {
            return PreparedImage(data: data,
                                 mime: "image/jpeg",
                                 originalBytes: data.count,
                                 sentBytes: data.count,
                                 wasDownscaled: false)
        }

        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else {
            return PreparedImage(data: data,
                                 mime: "image/jpeg",
                                 originalBytes: data.count,
                                 sentBytes: data.count,
                                 wasDownscaled: false)
        }

        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (image.size.width * ratio).rounded(),
                            height: (image.size.height * ratio).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else {
            return PreparedImage(data: data,
                                 mime: "image/jpeg",
                                 originalBytes: data.count,
                                 sentBytes: data.count,
                                 wasDownscaled: false)
        }

        return PreparedImage(data: jpeg,
                             mime: "image/jpeg",
                             originalBytes: data.count,
                             sentBytes: jpeg.count,
                             wasDownscaled: ratio < 1)
    }
}
