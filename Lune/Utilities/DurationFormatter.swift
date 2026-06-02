import Foundation

extension Int {
    var formattedAsDuration: String {
        let m = self / 60
        let s = self % 60
        return String(format: "%d:%02d", m, s)
    }

    var formattedAsLongDuration: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
