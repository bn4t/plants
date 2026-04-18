import SwiftUI
import UIKit

struct PlantPhotoView: View {
    let photoData: Data?
    var cornerRadius: CGFloat
    var fallbackSystemName: String

    init(
        photoData: Data?,
        cornerRadius: CGFloat = 16,
        fallbackSystemName: String = "leaf.fill"
    ) {
        self.photoData = photoData
        self.cornerRadius = cornerRadius
        self.fallbackSystemName = fallbackSystemName
    }

    var body: some View {
        Color.clear
            .overlay {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.systemGroupedBackground)
                        Image(systemName: fallbackSystemName)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
