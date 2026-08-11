import AVFoundation
import Foundation

/// A target format for the finished video.
public struct ExportPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var width: Int
    public var height: Int
    public var fps: Int
    /// Video bitrate in bits per second.
    public var bitrate: Int
    public var codec: ExportCodec

    public init(id: String, name: String, detail: String,
                width: Int, height: Int, fps: Int = 30,
                bitrate: Int? = nil, codec: ExportCodec = .h264) {
        self.id = id
        self.name = name
        self.detail = detail
        self.width = width
        self.height = height
        self.fps = fps
        // A reasonable default: roughly 0.1 bits per pixel per frame, which holds up
        // for map animation (large flat areas, occasional fast motion).
        self.bitrate = bitrate ?? Int(Double(width * height * fps) * 0.1)
        self.codec = codec
    }

    public var aspectRatio: Double { Double(width) / Double(height) }

    public var resolutionLabel: String { "\(width) × \(height)" }

    public var isPortrait: Bool { height > width }

    // MARK: - Built-in presets

    public static let tiktok = ExportPreset(
        id: "tiktok", name: "TikTok", detail: "1080 × 1920 · 9:16",
        width: 1080, height: 1920, fps: 30
    )

    public static let youtubeShorts = ExportPreset(
        id: "shorts", name: "YouTube Shorts", detail: "1080 × 1920 · 9:16",
        width: 1080, height: 1920, fps: 30
    )

    public static let youtube = ExportPreset(
        id: "youtube", name: "YouTube", detail: "1920 × 1080 · 16:9",
        width: 1920, height: 1080, fps: 30
    )

    public static let square = ExportPreset(
        id: "square", name: "Square", detail: "1080 × 1080 · 1:1",
        width: 1080, height: 1080, fps: 30
    )

    public static let builtIn: [ExportPreset] = [tiktok, youtubeShorts, youtube, square]

    /// A user-defined resolution, clamped to what the encoder will accept.
    public static func custom(width: Int, height: Int, fps: Int) -> ExportPreset {
        // H.264 requires even dimensions; odd values produce a green edge column.
        let w = max(64, min(width, 4096)) / 2 * 2
        let h = max(64, min(height, 4096)) / 2 * 2
        return ExportPreset(id: "custom", name: "Custom",
                            detail: "\(w) × \(h) · \(fps) fps",
                            width: w, height: h, fps: max(1, min(fps, 60)))
    }

    /// A rough estimate of the finished file size, used for the storage check.
    public func estimatedBytes(duration: TimeInterval) -> Int64 {
        // Video plus a generous allowance for audio and container overhead.
        Int64(Double(bitrate) / 8 * duration * 1.25) + 2_000_000
    }
}

public enum ExportCodec: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Widest compatibility. The right default for anything being uploaded.
    case h264
    /// Smaller files at the same quality, but not every tool ingests it.
    case hevc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

/// Where the render is up to. Reported on the main actor for the progress sheet.
public struct ExportProgress: Sendable, Equatable {
    public enum Stage: String, Sendable {
        case preparing
        case renderingFrames
        case mixingAudio
        case finalising
        case finished
    }

    public var stage: Stage
    /// 0…1 across the whole export.
    public var fraction: Double
    public var framesWritten: Int
    public var totalFrames: Int

    public init(stage: Stage, fraction: Double, framesWritten: Int = 0, totalFrames: Int = 0) {
        self.stage = stage
        self.fraction = min(max(fraction, 0), 1)
        self.framesWritten = framesWritten
        self.totalFrames = totalFrames
    }

    public var description: String {
        switch stage {
        case .preparing: return "Preparing…"
        case .renderingFrames: return "Rendering frame \(framesWritten) of \(totalFrames)"
        case .mixingAudio: return "Mixing audio…"
        case .finalising: return "Finalising…"
        case .finished: return "Done"
        }
    }
}
