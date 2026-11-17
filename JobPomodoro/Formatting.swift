import Foundation

/// 05:30 형식
func clockString(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds.rounded(.up)), 0)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

/// 1시간 5분 / 42분 10초 형식
func durationString(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds), 0)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)시간 \(m)분" }
    if m > 0 { return s > 0 ? "\(m)분 \(s)초" : "\(m)분" }
    return "\(s)초"
}

func starString(_ value: Int) -> String {
    let v = min(max(value, 0), 5)
    return String(repeating: "★", count: v) + String(repeating: "☆", count: 5 - v)
}
