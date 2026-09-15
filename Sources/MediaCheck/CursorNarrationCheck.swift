import AudioToolbox
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MediaEngine
import ProjectCore
import UniformTypeIdentifiers

enum CursorNarrationCheck {
    /// Runs native cursor and narration verification using MediaCheck's existing six-second source fixture.
    /// The returned dictionary contains only JSON-compatible values for `validation.json`.
    @MainActor static func run(in root: URL, source: URL) async throws -> [String: Any] {
        let fixtureRoot = root.appendingPathComponent("cursor-narration")
        guard !FileManager.default.fileExists(atPath: fixtureRoot.path) else {
            throw ProjectError("Cursor/narration validation destination already exists.")
        }
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

        let cursorID = UUID()
        let shortAudioID = UUID()
        let longAudioID = UUID()
        let cursorPath = "media/cursors/\(cursorID.uuidString).png"
        let shortPath = "media/narration/\(shortAudioID.uuidString).mp3"
        let longPath = "media/narration/\(longAudioID.uuidString).mp3"
        let cursorSource = fixtureRoot.appendingPathComponent("custom-cursor.png")
        let shortSource = fixtureRoot.appendingPathComponent("short-narration.mp3")
        let longSource = fixtureRoot.appendingPathComponent("long-narration.mp3")
        try makeCursorPNG(at: cursorSource)
        try makeMP3(at: shortSource, duration: 0.61, frequency: 760)
        try makeMP3(at: longSource, duration: 2.55, frequency: 1_130)
        let shortDuration = try await mp3Duration(shortSource)
        let longDuration = try await mp3Duration(longSource)
        guard shortDuration < 1.06, longDuration > 1.73 else {
            throw ProjectError("Synthetic narration lengths do not exercise both short and long timing: \(shortDuration), \(longDuration).")
        }

        let info = try await MediaInspector.inspect(source)
        guard abs(info.duration - 6) < 0.05, info.width == 1920, info.height == 1080 else {
            throw ProjectError("Cursor/narration validation requires MediaCheck's 1920×1080 six-second fixture.")
        }
        let cut = TimeRange(start: 2.03, end: 2.57)
        // With the 0.54-second cut, this maps to output frame 87 exactly.
        let cursorTargetSourceTime = 3.44
        let cursorTargetX = cursorX(at: cursorTargetSourceTime, duration: info.duration)
        var project = Project(title: "Cursor and narration verification", duration: info.duration, width: info.width, height: info.height)
        project.cuts = [cut]
        project.padding = 0.04
        project.background = .midnight
        project.sourceAudioVolume = 0
        project.narrationVolume = 0.8
        project.cursorMode = .separate
        project.cursorStyle = CursorStyle(
            shape: .customImage,
            color: CursorRGBA(red: 1, green: 0, blue: 0.75),
            size: 54,
            smoothing: 0,
            clickHalo: false,
            imageFile: cursorPath,
            hotspotX: 0.2,
            hotspotY: 0.25
        )
        project.cursor = (0...60).map { index in
            let time = Double(index) / 10
            return CursorSample(
                time: time,
                x: cursorX(at: time, duration: info.duration),
                y: 0.5,
                visible: true,
                pressed: time >= 3.4 && time < 3.5
            )
        }
        project.zooms = [Zoom(start: 3, end: 5.4, scale: 2, x: cursorTargetX, y: 0.5)]
        project.narrations = [
            NarrationSegment(
                start: 0.47,
                end: 1.53,
                script: "Short synthetic narration",
                voiceID: "synthetic-760-hz",
                voiceName: "Synthetic Short",
                audioFile: shortPath,
                audioDuration: shortDuration
            ),
            NarrationSegment(
                start: 1.8,
                end: 4.07,
                script: "Long synthetic narration across a cut",
                voiceID: "synthetic-1130-hz",
                voiceName: "Synthetic Long",
                audioFile: longPath,
                audioDuration: longDuration
            )
        ]
        try project.validate()

        let sourceAssets = [cursorPath: cursorSource, shortPath: shortSource, longPath: longSource]
        let document = fixtureRoot.appendingPathComponent("CursorNarration.takelet")
        try ProjectStore.create(project, source: source, at: document, assets: sourceAssets)
        let portable = try ProjectStore.load(from: document)
        guard portable == project else { throw ProjectError("Portable cursor/narration project changed during round-trip.") }
        let portableSource = try ProjectStore.sourceURL(in: document)
        let portableAssets = try ProjectStore.assetURLs(for: portable, in: document)
        guard Set(portableAssets.keys) == Set(sourceAssets.keys), portableAssets.values.allSatisfy({
            $0.path.hasPrefix(document.path + "/")
        }) else { throw ProjectError("Portable cursor/narration assets did not resolve inside the project.") }

        let timeline = try portable.makeTimeline()
        let shortPlacement = try placement(for: portable.narrations[0].id, in: timeline)
        let longPlacement = try placement(for: portable.narrations[1].id, in: timeline)
        let hold = try unwrap(timeline.spans.first(where: { $0.hold?.narrationID == portable.narrations[1].id }), "Long narration did not create a hold.")
        let holdFrameA = frameTime(in: hold.outputInterval, fraction: 0.25)
        let holdFrameB = frameTime(in: hold.outputInterval, fraction: 0.75)
        guard shortPlacement.heldSourceFrameTime == nil,
              abs(shortPlacement.outputDuration - 1.06) < 0.000_001,
              longPlacement.heldSourceFrameTime != nil,
              hold.isHold,
              abs(hold.outputInterval.duration - (longDuration - 1.73)) < 0.000_001,
              !isFrameAligned(hold.outputInterval.start, frameRate: 30) else {
            throw ProjectError("Short/long narration or non-grid hold derivation is incorrect.")
        }
        let cursorOutputTime = try unwrap(timeline.outputTime(forSource: cursorTargetSourceTime), "Cursor target was cut.")
        let expectedSourcePulseTimes = try [1.0, 3.5, 5.0].map { sourceTime in
            try unwrap(timeline.outputTime(forSource: sourceTime), "Source audio pulse at \(sourceTime) seconds was cut.")
        }
        guard abs((timeline.sourceTime(forOutput: cursorOutputTime) ?? -1) - cursorTargetSourceTime) < 0.000_001 else {
            throw ProjectError("Cursor source/output mapping changed across the cut.")
        }

        var outputReports: [[String: Any]] = []
        var deferredFailures: [String] = []
        for width in [1920, 3840] {
            let height = width == 1920 ? 1080 : 2160
            let started = Date()
            let active = try await CompositionBuilder.build(
                project: portable,
                source: portableSource,
                width: width,
                height: height,
                assets: portableAssets
            )
            try await verifySourceAudioGap(in: active.asset, sourceTrackCount: info.audioTracks, hold: hold.outputInterval)

            var embedded = portable
            embedded.cursorMode = .embedded
            let noCursor = try await CompositionBuilder.build(project: embedded, source: portableSource, width: width, height: height, assets: portableAssets)
            var hidden = portable
            hidden.cursorStyle.hidden = true
            let hiddenCursor = try await CompositionBuilder.build(project: hidden, source: portableSource, width: width, height: height, assets: portableAssets)

            let previewFrame = try await frame(from: active, at: cursorOutputTime)
            let noCursorFrame = try await frame(from: noCursor, at: cursorOutputTime)
            let hiddenFrame = try await frame(from: hiddenCursor, at: cursorOutputTime)
            let activeDifference = try difference(previewFrame, noCursorFrame, width: 960, height: 540)
            let hiddenDifference = try difference(hiddenFrame, noCursorFrame, width: 960, height: 540)
            guard activeDifference.changedPixels > 60,
                  abs(activeDifference.centroidX - 0.5) < 0.08,
                  abs(activeDifference.centroidY - 0.5) < 0.08,
                  hiddenDifference.mean < 0.05 else {
                throw ProjectError("Custom cursor visibility, hotspot, or zoom alignment failed at \(width)×\(height).")
            }

            let previewHoldA = try await frame(from: active, at: holdFrameA)
            let previewHoldB = try await frame(from: active, at: holdFrameB)
            let previewHoldDifference = try difference(previewHoldA, previewHoldB, width: 480, height: 270).mean
            guard previewHoldDifference < 0.05 else {
                throw ProjectError("Narration hold did not freeze the prepared video at \(width)×\(height): \(previewHoldDifference)")
            }

            let destination = fixtureRoot.appendingPathComponent("cursor-narration-\(width).mp4")
            try await VideoExporter().export(
                project: portable,
                source: portableSource,
                destination: destination,
                width: width,
                height: height,
                assets: portableAssets
            )
            let rendered = try await MediaInspector.inspect(destination)
            let outputAsset = AVURLAsset(url: destination)
            let frameRate = try await unwrap(
                outputAsset.loadTracks(withMediaType: .video).first,
                "Cursor/narration export is missing video."
            ).load(.nominalFrameRate)
            guard rendered.width == width, rendered.height == height,
                  abs(rendered.duration - timeline.outputDuration) < 0.06,
                  frameRate.isFinite, frameRate > 0, rendered.audioTracks > 0 else {
                throw ProjectError("Cursor/narration export dimensions, duration, or audio failed.")
            }
            if abs(frameRate - 30) >= 0.1 {
                deferredFailures.append("\(width)×\(height) frozen-hold export reports \(frameRate) fps instead of 30 fps")
            }
            let exportedTarget = try await frame(from: outputAsset, at: cursorOutputTime)
            let exportMatch = try difference(exportedTarget, previewFrame, width: 480, height: 270).mean
            guard exportMatch < 8 else { throw ProjectError("Cursor preview/export mismatch at \(width)×\(height): \(exportMatch)") }
            let exportedHoldA = try await frame(from: outputAsset, at: holdFrameA)
            let exportedHoldB = try await frame(from: outputAsset, at: holdFrameB)
            let exportedHoldDifference = try difference(exportedHoldA, exportedHoldB, width: 480, height: 270).mean
            guard exportedHoldDifference < 1 else {
                throw ProjectError("Exported narration hold is not frozen at \(width)×\(height): \(exportedHoldDifference)")
            }

            let audio = try await readAudio(destination)
            let shortActive = audio.rms(from: shortPlacement.outputStart + 0.12, to: shortPlacement.outputStart + 0.38)
            let shortAfter = audio.rms(from: shortPlacement.outputStart + shortDuration + 0.12, to: shortPlacement.outputStart + shortDuration + 0.32)
            let longActive = audio.rms(from: longPlacement.outputStart + 0.12, to: longPlacement.outputStart + 0.38)
            let longHold = audio.rms(from: hold.outputInterval.start + 0.15, to: min(hold.outputInterval.end - 0.1, hold.outputInterval.start + 0.45))
            let longAfter = audio.rms(from: longPlacement.outputStart + longDuration + 0.12, to: longPlacement.outputStart + longDuration + 0.32)
            let mutedLastSourcePulse = audio.rms(from: expectedSourcePulseTimes[2] + 0.015, to: expectedSourcePulseTimes[2] + 0.085)
            guard shortActive > 0.02, shortAfter < 0.01,
                  longActive > 0.02, longHold > 0.02, longAfter < 0.01,
                  mutedLastSourcePulse < 0.01 else {
                throw ProjectError("Narration-only audio placement failed at \(width)×\(height): \([shortActive, shortAfter, longActive, longHold, longAfter, mutedLastSourcePulse])")
            }

            outputReports.append([
                "width": width,
                "height": height,
                "duration": rendered.duration,
                "fps": frameRate,
                "cursorChangedPixels": activeDifference.changedPixels,
                "cursorCentroid": [activeDifference.centroidX, activeDifference.centroidY],
                "hiddenCursorMeanDifference": hiddenDifference.mean,
                "previewExportMeanDifference": exportMatch,
                "previewHoldMeanDifference": previewHoldDifference,
                "exportedHoldMeanDifference": exportedHoldDifference,
                "audioRMS": [
                    "shortActive": shortActive,
                    "shortAfter": shortAfter,
                    "longActive": longActive,
                    "longHold": longHold,
                    "longAfter": longAfter,
                    "mutedLastSourcePulse": mutedLastSourcePulse,
                ],
                "elapsedSeconds": Date().timeIntervalSince(started),
            ])
            print(String(
                format: "DETAIL %d×%d fps %.6f cursor %d px @ %.4f,%.4f hidden %.6f preview/export %.6f hold %.6f/%.6f audio %.5f %.5f %.5f %.5f %.5f muted-pulse %.5f",
                width, height, frameRate,
                activeDifference.changedPixels, activeDifference.centroidX, activeDifference.centroidY,
                hiddenDifference.mean, exportMatch, previewHoldDifference, exportedHoldDifference,
                shortActive, shortAfter, longActive, longHold, longAfter, mutedLastSourcePulse
            ))
            print("PASS cursor + narration \(width)×\(height); portable assets, zoom hotspot, audio, and frozen hold aligned.")
        }

        var sourceOnly = portable
        sourceOnly.sourceAudioVolume = 1
        sourceOnly.narrationVolume = 0
        let sourceOnlyDestination = fixtureRoot.appendingPathComponent("source-only-1920.mp4")
        try await VideoExporter().export(
            project: sourceOnly,
            source: portableSource,
            destination: sourceOnlyDestination,
            width: 1920,
            height: 1080,
            assets: portableAssets
        )
        let sourceOnlyPulseTimes = try await MediaCheck.pulseTimes(in: sourceOnlyDestination)
        guard sourceOnlyPulseTimes.count == expectedSourcePulseTimes.count,
              zip(sourceOnlyPulseTimes, expectedSourcePulseTimes).allSatisfy({ abs($0 - $1) < 0.08 }) else {
            throw ProjectError("Source-only audio pulse timing mismatch: measured \(sourceOnlyPulseTimes), expected \(expectedSourcePulseTimes).")
        }
        print("DETAIL source-only pulses measured \(sourceOnlyPulseTimes), expected \(expectedSourcePulseTimes)")
        print("PASS independent source/narration mixing and source audio timing after the narration hold.")

        let sixtyFPSHoldDifference = try await verifySixtyFPSHold(
            in: fixtureRoot,
            narrationPath: longPath,
            narrationURL: longSource,
            narrationDuration: longDuration
        )
        print(String(format: "DETAIL 60 fps source hold mean difference %.6f", sixtyFPSHoldDifference))
        if sixtyFPSHoldDifference >= 1 {
            deferredFailures.append("60 fps source moves during its stretched 1/30-second hold interval (mean difference \(sixtyFPSHoldDifference))")
        }

        guard deferredFailures.isEmpty else {
            throw ProjectError("Cursor/narration validation found: \(deferredFailures.joined(separator: "; ")).")
        }
        return [
            "portableProject": true,
            "customCursor": true,
            "hiddenCursor": true,
            "cut": ["start": cut.start, "end": cut.end],
            "cursorSourceTime": cursorTargetSourceTime,
            "cursorOutputTime": cursorOutputTime,
            "shortNarrationDuration": shortDuration,
            "longNarrationDuration": longDuration,
            "narrationOnlyAudio": [
                "sourceVolume": portable.sourceAudioVolume,
                "narrationVolume": portable.narrationVolume,
            ],
            "sourceOnlyAudio": [
                "sourceVolume": sourceOnly.sourceAudioVolume,
                "narrationVolume": sourceOnly.narrationVolume,
                "pulseTimes": sourceOnlyPulseTimes,
                "expectedPulseTimes": expectedSourcePulseTimes,
            ],
            "sixtyFPSHoldMeanDifference": sixtyFPSHoldDifference,
            "hold": [
                "outputStart": hold.outputInterval.start,
                "outputEnd": hold.outputInterval.end,
                "sourceFrameTime": hold.hold!.sourceFrameTime,
            ],
            "outputs": outputReports,
        ]
    }
}

