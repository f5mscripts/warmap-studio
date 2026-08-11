import Combine
import Foundation
import QuartzCore

/// Drives the playhead.
///
/// Time advances from `CADisplayLink` deltas rather than by counting frames, so
/// playback stays true to wall-clock speed even when a frame takes too long — and,
/// because the evaluator is a pure function of time, a dropped frame changes nothing
/// about what is drawn next.
@MainActor
public final class PlaybackController: ObservableObject {

    @Published public private(set) var time: TimeInterval = 0
    @Published public private(set) var isPlaying = false
    @Published public var speed: Double = 1.0
    @Published public var loops: Bool = true

    public var duration: TimeInterval = 30 {
        didSet { time = min(time, duration) }
    }

    public static let speedOptions: [Double] = [0.25, 0.5, 1, 2, 4]

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    public init() {}

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Transport

    public func play() {
        guard !isPlaying else { return }
        if time >= duration - 0.001 { time = 0 }
        isPlaying = true
        lastTimestamp = nil

        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func pause() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    public func seek(to newTime: TimeInterval) {
        time = min(max(newTime, 0), duration)
    }

    public func rewindToStart() {
        seek(to: 0)
    }

    public func step(by delta: TimeInterval) {
        seek(to: time + delta)
    }

    /// Jump the playhead to a historical date.
    public func jump(to date: HistoricalDate, in timeline: Timeline) {
        seek(to: timeline.time(for: date))
    }

    fileprivate func advance(to timestamp: CFTimeInterval) {
        guard isPlaying else { return }
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp else { return }

        // Clamp the delta so returning from the background does not jump the
        // playhead half a minute forward.
        let delta = min(timestamp - last, 0.1) * speed
        let next = time + delta

        if next >= duration {
            if loops {
                time = next.truncatingRemainder(dividingBy: max(duration, 0.001))
            } else {
                time = duration
                pause()
            }
        } else {
            time = next
        }
    }
}

/// `CADisplayLink` retains its target, so the proxy keeps the controller weak and
/// lets it deallocate normally.
private final class DisplayLinkProxy {
    weak var controller: PlaybackController?

    init(_ controller: PlaybackController) {
        self.controller = controller
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            controller?.advance(to: link.timestamp)
        }
    }
}
