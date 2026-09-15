import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import CoreImage
import AudioToolbox
import ImageIO
import UniformTypeIdentifiers
import ProjectCore
import MediaEngine

@main struct MediaCheck {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw ProjectError("Usage: takelet-media-check NEW_OUTPUT_DIRECTORY") }
            let root = URL(fileURLWithPath: CommandLine.arguments[1])
            guard !FileManager.default.fileExists(atPath: root.path) else { throw ProjectError("Choose a new output directory.") }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let video = root.appendingPathComponent("generated-video.mov")
            try await makeFixture(at: video)
            let audio = root.appendingPathComponent("generated-audio.caf")
            try makeAudio(at: audio)
            let source = root.appendingPathComponent("synthetic-source.mov")
            let composition = AVMutableComposition()
            let original = AVURLAsset(url: video)
            let soundtrack = AVURLAsset(url: audio)
            let full = CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600))
            let v = try await original.loadTracks(withMediaType: .video)[0]
            let a = try await soundtrack.loadTracks(withMediaType: .audio)[0]
            try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(full, of: v, at: .zero)
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(full, of: a, at: .zero)
            let combine = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
            try await combine.export(to: source, as: .mov)
            let info = try await MediaInspector.inspect(source)
            var project = Project(title: "A small product demo", duration: info.duration, width: info.width, height: info.height)
            project.cuts = [TimeRange(start: 2, end: 3)]
            project.background = .dawn; project.padding = 0.09
            project.zooms = [Zoom(start: 0.3, end: 1.8, scale: 1.6, x: 0.25, y: 0.3), Zoom(start: 3.4, end: 5.6, scale: 2, x: 0.8, y: 0.65)]
            project.cursor = [CursorSample(time: 1, x: 0.3, y: 0.4, visible: true, pressed: false), CursorSample(time: 3.5, x: 0.65, y: 0.5, visible: true, pressed: true)]
            let document = root.appendingPathComponent("Sample.takelet")
            try ProjectStore.create(project, source: source, at: document)
            let reopened = try ProjectStore.load(from: document)
            guard project == reopened else { throw ProjectError("Project round-trip changed data.") }
            let movie = try ProjectStore.sourceURL(in: document)
            let exporter = VideoExporter()
            let cancelledDestination = root.appendingPathComponent("cancelled.mp4")
            let cancellation = Task { @MainActor in
                try await exporter.export(project: reopened, source: movie, destination: cancelledDestination, width: 3840, height: 2160)
            }
            while !exporter.isExporting { await Task.yield() }
            exporter.cancel()
            do {
                try await cancellation.value
                throw ProjectError("Cancelled export unexpectedly completed.")
            } catch is CancellationError {}
            guard !FileManager.default.fileExists(atPath: cancelledDestination.path), !exporter.isExporting else {
                throw ProjectError("Cancelled export left a destination or active state.")
            }
            print("PASS cancellation during export preparation; no destination created.")
            var results: [[String: Any]] = []
            for width in [1920, 3840] {
                let height = width == 1920 ? 1080 : 2160
                let destination = root.appendingPathComponent("sample-\(width).mp4")
                let start = Date()
                try await exporter.export(project: reopened, source: movie, destination: destination, width: width, height: height)
                let rendered = try await MediaInspector.inspect(destination)
                let outputAsset = AVURLAsset(url: destination)
                let rate = try await outputAsset.loadTracks(withMediaType: .video)[0].load(.nominalFrameRate)
                guard rendered.width == width, rendered.height == height, abs(rendered.duration - 5) <= 0.04, abs(rate - 30) < 0.1, rendered.audioTracks > 0 else { throw ProjectError("Export dimensions, timing, frame rate or audio failed.") }
                let prepared = try await CompositionBuilder.build(project: reopened, source: movie, width: width, height: height)
                let preview = AVAssetImageGenerator(asset: prepared.asset); preview.videoComposition = prepared.video
                let output = AVAssetImageGenerator(asset: outputAsset)
                preview.maximumSize = CGSize(width: 640, height: 360); output.maximumSize = preview.maximumSize
                preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
                output.requestedTimeToleranceBefore = .zero; output.requestedTimeToleranceAfter = .zero
                var unzoomed = reopened; unzoomed.zooms = []
                let baseline = try await CompositionBuilder.build(project: unzoomed, source: movie, width: width, height: height)
                let baselineFrames = AVAssetImageGenerator(asset: baseline.asset); baselineFrames.videoComposition = baseline.video
                baselineFrames.maximumSize = preview.maximumSize
                baselineFrames.requestedTimeToleranceBefore = .zero; baselineFrames.requestedTimeToleranceAfter = .zero
                var frameErrors: [Double] = []
                var zoomDifferences: [Double] = []
                for seconds in [1.0, 2.2, 3.2, 4.8] {
                    let time = CMTime(seconds: seconds, preferredTimescale: 600)
                    let p = try await preview.image(at: time).image
                    let e = try await output.image(at: time).image
                    if seconds == 1 {
                        let decoded = try pixels(e)
                        let cornerDifference = (0..<3).reduce(0) { $0 + abs(Int(decoded[$1]) - Int(decoded[decoded.count - 4 + $1])) }
                        guard cornerDifference > 60 else { throw ProjectError("The exported gradient background is missing.") }
                    }
                    let difference = zip(try pixels(p), try pixels(e)).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(160 * 90 * 4)
                    guard difference < 8 else { throw ProjectError("Preview/export frame mismatch: \(difference)") }
                    frameErrors.append(difference)
                    let plain = try await baselineFrames.image(at: time).image
                    let zoomDifference = zip(try pixels(p), try pixels(plain)).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(160 * 90 * 4)
                    let shouldZoom = seconds == 1 || seconds == 3.2
                    guard shouldZoom ? zoomDifference > 5 : zoomDifference < 1 else {
                        throw ProjectError("Zoom activation or gap failed at output \(seconds): \(zoomDifference)")
                    }
                    zoomDifferences.append(zoomDifference)
                    if seconds == 1 {
                        let writer = CGImageDestinationCreateWithURL(root.appendingPathComponent("preview-\(width).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
                        CGImageDestinationAddImage(writer, e, nil); CGImageDestinationFinalize(writer)
                    }
                }
                let beeps = try await pulseTimes(in: destination)
                guard beeps.count == 3, zip(beeps, [1.0, 2.5, 4.0]).allSatisfy({ abs($0 - $1) < 0.08 }) else { throw ProjectError("Audio timing mismatch: \(beeps)") }
                results.append(["width": width, "height": height, "duration": rendered.duration, "fps": rate, "audioPulseTimes": beeps, "previewExportMeanPixelErrors": frameErrors, "zoomVsUnzoomedMeanPixelErrors": zoomDifferences, "elapsedSeconds": Date().timeIntervalSince(start)])
                print("PASS \(width)×\(height), 30 fps, 5 s; aligned audio and preview frames.")
            }
            let report: [String: Any] = ["syntheticFixture": true, "projectRoundTrip": true, "backgroundPreset": project.background.rawValue, "zoomCount": project.zooms.count, "preparationCancellation": true, "outputs": results]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("validation.json"))
        } catch { FileHandle.standardError.write(Data("Media check failed: \(error.localizedDescription)\n".utf8)); exit(1) }
    }

    static func pixels(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 160 * 90 * 4)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 160 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 90)); return true
        }
        if !ok { throw ProjectError("Cannot sample a frame.") }; return data
    }

    @MainActor static func makeFixture(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1920, kCVPixelBufferHeightKey as String: 1080, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ProjectError("Cannot write fixture.") }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<180 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? ProjectError("Fixture writer stopped.") }
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else { throw ProjectError("Cannot allocate frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
            context.setFillColor(CGColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 1080))
            context.setFillColor(CGColor(red: 0.22, green: 0.4, blue: 0.95, alpha: 1)); context.fill(CGRect(x: 380, y: 730, width: 1420, height: 180))
            context.setFillColor(CGColor(red: 0.84, green: 0.88, blue: 0.94, alpha: 1))
            for n in 0..<3 { context.fill(CGRect(x: 380 + n * 490, y: 190, width: 440, height: 470)) }
            context.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.56, alpha: 1))
            context.fillEllipse(in: CGRect(x: 420 + Double(index) * 4, y: 400, width: 90, height: 90))
            text("TAKELET", x: 38, y: 950, size: 38, color: .init(gray: 1, alpha: 1), in: context)
            text("Workspace", x: 38, y: 820, size: 26, color: .init(gray: 0.8, alpha: 1), in: context)
            text("Your next great demo", x: 430, y: 795, size: 64, color: .init(gray: 1, alpha: 1), in: context)
            text("Synthetic test footage · \(String(format: "%.1f", Double(index) / 30)) s", x: 390, y: 110, size: 30, color: .init(gray: 0.3, alpha: 1), in: context)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw writer.error ?? ProjectError("Cannot append frame.") }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 6, preferredTimescale: 600)); input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError("Fixture failed.") }
    }

    static func text(_ string: String, x: Double, y: Double, size: Double, color: CGColor, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, context)
    }

    static func makeAudio(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 288000)!
        buffer.frameLength = 288000
        for i in 0..<288000 {
            let t = Double(i) / 48000
            let active = [1.0, 3.5, 5.0].contains { t >= $0 && t < $0 + 0.1 }
            buffer.floatChannelData![0][i] = active ? Float(0.5 * sin(t * 2 * .pi * 440)) : 0
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer)
    }

    static func pulseTimes(in url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .audio)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1])
        reader.add(output); guard reader.startReading() else { throw reader.error ?? ProjectError("Cannot read audio.") }
        var pulses: [Double] = []
        var lastActive = -1.0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = sample.dataBuffer else { continue }
            let size = CMBlockBufferGetDataLength(block)
            var bytes = [Int16](repeating: 0, count: size / 2)
            let copied = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
            guard copied == kCMBlockBufferNoErr else { throw ProjectError("Cannot decode audio samples.") }
            for (i, value) in bytes.enumerated() where abs(Int(value)) > 4000 {
                let time = sample.presentationTimeStamp.seconds + Double(i) / 48000
                if time - lastActive > 0.2 { pulses.append(time) }
                lastActive = time
            }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError("Audio check interrupted.") }
        return pulses
    }
}