private extension CursorNarrationCheck {
    struct PixelDifference {
        var mean: Double
        var changedPixels: Int
        var centroidX: Double
        var centroidY: Double
    }

    struct AudioSamples {
        struct Chunk {
            var start: Double
            var sampleRate: Double
            var values: [Float]
        }
        var chunks: [Chunk]

        func rms(from start: Double, to end: Double) -> Double {
            var sum = 0.0
            var count = 0
            for chunk in chunks {
                for (index, sample) in chunk.values.enumerated() {
                    let time = chunk.start + Double(index) / chunk.sampleRate
                    if time >= start, time < end {
                        sum += Double(sample * sample)
                        count += 1
                    }
                }
            }
            return count > 0 ? sqrt(sum / Double(count)) : 0
        }
    }

    static func cursorX(at time: Double, duration: Double) -> Double {
        0.18 + 0.64 * time / duration
    }

    static func placement(for id: UUID, in timeline: NarrationTimeline) throws -> NarrationPlacement {
        try unwrap(timeline.narrations.first(where: { $0.narrationID == id }), "Narration placement is missing.")
    }

    static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw ProjectError(message) }
        return value
    }

    static func isFrameAligned(_ time: Double, frameRate: Double) -> Bool {
        abs(time * frameRate - (time * frameRate).rounded()) < 0.000_001
    }

    static func frameTime(in interval: TimelineInterval, fraction: Double) -> Double {
        let requested = interval.start + interval.duration * fraction
        return min(interval.end - 1.0 / 30, max(interval.start, (requested * 30).rounded() / 30))
    }

    static func makeCursorPNG(at url: URL) throws {
        let width = 80
        let height = 48
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ProjectError("Cannot create the custom cursor fixture.") }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 36))
        path.addLine(to: CGPoint(x: 72, y: 24))
        path.addLine(to: CGPoint(x: 29, y: 5))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0.75, alpha: 1))
        context.fillPath()
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 11, y: 31, width: 10, height: 10))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ProjectError("Cannot encode the custom cursor fixture.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ProjectError("Cannot encode the custom cursor fixture.") }
    }

    static func makeMP3(at url: URL, duration: Double, frequency: Int) throws {
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/ffmpeg" }
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] + pathCandidates
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ProjectError("Cursor/narration media validation needs ffmpeg to create local synthetic MP3 fixtures.")
        }
        let fadeStart = max(0, duration - 0.03)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-v", "error", "-nostdin", "-y",
            "-f", "lavfi", "-i", "sine=frequency=\(frequency):sample_rate=48000:duration=\(duration)",
            "-af", "volume=0.8,afade=t=in:st=0:d=0.02,afade=t=out:st=\(fadeStart):d=0.03",
            "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "96k", url.path,
        ]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown ffmpeg error"
            throw ProjectError("Cannot create synthetic MP3 fixture: \(detail.prefix(500))")
        }
    }

    @MainActor static func verifySixtyFPSHold(
        in root: URL,
        narrationPath: String,
        narrationURL: URL,
        narrationDuration: Double
    ) async throws -> Double {
        let source = root.appendingPathComponent("alternating-60fps.mov")
        try await makeSixtyFPSFixture(at: source)
        let info = try await MediaInspector.inspect(source)
        guard abs(info.duration - 1.2) < 0.02, info.width == 320, info.height == 180 else {
            throw ProjectError("The 60 fps hold fixture has unexpected media metadata.")
        }
        var project = Project(title: "60 fps hold verification", duration: info.duration, width: info.width, height: info.height)
        project.narrations = [NarrationSegment(
            start: 0.2,
            end: 0.71,
            script: "A long narration over sixty frame footage",
            voiceID: "synthetic-1130-hz",
            voiceName: "Synthetic Long",
            audioFile: narrationPath,
            audioDuration: narrationDuration
        )]
        let timeline = try project.makeTimeline()
        let hold = try unwrap(timeline.spans.first(where: \.isHold), "The 60 fps fixture did not create a hold.")
        guard abs(hold.sourceInterval.duration - 1.0 / 30) < 0.000_001 else {
            throw ProjectError("The 60 fps hold did not use the expected nominal 1/30-second source interval.")
        }
        let prepared = try await CompositionBuilder.build(
            project: project,
            source: source,
            width: 640,
            height: 360,
            assets: [narrationPath: narrationURL]
        )
        let first = try await frame(from: prepared, at: frameTime(in: hold.outputInterval, fraction: 0.25))
        let second = try await frame(from: prepared, at: frameTime(in: hold.outputInterval, fraction: 0.75))
        return try difference(first, second, width: 320, height: 180).mean
    }

    @MainActor static func makeSixtyFPSFixture(at url: URL) async throws {
        let width = 320
        let height = 180
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ProjectError("Cannot write the 60 fps fixture.") }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<72 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? ProjectError("The 60 fps fixture writer stopped.") }
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw ProjectError("Cannot allocate a 60 fps fixture frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw ProjectError("Cannot draw a 60 fps fixture frame.")
            }
            let even = index.isMultiple(of: 2)
            context.setFillColor(even
                ? CGColor(red: 0.92, green: 0.12, blue: 0.18, alpha: 1)
                : CGColor(red: 0.08, green: 0.24, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: (index * 13) % width, y: 0, width: 12, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60)) else {
                throw writer.error ?? ProjectError("Cannot append a 60 fps fixture frame.")
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 72, timescale: 60))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError("The 60 fps fixture failed.") }
    }

    static func mp3Duration(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let track = try unwrap(try await asset.loadTracks(withMediaType: .audio).first, "Synthetic MP3 has no audio track.")
        let descriptions = try await track.load(.formatDescriptions)
        let isMP3 = descriptions.contains { description in
            guard let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return false }
            return basic.pointee.mFormatID == kAudioFormatMPEGLayer3
        }
        guard duration.isFinite, duration > 0, isMP3 else { throw ProjectError("Synthetic narration is not a readable MP3.") }
        return duration
    }

    static func frame(from prepared: PreparedComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: prepared.asset)
        generator.videoComposition = prepared.video
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 960, height: 540)
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000)).image
    }

    static func frame(from asset: AVAsset, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 960, height: 540)
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000)).image
    }

    static func difference(_ lhs: CGImage, _ rhs: CGImage, width: Int, height: Int) throws -> PixelDifference {
        let left = try pixels(lhs, width: width, height: height)
        let right = try pixels(rhs, width: width, height: height)
        var total = 0.0
        var changed = 0
        var weightedX = 0.0
        var weightedY = 0.0
        var weight = 0.0
        for index in stride(from: 0, to: left.count, by: 4) {
            let delta = (0..<3).reduce(0) { $0 + abs(Int(left[index + $1]) - Int(right[index + $1])) }
            total += Double(delta) / 3
            if delta > 45 {
                let pixel = index / 4
                let amount = Double(delta)
                changed += 1
                weightedX += Double(pixel % width) * amount
                weightedY += Double(pixel / width) * amount
                weight += amount
            }
        }
        return PixelDifference(
            mean: total / Double(width * height),
            changedPixels: changed,
            centroidX: weight > 0 ? weightedX / weight / Double(width) : -1,
            centroidY: weight > 0 ? weightedY / weight / Double(height) : -1
        )
    }

    static func pixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let created = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { throw ProjectError("Cannot sample a validation frame.") }
        return data
    }

    static func verifySourceAudioGap(in asset: AVAsset, sourceTrackCount: Int, hold: TimelineInterval) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count >= sourceTrackCount else { throw ProjectError("Prepared composition lost source audio tracks.") }
        let target = CMTimeRange(
            start: CMTime(seconds: hold.start, preferredTimescale: 60_000),
            duration: CMTime(seconds: hold.duration, preferredTimescale: 60_000)
        )
        for track in tracks.prefix(sourceTrackCount) {
            for segment in try await track.load(.segments) where !segment.isEmpty {
                let overlap = CMTimeRangeGetIntersection(segment.timeMapping.target, otherRange: target)
                guard !overlap.isValid || overlap.duration <= CMTime(value: 1, timescale: 60_000) else {
                    throw ProjectError("Source audio overlaps a frozen narration hold.")
                }
            }
        }
    }

    static func readAudio(_ url: URL) async throws -> AudioSamples {
        let asset = AVURLAsset(url: url)
        let track = try unwrap(try await asset.loadTracks(withMediaType: .audio).first, "Export has no readable audio track.")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError("Cannot read exported audio.") }
        var chunks: [AudioSamples.Chunk] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = sample.dataBuffer else { continue }
            let size = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: size / MemoryLayout<Float>.size)
            let status = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw ProjectError("Cannot decode exported audio samples.") }
            chunks.append(AudioSamples.Chunk(start: sample.presentationTimeStamp.seconds, sampleRate: 48_000, values: values))
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError("Audio verification was interrupted.") }
        return AudioSamples(chunks: chunks)
    }
}
