import Foundation

/// Every failure the app can surface, with text written for the person using it.
///
/// Nothing in WarMap Studio fails silently: each case carries both what went wrong
/// and what the user can do next, so error alerts never bottom out in "unknown
/// error".
public enum WarMapError: LocalizedError, Equatable {
    case mapDataMissing(resource: String)
    case mapDataCorrupt(resource: String, detail: String)
    case projectCorrupt(name: String, detail: String)
    case projectVersionUnsupported(found: Int, supported: Int)
    case projectSaveFailed(detail: String)
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
    case unsupportedAudioFormat(fileExtension: String)
    case audioLoadFailed(name: String, detail: String)
    case exportFailed(stage: String, detail: String)
    case exportCancelled
    case renderFailed(detail: String)
    case photoLibraryDenied
    case scenarioGenerationFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .mapDataMissing(let resource):
            return "Missing map data “\(resource)”."
        case .mapDataCorrupt(let resource, _):
            return "The map data “\(resource)” could not be read."
        case .projectCorrupt(let name, _):
            return "“\(name)” could not be opened."
        case .projectVersionUnsupported(let found, let supported):
            return "This project was made with a newer version (format \(found); this build reads up to \(supported))."
        case .projectSaveFailed:
            return "The project could not be saved."
        case .insufficientStorage:
            return "Not enough storage to finish the export."
        case .unsupportedAudioFormat(let ext):
            return "“.\(ext)” audio isn’t supported."
        case .audioLoadFailed(let name, _):
            return "“\(name)” could not be loaded."
        case .exportFailed(let stage, _):
            return "Export failed while \(stage)."
        case .exportCancelled:
            return "Export cancelled."
        case .renderFailed:
            return "A frame could not be rendered."
        case .photoLibraryDenied:
            return "WarMap Studio can’t save to your photo library."
        case .scenarioGenerationFailed:
            return "The scenario could not be generated."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .mapDataMissing:
            return "Reinstall the app — this file ships inside the app bundle."
        case .mapDataCorrupt(_, let detail):
            return "Reinstall the app. Technical detail: \(detail)"
        case .projectCorrupt(_, let detail):
            return "Try duplicating the project from the dashboard, or open an earlier copy. Technical detail: \(detail)"
        case .projectVersionUnsupported:
            return "Update WarMap Studio, or open the project on the device that created it."
        case .projectSaveFailed(let detail):
            return "Check that your device has free space, then try again. Technical detail: \(detail)"
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "This export needs about \(formatter.string(fromByteCount: required)) but only \(formatter.string(fromByteCount: available)) is free. Free up space, or export at a lower resolution."
        case .unsupportedAudioFormat:
            return "Use an MP3, WAV, or M4A file."
        case .audioLoadFailed(_, let detail):
            return "The file may be damaged or copy-protected. Technical detail: \(detail)"
        case .exportFailed(_, let detail):
            return "Try again, or export at a lower resolution or frame rate. Technical detail: \(detail)"
        case .exportCancelled:
            return "No file was written."
        case .renderFailed(let detail):
            return "Try lowering the preview quality in Settings. Technical detail: \(detail)"
        case .photoLibraryDenied:
            return "Allow photo access in Settings › Privacy › Photos, or save the video to Files instead."
        case .scenarioGenerationFailed(let detail):
            return "Try rephrasing the description, or build the scenario by hand. Technical detail: \(detail)"
        }
    }

    /// Cancellation is a normal outcome, not something to alert about.
    public var isSilent: Bool { self == .exportCancelled }
}
