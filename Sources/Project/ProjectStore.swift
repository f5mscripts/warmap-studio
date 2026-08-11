import Foundation
import UIKit

/// Reads and writes `.warmap` projects.
///
/// A `.warmap` is a directory package, not a zip:
///
///     WW2 Europe — Demo.warmap/
///       project.json      the whole document
///       thumbnail.png     dashboard preview, regenerated on save
///       audio/            imported audio, copied in so the project is portable
///       assets/           imported images (custom flags, logos)
///
/// A package keeps imported media as ordinary files — no archive to unpack before
/// `AVAssetWriter` can read a track, and a half-finished write can never corrupt an
/// otherwise good archive. Everything lives in the app's Documents directory, so
/// nothing leaves the device unless the user shares it.
public final class ProjectStore: @unchecked Sendable {

    public static let shared = ProjectStore()

    public static let fileExtension = "warmap"
    private static let documentName = "project.json"
    private static let thumbnailName = "thumbnail.png"

    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init() {}

    // MARK: - Locations

    public var projectsDirectory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Projects", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public func packageURL(for project: WarMapProject) -> URL {
        projectsDirectory
            .appendingPathComponent(sanitise(project.name) + "-" + project.id.uuidString.prefix(8))
            .appendingPathExtension(Self.fileExtension)
    }

    public func audioDirectory(in package: URL) -> URL {
        package.appendingPathComponent("audio", isDirectory: true)
    }

    public func assetsDirectory(in package: URL) -> URL {
        package.appendingPathComponent("assets", isDirectory: true)
    }

    /// Strips anything that would be awkward in a file name while keeping the name
    /// recognisable in the Files app.
    private func sanitise(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let joined = String(cleaned).trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Project" : String(joined.prefix(60))
    }

    // MARK: - Listing

    /// Reads just enough of each package to populate the dashboard.
    public func listProjects() -> [ProjectSummary] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let summaries = contents
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { summary(at: $0) }

        return summaries.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func summary(at package: URL) -> ProjectSummary? {
        let documentURL = package.appendingPathComponent(Self.documentName)
        guard let data = try? Data(contentsOf: documentURL),
              let project = try? decoder.decode(WarMapProject.self, from: data) else {
            return nil
        }
        let thumbnail = package.appendingPathComponent(Self.thumbnailName)
        return ProjectSummary(
            id: project.id,
            name: project.name,
            subtitle: project.subtitle,
            periodLabel: project.periodLabel,
            era: project.era,
            modifiedAt: project.modifiedAt,
            url: package,
            thumbnailURL: fileManager.fileExists(atPath: thumbnail.path) ? thumbnail : nil
        )
    }

    // MARK: - Load and save

    public func load(from package: URL) throws -> WarMapProject {
        let documentURL = package.appendingPathComponent(Self.documentName)
        let data: Data
        do {
            data = try Data(contentsOf: documentURL)
        } catch {
            throw WarMapError.projectCorrupt(name: package.lastPathComponent,
                                             detail: "project.json is missing or unreadable")
        }
        do {
            return try decoder.decode(WarMapProject.self, from: data)
        } catch let error as WarMapError {
            throw error
        } catch {
            throw WarMapError.projectCorrupt(name: package.lastPathComponent,
                                             detail: String(describing: error))
        }
    }

    /// Writes a project, replacing any previous copy.
    ///
    /// The document is written to a sibling file and then swapped in, so an
    /// interrupted save leaves the previous version intact rather than a truncated
    /// one — the difference between "your last edit is missing" and "your project is
    /// gone".
    @discardableResult
    public func save(_ project: WarMapProject, thumbnail: UIImage? = nil) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        var stamped = project
        stamped.modifiedAt = Date()

        let package = existingPackage(for: project.id) ?? packageURL(for: stamped)
        do {
            try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: audioDirectory(in: package),
                                            withIntermediateDirectories: true)
            try fileManager.createDirectory(at: assetsDirectory(in: package),
                                            withIntermediateDirectories: true)

            let data = try encoder.encode(stamped)
            let destination = package.appendingPathComponent(Self.documentName)
            let scratch = package.appendingPathComponent(Self.documentName + ".writing")
            try data.write(to: scratch, options: .atomic)
            _ = try fileManager.replaceItemAt(destination, withItemAt: scratch)

            if let thumbnail, let png = thumbnail.pngData() {
                try? png.write(to: package.appendingPathComponent(Self.thumbnailName),
                               options: .atomic)
            }
        } catch let error as WarMapError {
            throw error
        } catch {
            throw WarMapError.projectSaveFailed(detail: error.localizedDescription)
        }
        return package
    }

    /// Finds a project's package by id, so renaming a project does not orphan it.
    public func existingPackage(for id: UUID) -> URL? {
        listProjects().first { $0.id == id }?.url
    }

    // MARK: - Project management

    public func duplicate(_ summary: ProjectSummary) throws -> WarMapProject {
        var project = try load(from: summary.url)
        project.id = UUID()
        project.name = uniqueName(basedOn: project.name)
        project.createdAt = Date()
        project.modifiedAt = Date()

        let destination = packageURL(for: project)
        // Copy the package first so imported audio and assets come along, then
        // overwrite project.json with the new identity.
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: summary.url, to: destination)
        let data = try encoder.encode(project)
        try data.write(to: destination.appendingPathComponent(Self.documentName), options: .atomic)
        return project
    }

    private func uniqueName(basedOn name: String) -> String {
        let existing = Set(listProjects().map(\.name))
        guard existing.contains(name) else { return name }
        var index = 2
        while existing.contains("\(name) \(index)") { index += 1 }
        return "\(name) \(index)"
    }

    public func delete(_ summary: ProjectSummary) throws {
        do {
            try fileManager.removeItem(at: summary.url)
        } catch {
            throw WarMapError.projectSaveFailed(detail: "could not delete: \(error.localizedDescription)")
        }
    }

    // MARK: - Import and export

    /// Copies a `.warmap` from elsewhere (Files, AirDrop) into the library.
    public func importProject(from url: URL) throws -> WarMapProject {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var project = try load(from: url)
        // A fresh id so importing the same file twice gives two projects rather than
        // silently overwriting.
        project.id = UUID()
        project.name = uniqueName(basedOn: project.name)

        let destination = packageURL(for: project)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: url, to: destination)
        let data = try encoder.encode(project)
        try data.write(to: destination.appendingPathComponent(Self.documentName), options: .atomic)
        return project
    }

    /// Copies imported audio into the project package so the `.warmap` stays
    /// self-contained.
    public func importAudio(from url: URL, into package: URL) throws -> AudioClip {
        try AudioClip.validate(url: url)

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let directory = audioDirectory(in: package)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).\(url.pathExtension.lowercased())"
        let destination = directory.appendingPathComponent(filename)
        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw WarMapError.audioLoadFailed(name: url.lastPathComponent,
                                              detail: error.localizedDescription)
        }
        return AudioClip(name: url.deletingPathExtension().lastPathComponent,
                         relativePath: filename)
    }

    // MARK: - Coding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Readable on purpose: a .warmap should be inspectable and hand-fixable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
