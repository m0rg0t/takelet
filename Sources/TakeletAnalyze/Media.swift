import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import AnalysisCore

func jsonData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func writeJSON<T: Encodable>(_ value: T, _ url: URL) throws { try jsonData(value).write(to: url, options: .atomic) }

func grayscale(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 320 * 180)
    let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(data: raw.baseAddress, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 180))
        return true
    }
    guard ok else { throw AnalysisError("Could not create activity thumbnail") }
    return bytes
}

func prepare(source: URL, destination: URL) async throws {
    let manifestURL = destination.appendingPathComponent("manifest.json")
    guard !FileManager.default.fileExists(atPath: manifestURL.path) else { throw AnalysisError("Output already contains a manifest; choose a new directory") }
    let asset = AVURLAsset(url: source)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0, duration <= 600 else { throw AnalysisError("Source must be between 0 and 600 seconds") }
    let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1280, height: 1280)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    try FileManager.default.createDirectory(at: destination.appendingPathComponent("frames"), withIntermediateDirectories: true)
    var frames: [Frame] = []
    var previous: [UInt8]?
    for index in 0..<Int(ceil(duration / 0.5)) {
        let requested = Double(index) * 0.5
        let result = try await generator.image(at: CMTime(seconds: requested, preferredTimescale: 600))
        let pixels = try grayscale(result.image)
        let changed: Double
        if let previous {
            changed = Double(zip(pixels, previous).filter { abs(Int($0) - Int($1)) > 12 }.count) / Double(pixels.count)
        } else { changed = 1 }
        previous = pixels
        let id = String(format: "f%04d", index)
        let file = "frames/\(id).jpg"
        guard let writer = CGImageDestinationCreateWithURL(destination.appendingPathComponent(file) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw AnalysisError("Could not create JPEG") }
        CGImageDestinationAddImage(writer, result.image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw AnalysisError("Could not finish JPEG") }
        frames.append(Frame(id: id, time: result.actualTime.seconds, file: file, change: changed))
    }
    let candidates = idleCandidates(frames: frames)
    // Evenly spaced context plus candidate endpoints; hard cap gives a predictable image budget.
    var indices: Set<Int> = [0, frames.count - 1]
    for span in candidates {
        for time in [span.start, span.end] {
            if let index = frames.indices.min(by: { abs(frames[$0].time - time) < abs(frames[$1].time - time) }), indices.count < 16 { indices.insert(index) }
        }
    }
    for i in 0..<12 where indices.count < 16 { indices.insert(Int((Double(i) / 11 * Double(frames.count - 1)).rounded())) }
    let manifest = Manifest(source: source.path, duration: duration, audioStatus: hasAudio ? "unreviewed" : "absent", frames: frames, candidates: candidates, protected: hasAudio ? [Span(0, duration)] : [], selectedFrameIDs: indices.sorted().map { frames[$0].id })
    try manifest.validate()
    try writeJSON(manifest, manifestURL)
    print("Prepared \(frames.count) frames; selected \(indices.count); candidate pauses \(candidates.count); audio \(manifest.audioStatus).")
}
