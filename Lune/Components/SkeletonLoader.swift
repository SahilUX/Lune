import SwiftUI

struct SkeletonLoader: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shimmer(isActive: isAnimating)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonSongRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonLoader()
                .frame(width: 36, height: 36)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonLoader()
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonLoader()
                    .frame(height: 12)
                    .frame(maxWidth: 200, alignment: .leading)
            }

            Spacer()

            SkeletonLoader()
                .frame(width: 30, height: 14)
        }
        .padding(.vertical, 4)
    }
}

struct SkeletonPlaylistRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonLoader()
                .frame(width: 36, height: 36)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                SkeletonLoader()
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonLoader()
                    .frame(height: 12)
                    .frame(maxWidth: 100, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}

extension View {
    func shimmer(isActive: Bool) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

struct ShimmerModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white, location: 0.5),
                            .init(color: .white.opacity(0), location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        } else {
            content
        }
    }
}
