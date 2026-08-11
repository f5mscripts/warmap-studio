import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// Renders a project to an MP4.
///
/// Frames are drawn by the same `MapSceneRenderer` the editor uses, into a bitmap
/// context backed directly by the pixel buffer the encoder will consume — no
/// intermediate `UIImage`, no snapshotting of a live view. That is what makes the
/// exported video match the preview rather than approximate it.
///
/// Video is written first, then audio is mixed in as a second pass. Doing both in
/// one `AVAssetWriter` would mean interleaving audio sample buffers by hand;
/// composing afterwards gets volume ramps and trimming from `AVAudioMix` for free.
public actor VideoExporter {

    public struct Request: Sendable {
        public var timeline: Timeline
        public var countries: [String: Country]
        public var style: MapRenderStyle
        public var projection: MapProjectionKind
        public var preset: ExportPreset
        public var audioClips: [AudioClip]
        /// Directory holding the project's imported audio.
        public var audioDirectory: URL?

        public init(timeline: Timeline,
                    countries: [String: Country],
                    style: MapRenderStyle,
                    projection: MapProjectionKind = .mercator,
                    preset: ExportPreset,
                    audioClips: [AudioClip] = [],
                    audioDirectory: URL? = nil) {
            self.timeline = timeline
            self.countries = countries
            self.style = style
            self.projection = projection
            self.preset = preset
            self.audioClips = audioClips
            self.audioDirectory = audioDirectory
        }
    }

    private var isCancelled = false
    private let library: MapLibrary

    public init(library: MapLibrary = .shared) {
        self.library = library
    }

    public func cancel() {
        isCancelled = true
    }

    /// Renders and returns the finished file.
    ///
    /// - Parameter progress: called as the export advances. Not isolated to the main
    ///   actor — the caller decides where to hop.
    public func export(_ request: Request,
                       to destination: URL? = nil,
                       progress: @Sendable @escaping (ExportProgress) -> Void) async throws -> URL {
        isCancelled = false
        progress(ExportProgress(stage: .preparing, fraction: 0))

        let preset = request.preset
        let evaluator = TimelineEvaluator(timeline: request.timeline)
        let frameTimes = evaluator.frameTimes(fps: preset.fps)

        try checkStorage(for: preset, duration: request.timeline.duration)

        let videoOnlyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("warmap-video-\(UUID().uuidString).mp4")

        try await renderVideo(request: request,
                              evaluator: evaluator,
                              frameTimes: frameTimes,
                              to: videoOnlyURL,
                              progress: progress)

        if isCancelled {
            try? FileManager.default.removeItem(at: videoOnlyURL)
            throw WarMapError.exportCancelled
        }

        let audible = request.audioClips.filter { !$0.isMuted && $0.volume > 0 }
        let output = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("WarMap-\(Int(Date().timeIntervalSince1970)).mp4")

        guard !audible.isEmpty, let audioDirectory = request.audioDirectory else {
            // No audio: the video-only file is already the finished article.
            progress(ExportProgress(stage: .finalising, fraction: 0.97))
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: videoOnlyURL, to: output)
            progress(ExportProgress(stage: .finished, fraction: 1))
            return output
        }

        progress(ExportProgress(stage: .mixingAudio, fraction: 0.9))
        do {
            try await mix(videoURL: videoOnlyURL,
                          clips: audible,
                          audioDirectory: audioDirectory,
                          duration: request.timeline.duration,
                          to: output)
        } catch {
            try? FileManager.default.removeItem(at: videoOnlyURL)
            throw error
        }
        try? FileManager.default.removeItem(at: videoOnlyURL)

        progress(ExportProgress(stage: .finished, fraction: 1))
        return output
    }

    // MARK: - Video

    private func renderVideo(request: Request,
                             evaluator: TimelineEvaluator,
                             frameTimes: [TimeInterval],
                             to url: URL,
                             progress: @Sendable @escaping (ExportProgress) -> Void) async throws {

        let preset = request.preset
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw WarMapError.exportFailed(stage: "creating the output file",
                                           detail: error.localizedDescription)
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: preset.codec.avCodec,
            AVVideoWidthKey: preset.width,
            AVVideoHeightKey: preset.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: preset.bitrate,
                AVVideoExpectedSourceFrameRateKey: preset.fps,
                AVVideoMaxKeyFrameIntervalKey: preset.fps * 2,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: preset.width,
                kCVPixelBufferHeightKey as String: preset.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
            ]
        )

        guard writer.canAdd(input) else {
            throw WarMapError.exportFailed(stage: "configuring the encoder",
                                           detail: "the writer rejected the video input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw WarMapError.exportFailed(stage: "starting the encoder",
                                           detail: writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        let renderer = MapSceneRenderer(library: library)
        let viewport = CGSize(width: preset.width, height: preset.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue

        let total = frameTimes.count
        var index = 0
        var renderError: Error?

        // Drive the encoder from its own queue: it tells us when it can take more
        // data, and we render exactly that much. Pushing frames faster would just
        // balloon memory holding pixel buffers the encoder has not consumed.
        let queue = DispatchQueue(label: "studio.warmap.export.video")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if Task.isCancelled {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard index < total else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    guard let pool = adaptor.pixelBufferPool else {
                        renderError = WarMapError.exportFailed(
                            stage: "allocating frame buffers",
                            detail: "the encoder provided no pixel buffer pool"
                        )
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                          let pixelBuffer = buffer else {
                        renderError = WarMapError.exportFailed(
                            stage: "allocating frame buffers",
                            detail: "out of memory"
                        )
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    let time = frameTimes[index]
                    let snapshot = evaluator.snapshot(at: time)

                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    if let context = CGContext(
                        data: CVPixelBufferGetBaseAddress(pixelBuffer),
                        width: preset.width,
                        height: preset.height,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                        space: colorSpace,
                        bitmapInfo: bitmapInfo
                    ) {
                        // Core Video buffers are bottom-up; flip so the renderer's
                        // y-down coordinates land the right way round.
                        context.translateBy(x: 0, y: CGFloat(preset.height))
                        context.scaleBy(x: 1, y: -1)

                        let transform = MapTransform(projection: request.projection,
                                                     camera: snapshot.camera,
                                                     viewport: viewport)
                        do {
                            try renderer.render(snapshot, transform: transform,
                                                style: request.style,
                                                countries: request.countries,
                                                into: context)
                        } catch {
                            renderError = error
                        }
                    } else {
                        renderError = WarMapError.renderFailed(
                            detail: "could not create a drawing context for the frame"
                        )
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

                    if renderError != nil {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    let presentation = CMTime(value: CMTimeValue(index),
                                              timescale: CMTimeScale(preset.fps))
                    if !adaptor.append(pixelBuffer, withPresentationTime: presentation) {
                        renderError = WarMapError.exportFailed(
                            stage: "writing frame \(index)",
                            detail: writer.error?.localizedDescription ?? "the encoder rejected a frame"
                        )
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    index += 1
                    if index % 5 == 0 || index == total {
                        progress(ExportProgress(stage: .renderingFrames,
                                                fraction: 0.9 * Double(index) / Double(total),
                                                framesWritten: index,
                                                totalFrames: total))
                    }
                }
            }
        }

        if let renderError {
            writer.cancelWriting()
            throw renderError
        }
        if isCancelled || Task.isCancelled {
            writer.cancelWriting()
            throw WarMapError.exportCancelled
        }

        await writer.finishWriting()

        if writer.status != .completed {
            throw WarMapError.exportFailed(stage: "finalising the video",
                                           detail: writer.error?.localizedDescription
                                               ?? "writer status \(writer.status.rawValue)")
        }
    }

    // MARK: - Audio

    private func mix(videoURL: URL,
                     clips: [AudioClip],
                     audioDirectory: URL,
                     duration: TimeInterval,
                     to output: URL) async throws {

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WarMapError.exportFailed(stage: "mixing audio",
                                           detail: "the rendered video had no video track")
        }

        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                             of: videoTrack, at: .zero)

        var parameters: [AVMutableAudioMixInputParameters] = []

        for clip in clips {
            let url = audioDirectory.appendingPathComponent(clip.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw WarMapError.audioLoadFailed(name: clip.name,
                                                  detail: "the file is missing from the project")
            }
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw WarMapError.audioLoadFailed(name: clip.name,
                                                  detail: "no audio track in the file")
            }
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }

            let assetDuration = try await asset.load(.duration).seconds
            let available = max(0, assetDuration - clip.trimStart)
            // Never run past the end of the video or the end of the source file.
            let length = min(clip.duration ?? available, available, duration - clip.start)
            guard length > 0 else { continue }

            let range = CMTimeRange(
                start: CMTime(seconds: clip.trimStart, preferredTimescale: 600),
                duration: CMTime(seconds: length, preferredTimescale: 600)
            )
            let at = CMTime(seconds: clip.start, preferredTimescale: 600)
            do {
                try compositionAudio.insertTimeRange(range, of: sourceTrack, at: at)
            } catch {
                throw WarMapError.audioLoadFailed(name: clip.name,
                                                  detail: error.localizedDescription)
            }

            let input = AVMutableAudioMixInputParameters(track: compositionAudio)
            input.setVolume(Float(clip.volume), at: at)
            if clip.fadeIn > 0 {
                input.setVolumeRamp(
                    fromStartVolume: 0, toEndVolume: Float(clip.volume),
                    timeRange: CMTimeRange(start: at,
                                           duration: CMTime(seconds: min(clip.fadeIn, length),
                                                            preferredTimescale: 600))
                )
            }
            if clip.fadeOut > 0 {
                let fade = min(clip.fadeOut, length)
                let fadeStart = CMTime(seconds: clip.start + length - fade, preferredTimescale: 600)
                input.setVolumeRamp(
                    fromStartVolume: Float(clip.volume), toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart,
                                           duration: CMTime(seconds: fade, preferredTimescale: 600))
                )
            }
            parameters.append(input)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw WarMapError.exportFailed(stage: "mixing audio",
                                           detail: "could not create an export session")
        }
        session.audioMix = audioMix

        try? FileManager.default.removeItem(at: output)

        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: output, as: .mp4)
            } catch {
                throw WarMapError.exportFailed(stage: "mixing audio",
                                               detail: error.localizedDescription)
            }
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else {
                throw WarMapError.exportFailed(
                    stage: "mixing audio",
                    detail: session.error?.localizedDescription ?? "export did not complete"
                )
            }
        }
    }

    // MARK: - Storage

    /// Refuses to start an export that plainly will not fit, rather than failing
    /// three minutes in with a disk-full error.
    private func checkStorage(for preset: ExportPreset, duration: TimeInterval) throws {
        let required = preset.estimatedBytes(duration: duration)
        let values = try? FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        // Doubled because the video-only pass and the muxed output briefly coexist.
        guard available > required * 2 else {
            throw WarMapError.insufficientStorage(requiredBytes: required * 2,
                                                  availableBytes: available)
        }
    }
}
