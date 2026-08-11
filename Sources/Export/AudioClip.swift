import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A piece of audio placed on the timeline.
///
/// WarMap Studio ships no music. Every clip points at a file the user imported,
/// stored inside the project package so a `.warmap` stays self-contained and
/// portable between devices.
public struct AudioClip: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Path relative to the project package's `audio/` directory.
    public var relativePath: String
    /// Where the clip starts on the timeline, in seconds.
    public var start: TimeInterval
    /// Seconds trimmed from the head of the source file.
    public var trimStart: TimeInterval
    /// Playback length. `nil` means "to the end of the source".
    public var duration: TimeInterval?
    /// 0…2. Above 1 boosts, which is occasionally what a quiet source needs.
    public var volume: Double
    public var fadeIn: TimeInterval
    public var fadeOut: TimeInterval
    public var isMuted: Bool

    public init(id: UUID = UUID(),
                name: String,
                relativePath: String,
                start: TimeInterval = 0,
                trimStart: TimeInterval = 0,
                duration: TimeInterval? = nil,
                volume: Double = 1.0,
                fadeIn: TimeInterval = 0,
                fadeOut: TimeInterval = 0,
                isMuted: Bool = false) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.start = start
        self.trimStart = trimStart
        self.duration = duration
        self.volume = min(max(volume, 0), 2)
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        self.isMuted = isMuted
    }

    /// The formats the importer accepts.
    public static let supportedTypes: [UTType] = [.mp3, .wav, .mpeg4Audio, .audio]

    public static let supportedExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "caf"]

    /// Validates an import before it is copied into the project.
    public static func validate(url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw WarMapError.unsupportedAudioFormat(fileExtension: ext.isEmpty ? "?" : ext)
        }
    }
}
