import SwiftUI

struct RecordView: View {
    let coverArtId: String?
    let isPlaying: Bool
    var size: CGFloat = 300

    // Track accumulated rotation across pauses
    @State private var baseAngle: Double = 0
    @State private var playStartDate: Date? = nil
    private let degreesPerSecond: Double = 36.0  // 10 s per revolution

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            ZStack {
                vinylDisc
                AsyncArtwork(coverArtId: coverArtId, size: 300, cornerRadius: size)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .clipShape(Circle())
                // Spindle
                Circle()
                    .fill(Color(white: 0.5))
                    .frame(width: size * 0.04, height: size * 0.04)
                // Tonearm reflection glint
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size * 0.015, height: size * 0.015)
                    .offset(x: size * 0.04, y: -size * 0.04)
            }
            .rotationEffect(.degrees(angle(at: context.date)))
            .frame(width: size, height: size)
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                playStartDate = Date()
            } else {
                if let start = playStartDate {
                    baseAngle += Date().timeIntervalSince(start) * degreesPerSecond
                }
                playStartDate = nil
            }
        }
        .onAppear { if isPlaying { playStartDate = Date() } }
    }

    private func angle(at date: Date) -> Double {
        var angle = baseAngle
        if let start = playStartDate {
            angle += date.timeIntervalSince(start) * degreesPerSecond
        }
        return angle
    }

    private var vinylDisc: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.07))
                .shadow(color: .black.opacity(0.6), radius: 20)
            // Groove rings
            ForEach(0..<12, id: \.self) { i in
                let padding = size * 0.08 + CGFloat(i) * size * 0.028
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
                    .padding(padding)
            }
            // Label area (slightly lighter center ring)
            Circle()
                .fill(Color(white: 0.12))
                .padding(size * 0.32)
        }
    }
}
