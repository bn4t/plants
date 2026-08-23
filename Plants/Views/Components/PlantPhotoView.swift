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
        GeometryReader { geo in
            ZStack {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [BotanicalTheme.tint.opacity(0.07), BotanicalTheme.tint.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Image(systemName: fallbackSystemName)
                            .font(.system(size: min(geo.size.width, geo.size.height) * 0.18, weight: .semibold))
                            .foregroundStyle(BotanicalTheme.tint)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .opacity(photoData == nil ? 0 : 1)
            )
        }
        .clipped()
    }

}
