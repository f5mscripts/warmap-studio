import CoreGraphics
import Foundation

/// Turns a `Timeline` and a point in time into a `WorldSnapshot`.
///
/// Evaluation is a *replay*: start from the initial state and apply every clip whose
/// start has passed, in order, clamping finished clips to their end state and
/// interpolating the one or two still in flight. That makes the result a pure
/// function of `(timeline, time)` — scrubbing backwards gives exactly the same frame
/// as playing forwards into it, and the export renderer, which jumps straight to
/// arbitrary times, cannot drift out of step with the preview.
///
/// Cost is linear in the number of clips before `time`, which for a few hundred
/// clips is far below a frame budget. If a project ever grows past that, the fix is
/// periodic checkpoints, not incremental mutation — determinism is worth more than
/// the constant factor.
public struct TimelineEvaluator: Sendable {

    public let timeline: Timeline
    /// Clips pre-sorted once, so evaluation does no sorting per frame.
    private let ordered: [TimelineItem]

    public init(timeline: Timeline) {
        self.timeline = timeline
        // Ties are broken by id so the order never depends on how the array was
        // built — two clips starting on the same frame must resolve identically
        // every run.
        self.ordered = timeline.items
            .filter(\.isEnabled)
            .sorted {
                $0.start == $1.start
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.start < $1.start
            }
    }

    public func snapshot(at time: TimeInterval) -> WorldSnapshot {
        let clampedTime = min(max(time, 0), timeline.duration)
        let date = timeline.date(at: clampedTime)

        var ownership = timeline.initialOwnership
        var cityOwners = timeline.initialCityOwners
        var contested: [String: ContestedTerritory] = [:]
        var armies = timeline.initialArmies
        var frontlines: [Frontline] = []
        var battles: [BattleMarker] = []
        var texts: [ResolvedText] = []
        var events: [WarEvent] = []
        var camera = timeline.initialCamera

        for item in ordered {
            guard clampedTime >= item.start else { break }  // ordered: nothing later applies
            let finished = clampedTime >= item.end
            let progress = item.progress(at: clampedTime)

            switch item.action {

            case .captureTerritory(let units, let attacker, let bearing):
                for unit in units {
                    if finished {
                        ownership[unit] = attacker
                        contested.removeValue(forKey: unit)
                    } else {
                        // The defender keeps the unit until the sweep completes; the
                        // renderer paints the captured fraction on top.
                        contested[unit] = ContestedTerritory(attackerID: attacker,
                                                             defenderID: ownership[unit],
                                                             progress: progress,
                                                             bearing: bearing)
                    }
                }

            case .transferTerritory(let units, let to):
                guard finished || item.duration == 0 else { break }
                for unit in units {
                    ownership[unit] = to
                    contested.removeValue(forKey: unit)
                }

            case .captureCity(let cityID, let by):
                if finished { cityOwners[cityID] = by }

            case .spawnArmy(let army):
                if !armies.contains(where: { $0.id == army.id }) {
                    armies.append(army)
                }

            case .moveArmy(let armyID, let destination):
                guard let index = armies.firstIndex(where: { $0.id == armyID }) else { break }
                if finished {
                    armies[index].position = destination
                } else {
                    // Interpolate from wherever the replay has already put it, so a
                    // chain of moves reads as one continuous march.
                    armies[index].position = Interpolate.coordinate(
                        armies[index].position, destination, progress
                    )
                }

            case .removeArmy(let armyID):
                if finished { armies.removeAll { $0.id == armyID } }

            case .showBattle(let marker):
                if clampedTime <= item.end || item.duration == 0 {
                    battles.append(marker)
                }

            case .showFrontline(let frontline):
                if !frontlines.contains(where: { $0.id == frontline.id }) {
                    frontlines.append(frontline)
                }

            case .moveFrontline(let frontlineID, let destination):
                guard let index = frontlines.firstIndex(where: { $0.id == frontlineID }) else { break }
                frontlines[index].points = finished
                    ? destination
                    : Interpolate.polyline(frontlines[index].points, destination, progress)

            case .hideFrontline(let frontlineID):
                if finished { frontlines.removeAll { $0.id == frontlineID } }

            case .cameraMove(let target):
                camera = finished ? target : MapCamera.interpolate(camera, target, progress)

            case .showText(let element):
                guard clampedTime <= item.end || item.duration == 0 else { break }
                let raw = item.duration > 0
                    ? min(max((clampedTime - item.start) / item.duration, 0), 1)
                    : 1
                texts.append(TextAnimator.resolve(element,
                                                  progress: raw,
                                                  date: date,
                                                  easing: item.easing))

            case .markEvent(let event):
                events.append(event)
            }
        }

        return WorldSnapshot(
            time: clampedTime,
            date: date,
            ownership: ownership,
            contested: contested,
            cityOwners: cityOwners,
            armies: armies,
            frontlines: frontlines,
            battles: battles,
            texts: texts,
            camera: camera,
            recentEvents: events.reversed()
        )
    }

    /// Snapshot at a historical date rather than a video time.
    public func snapshot(on date: HistoricalDate) -> WorldSnapshot {
        snapshot(at: timeline.time(for: date))
    }

    /// The frame times an export will render, so the exporter and any progress
    /// reporting agree on the count exactly.
    public func frameTimes(fps: Int) -> [TimeInterval] {
        let count = max(1, Int((timeline.duration * Double(fps)).rounded()))
        return (0..<count).map { Double($0) / Double(fps) }
    }
}
