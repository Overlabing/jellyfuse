import CoreImage.CIFilterBuiltins
import DesignSystem
import SwiftUI
import UIKit

/// QR code of a URL, drawn crisp (no interpolation) on a white tile so cameras read it on a dark UI.
struct QRCodeView: View {
    let url: URL
    let side: CGFloat

    var body: some View {
        Group {
            if let image = Self.render(url) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(Design.Spacing.s)
            }
        }
        .frame(width: side, height: side)
        .background(.white, in: RoundedRectangle(cornerRadius: Design.Radius.card))
        .accessibilityHidden(true)
    }

    private static func render(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
