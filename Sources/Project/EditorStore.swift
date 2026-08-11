import Combine
import Foundation
import SwiftUI

/// Owns the project being edited, and is the only thing allowed to change it.
///
/// Every mutation goes through `apply`, which snapshots the document, applies the
/// change, registers the inverse with `UndoManager` and schedules an autosave. That
/// gives undo for free on every operation — territory changes, army moves, event
/// deletion, timeline drags — rather than requiring each new feature to hand-write a
/// matching inverse and get it subtly wrong.
///
/// Snapshotting the whole document rather than diffing it is a deliberate trade: a
/// project is a few hundred kilobytes of value types, so a snapshot is cheap, and
/// correctness matters far more here than the memory saved.
@MainActor
public final class EditorStore: ObservableObject {

    public enum SaveState: Equatable {
        case saved
        case saving
        case unsaved
        case failed(String)

        public var label: String {
            switch self {
            case .saved: return "Saved"
            case .saving: return "Saving…"
            case .unsaved: return "Unsaved changes"
            case .failed: return "Save failed"
            }
        }
    }

    @Published public private(set) var project: WarMapProject
    @Published public private(set) var saveState: SaveState = .saved
    @Published public var lastError: WarMapError?

    /// Bumped whenever the document changes, so views can invalidate cheaply
    /// without comparing whole projects.
    @Published public private(set) var revision: Int = 0

    public let undoManager = UndoManager()
    private let store: ProjectStore
    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration

    public init(project: WarMapProject,
                store: ProjectStore = .shared,
                autosaveDelay: Duration = .milliseconds(1200)) {
        self.project = project
        self.store = store
        self.autosaveDelay = autosaveDelay
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = 100
    }

    // MARK: - Mutation

    /// Applies a change and makes it undoable.
    ///
    /// - Parameter name: what appears in "Undo Move Army".
    public func apply(_ name: String, _ mutate: (inout WarMapProject) -> Void) {
        let before = project
        var updated = project
        mutate(&updated)
        guard updated != before else { return }

        project = updated
        revision &+= 1

        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.restore(before, name: name)
            }
        }
        undoManager.setActionName(name)
        scheduleAutosave()
    }

    /// Restores a snapshot, registering the opposite direction so redo works.
    private func restore(_ snapshot: WarMapProject, name: String) {
        let current = project
        project = snapshot
        revision &+= 1
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.restore(current, name: name)
            }
        }
        undoManager.setActionName(name)
        scheduleAutosave()
    }

    public var canUndo: Bool { undoManager.canUndo }
    public var canRedo: Bool { undoManager.canRedo }

    public func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
    }

    public func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
    }

    // MARK: - Convenience mutations

    public func addTimelineItem(_ item: TimelineItem, name: String? = nil) {
        apply(name ?? "Add \(item.title)") { $0.activeTimeline.add(item) }
    }

    public func removeTimelineItem(id: UUID) {
        apply("Delete Item") { $0.activeTimeline.remove(id: id) }
    }

    public func updateTimelineItem(_ item: TimelineItem) {
        apply("Edit \(item.title)") { $0.activeTimeline.update(item) }
    }

    public func moveTimelineItem(id: UUID, to start: TimeInterval) {
        apply("Move Item") { project in
            guard var item = project.activeTimeline.items.first(where: { $0.id == id }) else { return }
            item.start = max(0, start)
            project.activeTimeline.update(item)
        }
    }

    public func setCountryColor(_ countryID: String, hex: String) {
        apply("Change Colour") { project in
            guard let index = project.countries.firstIndex(where: { $0.id == countryID }) else { return }
            project.countries[index].colorHex = hex
        }
    }

    public func setTerritoryOwner(_ unitID: String, to countryID: String) {
        apply("Change Owner") { project in
            project.activeTimeline.initialOwnership[unitID] = countryID
        }
    }

    public func createBranch(named name: String, at date: HistoricalDate, note: String = "") {
        apply("Create Branch") { project in
            let branch = project.branch(named: name, at: date, note: note)
            project.activeBranchID = branch.id
        }
    }

    public func switchToBranch(_ id: UUID?) {
        apply("Switch Timeline") { $0.activeBranchID = id }
    }

    public func setMapStyle(_ style: MapStyle) {
        apply("Change Map Style") { project in
            project.mapStyle = style
            project.renderStyle = .preset(style)
        }
    }

    // MARK: - Saving

    private func scheduleAutosave() {
        saveState = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self.saveNow()
        }
    }

    /// Writes immediately. Called by the autosave timer, and directly when the app
    /// is about to go to the background — the point at which a project must never be
    /// left only in memory.
    public func saveNow(thumbnail: UIImage? = nil) async {
        let snapshot = project
        saveState = .saving
        let store = self.store
        do {
            try await Task.detached(priority: .utility) {
                try store.save(snapshot, thumbnail: thumbnail)
            }.value
            saveState = .saved
        } catch let error as WarMapError {
            saveState = .failed(error.localizedDescription)
            lastError = error
        } catch {
            saveState = .failed(error.localizedDescription)
            lastError = .projectSaveFailed(detail: error.localizedDescription)
        }
    }

    /// Cancels any pending autosave and flushes synchronously-ish. Used on scene
    /// deactivation.
    public func flush() {
        autosaveTask?.cancel()
        Task { await saveNow() }
    }
}
