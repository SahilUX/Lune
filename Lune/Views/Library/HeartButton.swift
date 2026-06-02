import SwiftUI

struct HeartButton: View {
    let songId: String
    let initiallyStarred: Bool

    @State private var isStarred: Bool
    @State private var isBroken = false
    @State private var isAnimating = false   // true while any animation runs
    @State private var scale: CGFloat = 1
    @State private var shakeOffset: CGFloat = 0
    @State private var opacity: Double = 1

    init(song: Song) {
        self.songId = song.id
        self.initiallyStarred = song.isStarred
        self._isStarred = State(initialValue: song.isStarred)
    }

    var body: some View {
        Button { handleTap() } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .scaleEffect(scale)
                .offset(x: shakeOffset)
                .opacity(opacity)
                .contentTransition(.symbolEffect(.replace.downUp))
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        // Only sync external changes when we're not mid-animation
        .onChange(of: initiallyStarred) { _, new in
            guard !isAnimating else { return }
            isStarred = new
        }
    }

    private var iconName: String {
        if isBroken { return "heart.slash.fill" }
        return isStarred ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        if isBroken { return .red.opacity(0.7) }
        return isStarred ? .red : Color.secondary.opacity(0.5)
    }

    private func handleTap() {
        guard !isAnimating else { return }
        isStarred ? heartbreak() : favorite()
    }

    private func favorite() {
        isAnimating = true
        isStarred = true
        // Pop: overshoot → settle
        withAnimation(.spring(response: 0.22, dampingFraction: 0.3)) { scale = 1.65 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55).delay(0.16)) { scale = 1.0 }
        Task {
            try? await SubsonicClient.shared.star(id: songId)
            isAnimating = false
        }
    }

    private func heartbreak() {
        isAnimating = true
        Task {
            // Shake: left-right tremor
            let offsets: [CGFloat] = [7, -6, 5, -4, 3, -2, 0]
            for offset in offsets {
                withAnimation(.interactiveSpring(response: 0.055, dampingFraction: 0.25)) {
                    shakeOffset = offset
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            // Crack: switch to broken heart icon
            withAnimation(.easeIn(duration: 0.08)) { isBroken = true }
            // Brief pause so the user sees the broken heart
            try? await Task.sleep(for: .milliseconds(380))

            // Shatter: shrink + fade
            withAnimation(.easeOut(duration: 0.22)) {
                scale = 0.5
                opacity = 0
            }
            try? await Task.sleep(for: .milliseconds(230))

            // Reset invisibly, then fade back in as empty heart
            isBroken = false
            isStarred = false
            scale = 1
            withAnimation(.easeIn(duration: 0.18)) { opacity = 1 }

            try? await SubsonicClient.shared.unstar(id: songId)
            isAnimating = false
        }
    }
}
