import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreImage
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
}

public enum CompositionBuilder {
    // Each build transfers a fresh composition to its caller; mutable AVFoundation objects are never shared.
    public static func build(project: Project, source: URL, width: Int = 1920, height: Int = 1080) async throws -> sending PreparedComposition {
        try project.validate()
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
        var output = CMTime.zero
        for range in project.retainedRanges {
            let sourceRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60000), duration: CMTime(seconds: range.duration, preferredTimescale: 60000))
            try videoTrack.insertTimeRange(sourceRange, of: video, at: output)
            for (originalTrack, destination) in audioPairs {
                let available = try await originalTrack.load(.timeRange)
                let overlap = CMTimeRangeGetIntersection(available, otherRange: sourceRange)
                if overlap.isValid, overlap.duration > .zero {
                    try destination.insertTimeRange(overlap, of: originalTrack, at: output + overlap.start - sourceRange.start)
                }
            }
            output = output + sourceRange.duration
        }
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
            let sourceTime = project.sourceTime(forOutput: request.compositionTime.seconds) ?? project.sourceDuration
            let scale = fit * project.zoom.amount(at: sourceTime)
            let focus = CGPoint(x: extent.minX + extent.width * project.zoom.x, y: extent.minY + extent.height * (1 - project.zoom.y))
            let tx = min(frame.minX - extent.minX * scale, max(frame.maxX - extent.maxX * scale, frame.midX - focus.x * scale))
            let ty = min(frame.minY - extent.minY * scale, max(frame.maxY - extent.maxY * scale, frame.midY - focus.y * scale))
            let image = input.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)).cropped(to: frame).composited(over: background).cropped(to: canvas)
            request.finish(with: image, context: nil)
        }
        rendered.renderSize = canvas.size
        rendered.frameDuration = CMTime(value: 1, timescale: 30)
        return PreparedComposition(asset: composition, video: rendered)
    }
}

@MainActor public final class VideoExporter {
    private var session: AVAssetExportSession?
    public private(set) var isExporting = false
    private var cancelled = false
    public var progress: Double { Double(session?.progress ?? 0) }
    public init() {}
    public func cancel() { cancelled = true; session?.cancelExport() }
    public func export(project: Project, source: URL, destination: URL, width: Int, height: Int) async throws {
        guard !isExporting else { throw ProjectError("An export is already active.") }
        isExporting = true; cancelled = false
        defer { isExporting = false; session = nil }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectError("Choose a new export filename; existing files are preserved.") }
        let prepared = try await CompositionBuilder.build(project: project, source: source, width: width, height: height)
        guard !cancelled else { throw CancellationError() }
        guard let exporter = AVAssetExportSession(asset: prepared.asset, presetName: AVAssetExportPresetHighestQuality) else { throw ProjectError("Cannot start the video encoder.") }
        session = exporter
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".takelet-export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        exporter.videoComposition = prepared.video
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: temporary, as: .mp4)
        guard !cancelled else { throw CancellationError() }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
