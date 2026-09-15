import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ProjectCore

public struct MediaInfo: Sendable {
    public let duration: Double
    public let width: Int
    public let height: Int
    public let audioTracks: Int
}

public enum MediaInspector {
    public static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProjectError("This file has no video track.") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displayed = CGRect(origin: .zero, size: size).applying(transform)
        return MediaInfo(duration: duration, width: Int(abs(displayed.width).rounded()), height: Int(abs(displayed.height).rounded()), audioTracks: try await asset.loadTracks(withMediaType: .audio).count)
    }
}

public struct PreparedComposition {
    public let asset: AVMutableComposition
    public let video: AVMutableVideoComposition
    public let audio: AVMutableAudioMix
}

public enum CompositionBuilder {
    // Each build transfers a fresh composition to its caller; mutable AVFoundation objects are never shared.
    public static func build(project: Project, source: URL, width: Int = 1920, height: Int = 1080, assets: [String: URL] = [:]) async throws -> sending PreparedComposition {
        try project.validate()
        let timeline = try project.makeTimeline()
        guard width > 0, height > 0, width <= 3840, height <= 3840 else { throw ProjectError("Unsupported render dimensions.") }
        let original = AVURLAsset(url: source)
        guard let video = try await original.loadTracks(withMediaType: .video).first else { throw ProjectError("Missing video track.") }
        let actualDuration = try await original.load(.duration).seconds
        guard abs(actualDuration - project.sourceDuration) < 0.1 else { throw ProjectError("The source duration no longer matches this project.") }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ProjectError("Cannot prepare the video track.") }
        videoTrack.preferredTransform = try await video.load(.preferredTransform)
        let audio = try await original.loadTracks(withMediaType: .audio)
        var audioPairs: [(AVAssetTrack, AVMutableCompositionTrack)] = []
        for track in audio {
            if let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) { audioPairs.append((track, destination)) }
        }
        for span in timeline.spans {
            let range = span.sourceInterval
            // A nominal 30 fps interval can contain multiple native source frames
            // (for example in a 60 fps import). Stretch only a single source tick.
            let duration = span.isHold ? CMTime(value: 1, timescale: 60000) : CMTime(seconds: range.duration, preferredTimescale: 60000)
            let sourceRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60000), duration: duration)
            let output = CMTime(seconds: span.outputInterval.start, preferredTimescale: 60000)
            try videoTrack.insertTimeRange(sourceRange, of: video, at: output)
            if span.hold != nil {
                videoTrack.scaleTimeRange(CMTimeRange(start: output, duration: sourceRange.duration), toDuration: CMTime(seconds: span.outputInterval.duration, preferredTimescale: 60000))
                continue // Freeze the picture; never stretch or repeat the original audio.
            }
            for (originalTrack, destination) in audioPairs {
                let available = try await originalTrack.load(.timeRange)
                let overlap = CMTimeRangeGetIntersection(available, otherRange: sourceRange)
                if overlap.isValid, overlap.duration > .zero {
                    try destination.insertTimeRange(overlap, of: originalTrack, at: output + overlap.start - sourceRange.start)
                }
            }
        }
        var mixParameters: [AVAudioMixInputParameters] = audioPairs.map { _, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(Float(project.sourceAudioVolume), at: .zero)
            return parameters
        }
        for placement in timeline.narrations {
            guard let narration = project.narrations.first(where: { $0.id == placement.narrationID }),
                  let path = narration.audioFile, let duration = narration.audioDuration else { continue }
            let url = try resolveAsset(path, source: source, assets: assets)
            let audioAsset = AVURLAsset(url: url)
            let actual = try await audioAsset.load(.duration).seconds
            guard actual.isFinite, abs(actual - duration) < 0.1,
                  let track = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                throw ProjectError("A narration file no longer matches its measured duration. Regenerate that segment.")
            }
            let available = try await track.load(.timeRange)
            guard available.duration.seconds >= duration - 0.1,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ProjectError("Cannot prepare a narration audio track.")
            }
            try destination.insertTimeRange(CMTimeRange(start: available.start, duration: min(available.duration, CMTime(seconds: duration, preferredTimescale: 60000))), of: track, at: CMTime(seconds: placement.outputStart, preferredTimescale: 60000))
            let parameters = AVMutableAudioMixInputParameters(track: destination)
            parameters.setVolume(Float(project.narrationVolume), at: .zero); mixParameters.append(parameters)
        }
        let audioMix = AVMutableAudioMix(); audioMix.inputParameters = mixParameters
        var cursorRenderer: CursorRenderer?
        if project.cursorMode == .separate {
            var customImage: CGImage?
            if let path = project.cursorStyle.imageFile {
                let url = try resolveAsset(path, source: source, assets: assets)
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetType(imageSource) as String? == UTType.png.identifier,
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                      let imageWidth = properties[kCGImagePropertyPixelWidth] as? Int,
                      let imageHeight = properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...2048).contains(imageWidth), (1...2048).contains(imageHeight),
                      let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw ProjectError("The custom cursor must be a PNG no larger than 2048×2048 pixels.")
                }
                customImage = decoded
            }
            cursorRenderer = try CursorRenderer(samples: project.cursor, style: project.cursorStyle, customImage: customImage)
        }
        let preparedCursor = cursorRenderer
        let preparedAnnotations = project.annotations.isEmpty ? nil : try AnnotationRenderer(
            annotations: project.annotations,
            sourceWidth: project.sourceWidth,
            sourceHeight: project.sourceHeight
        )
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let colors = project.background.colors.map { CIColor(red: $0.red, green: $0.green, blue: $0.blue) }
        guard let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: canvas.minX, y: canvas.maxY),
            "inputPoint1": CIVector(x: canvas.maxX, y: canvas.minY),
            "inputColor0": colors[0], "inputColor1": colors[1]
        ])?.outputImage else { throw ProjectError("Cannot prepare the canvas background.") }
        let background = gradient.cropped(to: canvas)
        let rendered = try await AVMutableVideoComposition.videoComposition(with: composition) { request in
            let input = request.sourceImage
            let extent = input.extent
            guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else {
                request.finish(with: ProjectError("Invalid video frame.")); return
            }
            let inner = canvas.insetBy(dx: canvas.width * project.padding, dy: canvas.height * project.padding)
            let fit = min(inner.width / extent.width, inner.height / extent.height)
            let frame = CGRect(x: canvas.midX - extent.width * fit / 2, y: canvas.midY - extent.height * fit / 2, width: extent.width * fit, height: extent.height * fit)
            let sourceTime = timeline.sourceTime(forOutput: request.compositionTime.seconds) ?? project.sourceDuration
            let zoom = project.zoom(atSource: sourceTime)
            let scale = fit * (zoom?.amount(at: sourceTime) ?? 1)
            let focus = CGPoint(x: extent.minX + extent.width * (zoom?.x ?? 0.5), y: extent.minY + extent.height * (1 - (zoom?.y ?? 0.5)))
            let tx = min(frame.minX - extent.minX * scale, max(frame.maxX - extent.maxX * scale, frame.midX - focus.x * scale))
            let ty = min(frame.minY - extent.minY * scale, max(frame.maxY - extent.maxY * scale, frame.midY - focus.y * scale))
            let withCursor = preparedCursor?.composite(over: input, sourceTime: sourceTime) ?? input
            let annotated = preparedAnnotations?.composite(over: withCursor, sourceTime: sourceTime) ?? withCursor
            let image = annotated.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)).cropped(to: frame).composited(over: background).cropped(to: canvas)
            request.finish(with: image, context: nil)
        }
        rendered.renderSize = canvas.size
        // The convenience builder otherwise inherits variable source sample timing,
        // including a long sample for a held frame. Render a regular 30 fps timeline.
        rendered.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        rendered.frameDuration = CMTime(value: 1, timescale: 30)
        return PreparedComposition(asset: composition, video: rendered, audio: audioMix)
    }

    private static func resolveAsset(_ path: String, source: URL, assets: [String: URL]) throws -> URL {
        let directory = source.deletingLastPathComponent().deletingLastPathComponent()
        let url = try assets[path] ?? ProjectStore.assetURL(path, in: directory)
        try ProjectStore.validateAssetFile(url, path: path)
        return url
    }
}

@MainActor public final class VideoExporter {
    private var session: AVAssetExportSession?
    public private(set) var isExporting = false
    private var cancelled = false
    public var progress: Double { Double(session?.progress ?? 0) }
    public init() {}
    public func cancel() { cancelled = true; session?.cancelExport() }
    public func export(project: Project, source: URL, destination: URL, width: Int, height: Int, assets: [String: URL] = [:]) async throws {
        guard !isExporting else { throw ProjectError("An export is already active.") }
        isExporting = true; cancelled = false
        defer { isExporting = false; session = nil }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectError("Choose a new export filename; existing files are preserved.") }
        let prepared = try await CompositionBuilder.build(project: project, source: source, width: width, height: height, assets: assets)
        guard !cancelled else { throw CancellationError() }
        guard let exporter = AVAssetExportSession(asset: prepared.asset, presetName: AVAssetExportPresetHighestQuality) else { throw ProjectError("Cannot start the video encoder.") }
        session = exporter
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".takelet-export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        exporter.videoComposition = prepared.video
        exporter.audioMix = prepared.audio
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: temporary, as: .mp4)
        guard !cancelled else { throw CancellationError() }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
