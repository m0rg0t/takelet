@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import MediaEngine
import ProjectCore
import UniformTypeIdentifiers

enum AnnotationCheck {
    @MainActor static func run(in root: URL, source: URL) async throws -> [String: Any] {
        let fixtureRoot = root.appendingPathComponent("annotations")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

        let direct = try directRendererChecks()
        let info = try await MediaInspector.inspect(source)
        guard info.width == 1920, info.height == 1080, abs(info.duration - 6) < 0.05 else {
            throw ProjectError("Annotation validation requires MediaCheck's 1920×1080 six-second fixture.")
        }

        let narrationID = UUID()
        let narrationPath = "media/narration/\(narrationID.uuidString).mp3"
        let narrationURL = fixtureRoot.appendingPathComponent("hold.mp3")
        try makeMP3(at: narrationURL, duration: 1.3)
        let narrationDuration = try await AVURLAsset(url: narrationURL).load(.duration).seconds

        var project = Project(title: "Annotation verification", duration: info.duration, width: info.width, height: info.height)
        project.cuts = [TimeRange(start: 2, end: 2.5)]
        project.zooms = [Zoom(start: 3, end: 4.3, scale: 1.8, x: 0.5, y: 0.5)]
        project.cursorMode = .separate
        project.cursorStyle = CursorStyle(shape: .circle, color: CursorRGBA(red: 0, green: 1, blue: 0), size: 72, smoothing: 0, clickHalo: false)
        project.cursor = stride(from: 0.0, through: 6.0, by: 0.1).map {
            CursorSample(time: $0, x: 0.5, y: 0.5, visible: true, pressed: false)
        }
        project.narrations = [
            NarrationSegment(
                start: 3.2,
                end: 4,
                script: "Synthetic hold",
                voiceID: "synthetic",
                voiceName: "Synthetic",
                audioFile: narrationPath,
                audioDuration: narrationDuration
            )
        ]
        let activeStart = 3.0
        let activeEnd = 4.1
        project.annotations = [
            // The cover deliberately precedes callouts in storage. Masks must still render last.
            Annotation(kind: .cover, start: activeStart, end: activeEnd, bounds: AnnotationBounds(x: 0.43, y: 0.39, width: 0.14, height: 0.22), color: AnnotationColor(red: 0.72, green: 0.05, blue: 0.46)),
            Annotation(kind: .arrow, start: activeStart, end: activeEnd, bounds: AnnotationBounds(x: 0.39, y: 0.34, width: 0.22, height: 0.32), color: AnnotationColor(red: 1, green: 0.7, blue: 0.05), direction: .downRight),
            Annotation(kind: .frame, start: activeStart, end: activeEnd, bounds: AnnotationBounds(x: 0.35, y: 0.3, width: 0.3, height: 0.4), color: AnnotationColor(red: 0.1, green: 0.75, blue: 1)),
            Annotation(kind: .text, start: activeStart, end: activeEnd, bounds: AnnotationBounds(x: 0.66, y: 0.22, width: 0.26, height: 0.16), color: AnnotationColor(red: 0.08, green: 0.2, blue: 0.62), text: "Wrapped callout text remains visible", fontSize: 0.05),
            Annotation(kind: .blur, start: activeStart, end: activeEnd, bounds: AnnotationBounds(x: 0.18, y: 0.28, width: 0.12, height: 0.24), blurRadius: 0.025),
        ]
        try project.validate()

        let assets = [narrationPath: narrationURL]
        let document = root.appendingPathComponent("AnnotatedSample.takelet")
        try ProjectStore.create(project, source: source, at: document, assets: assets)
        let portable = try ProjectStore.load(from: document)
        guard portable == project else { throw ProjectError("Portable annotation project changed during round-trip.") }
        let portableSource = try ProjectStore.sourceURL(in: document)
        let portableAssets = try ProjectStore.assetURLs(for: portable, in: document)

        let timeline = try portable.makeTimeline()
        let hold = try unwrap(timeline.spans.first(where: \.isHold), "Annotation fixture did not create a narration hold.")
        let beforeOutput = try unwrap(timeline.outputTime(forSource: 2.8), "Pre-annotation source time was cut.")
        let activeOutput = try unwrap(timeline.outputTime(forSource: 3.5), "Active annotation source time was cut.")
        let afterOutput = try unwrap(timeline.outputTime(forSource: 4.2), "Post-annotation source time was cut.")
        let holdOutput = hold.outputInterval.start + hold.outputInterval.duration * 0.5
        guard timeline.sourceTime(forOutput: beforeOutput)! < activeStart,
              project.annotations[0].isVisible(atSource: timeline.sourceTime(forOutput: activeOutput)!),
              project.annotations[0].isVisible(atSource: timeline.sourceTime(forOutput: holdOutput)!),
              timeline.sourceTime(forOutput: afterOutput)! >= activeEnd else {
            throw ProjectError("Annotation source-time mapping failed across cuts or narration hold.")
        }

        let prepared1080 = try await CompositionBuilder.build(project: portable, source: portableSource, width: 1920, height: 1080, assets: portableAssets)
        var baselineProject = portable
        baselineProject.annotations = []
        let baseline1080 = try await CompositionBuilder.build(project: baselineProject, source: portableSource, width: 1920, height: 1080, assets: portableAssets)
        let beforeDifference = try await frameDifference(prepared1080, baseline1080, at: beforeOutput)
        let activeDifference = try await frameDifference(prepared1080, baseline1080, at: activeOutput)
        let holdDifference = try await frameDifference(prepared1080, baseline1080, at: holdOutput)
        let afterDifference = try await frameDifference(prepared1080, baseline1080, at: afterOutput)
        guard beforeDifference.mean < 0.08, afterDifference.mean < 0.08,
              activeDifference.changedPixels > 600, holdDifference.changedPixels > 600,
              abs(activeDifference.centroidX - 0.5) < 0.18,
              abs(activeDifference.centroidY - 0.5) < 0.18 else {
            throw ProjectError("Annotation visibility or zoom/source-time alignment failed: \([beforeDifference.mean, activeDifference.mean, holdDifference.mean, afterDifference.mean]).")
        }

        let activeFrame = try await frame(from: prepared1080, at: activeOutput)
        try writePNG(activeFrame, to: fixtureRoot.appendingPathComponent("annotated-preview-1920.png"))
        let center = try averageRegion(activeFrame, normalized: CGRect(x: 0.46, y: 0.46, width: 0.08, height: 0.08))
        guard center.spread < 5, center.red > 100, center.blue > 60, center.green < 50 else {
            throw ProjectError("Opaque cover did not fully obscure the cursor and callouts below it: \(center).")
        }

        let fourK = try await CompositionBuilder.build(project: portable, source: portableSource, width: 3840, height: 2160, assets: portableAssets)
        let fourKFrame = try await frame(from: fourK, at: activeOutput)
        guard fourKFrame.width == 3840, fourKFrame.height == 2160 else {
            throw ProjectError("Annotation composition did not produce a 3840×2160 frame.")
        }

        var exportReports: [[String: Any]] = []
        var previewExportDifferences: [Double] = []
        for (width, height, previewFrame) in [(1920, 1080, activeFrame), (3840, 2160, fourKFrame)] {
            let destination = fixtureRoot.appendingPathComponent("annotations-\(width).mp4")
            try await VideoExporter().export(project: portable, source: portableSource, destination: destination, width: width, height: height, assets: portableAssets)
            let outputInfo = try await MediaInspector.inspect(destination)
            let exportedFrame = try await frame(from: AVURLAsset(url: destination), at: activeOutput)
            let previewExportDifference = try pixelDifference(previewFrame, exportedFrame, sampleWidth: 480, sampleHeight: 270).mean
            guard outputInfo.width == width, outputInfo.height == height,
                  abs(outputInfo.duration - timeline.outputDuration) < 0.06,
                  previewExportDifference < 8 else {
                throw ProjectError("Annotation \(width)×\(height) export size, duration, or preview match failed.")
            }
            previewExportDifferences.append(previewExportDifference)
            exportReports.append([
                "width": width,
                "height": height,
                "duration": outputInfo.duration,
                "previewExportMeanDifference": previewExportDifference,
            ])
        }

        print(String(format: "DETAIL annotations direct half-open %.6f blur %.6f/%.6f cover %.6f text %d px", direct.halfOpenDifference, direct.blurInsideDifference, direct.blurOutsideDifference, direct.coverDifference, direct.whiteTextPixels))
        print(String(format: "DETAIL annotations timing before %.6f active %.6f hold %.6f after %.6f preview/export %.6f/%.6f", beforeDifference.mean, activeDifference.mean, holdDifference.mean, afterDifference.mean, previewExportDifferences[0], previewExportDifferences[1]))
        print("PASS annotations portable project, half-open timing, mask layering, blur ROI, cuts, zoom, hold, and 1080p/4K exports.")

        return [
            "portableProject": true,
            "document": document.lastPathComponent,
            "halfOpenDifference": direct.halfOpenDifference,
            "blurInsideDifference": direct.blurInsideDifference,
            "blurOutsideDifference": direct.blurOutsideDifference,
            "coverDifference": direct.coverDifference,
            "whiteTextPixels": direct.whiteTextPixels,
            "beforeMeanDifference": beforeDifference.mean,
            "activeMeanDifference": activeDifference.mean,
            "holdMeanDifference": holdDifference.mean,
            "afterMeanDifference": afterDifference.mean,
            "activeDifferenceCentroid": [activeDifference.centroidX, activeDifference.centroidY],
            "hold": ["outputStart": hold.outputInterval.start, "outputEnd": hold.outputInterval.end, "sampledOutput": holdOutput],
            "fourKFrameSize": [fourKFrame.width, fourKFrame.height],
            "exports": exportReports,
        ]
    }
}

private extension AnnotationCheck {
    struct DirectResults {
        let halfOpenDifference: Double
        let blurInsideDifference: Double
        let blurOutsideDifference: Double
        let coverDifference: Double
        let whiteTextPixels: Int
    }

    struct Difference {
        let mean: Double
        let changedPixels: Int
        let centroidX: Double
        let centroidY: Double
    }

    struct RegionAverage: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double
        let spread: Double
        var description: String { "rgb=(\(red), \(green), \(blue)), spread=\(spread)" }
    }

    static func directRendererChecks() throws -> DirectResults {
        let source = try checkerImage(width: 320, height: 180).transformed(by: CGAffineTransform(translationX: 17, y: 29))
        let halfOpenAnnotation = Annotation(
            kind: .cover,
            start: 1,
            end: 2,
            bounds: AnnotationBounds(x: 0.4, y: 0.35, width: 0.2, height: 0.3),
            color: AnnotationColor(red: 0.8, green: 0.05, blue: 0.4)
        )
        let halfOpen = try AnnotationRenderer(annotations: [halfOpenAnnotation], sourceWidth: 320, sourceHeight: 180)
        let before = halfOpen.composite(over: source, sourceTime: 1 - 0.000_001)
        let atStart = halfOpen.composite(over: source, sourceTime: 1)
        let beforeEnd = halfOpen.composite(over: source, sourceTime: 2 - 0.000_001)
        let atEnd = halfOpen.composite(over: source, sourceTime: 2)
        guard before.extent == source.extent, atStart.extent == source.extent,
              beforeEnd.extent == source.extent, atEnd.extent == source.extent else {
            throw ProjectError("Annotation rendering changed a nonzero source extent.")
        }
        let startDifference = try pixelDifference(before, atStart, bounds: source.extent).mean
        let endDifference = try pixelDifference(beforeEnd, atEnd, bounds: source.extent).mean
        let outsideBefore = try pixelDifference(source, before, bounds: source.extent).mean
        let outsideAfter = try pixelDifference(source, atEnd, bounds: source.extent).mean
        guard startDifference > 2, endDifference > 2, outsideBefore == 0, outsideAfter == 0 else {
            throw ProjectError("Annotation visibility is not exactly half-open.")
        }

        let blurBounds = AnnotationBounds(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let blur = try AnnotationRenderer(
            annotations: [Annotation(kind: .blur, start: 0, end: 1, bounds: blurBounds, blurRadius: 0.035)],
            sourceWidth: 320,
            sourceHeight: 180
        ).composite(over: source, sourceTime: 0.5)
        let blurDifference = try regionalDifferences(source, blur, normalizedROI: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        guard blurDifference.inside > 4, blurDifference.outside < 0.001 else {
            throw ProjectError("Blur did not change only its rectangular ROI: \(blurDifference).")
        }

        let textOnly = try AnnotationRenderer(
            annotations: [Annotation(
                kind: .text,
                start: 0,
                end: 1,
                bounds: AnnotationBounds(x: 0.12, y: 0.18, width: 0.76, height: 0.64),
                color: AnnotationColor(red: 0.02, green: 0.08, blue: 0.3),
                text: "Каждое слово видно\nВторая строка целиком",
                fontSize: 0.1
            )],
            sourceWidth: 320,
            sourceHeight: 180
        ).composite(over: source, sourceTime: 0.5)
        let textPixels = try pixels(textOnly, bounds: source.extent, width: 320, height: 180)
        let whiteTextPixels = stride(from: 0, to: textPixels.count, by: 4).filter {
            textPixels[$0] > 225 && textPixels[$0 + 1] > 225 && textPixels[$0 + 2] > 225
        }.count
        guard whiteTextPixels > 80 else {
            throw ProjectError("Text annotation rendered its plate without visible wrapped text.")
        }
        let rejectedUnrenderableText: Bool
        do {
            _ = try AnnotationRenderer(
                annotations: [Annotation(
                    kind: .text,
                    start: 0,
                    end: 1,
                    bounds: AnnotationBounds(x: 0, y: 0, width: 0.01, height: 0.01),
                    text: String(repeating: "unrenderable ", count: 35)
                )],
                sourceWidth: 320,
                sourceHeight: 180
            )
            rejectedUnrenderableText = false
        } catch {
            rejectedUnrenderableText = true
        }
        guard rejectedUnrenderableText else {
            throw ProjectError("Unrenderable annotation text was silently accepted.")
        }

        let coverColor = AnnotationColor(red: 0.74, green: 0.03, blue: 0.42)
        let sourceWithCursor = try CursorRenderer(
            samples: [CursorSample(time: 0.5, x: 0.5, y: 0.5, visible: true, pressed: false)],
            style: CursorStyle(shape: .circle, color: CursorRGBA(red: 0, green: 1, blue: 0), size: 48, smoothing: 0, clickHalo: false)
        ).composite(over: source, sourceTime: 0.5)
        let layered = try AnnotationRenderer(
            annotations: [
                Annotation(kind: .cover, start: 0, end: 1, bounds: AnnotationBounds(x: 0.35, y: 0.3, width: 0.3, height: 0.4), color: coverColor),
                Annotation(kind: .text, start: 0, end: 1, bounds: AnnotationBounds(x: 0.38, y: 0.34, width: 0.24, height: 0.32), color: AnnotationColor(red: 0, green: 0.3, blue: 0.9), text: "Must be hidden", fontSize: 0.06),
                Annotation(kind: .arrow, start: 0, end: 1, bounds: AnnotationBounds(x: 0.38, y: 0.34, width: 0.24, height: 0.32), color: AnnotationColor(red: 1, green: 1, blue: 0), direction: .upLeft),
            ],
            sourceWidth: 320,
            sourceHeight: 180
        ).composite(over: sourceWithCursor, sourceTime: 0.5)
        let expectedCover = CIImage(color: CIColor(red: coverColor.red, green: coverColor.green, blue: coverColor.blue, alpha: 1))
            .cropped(to: source.extent)
        let coverDifference = try regionalDifferences(layered, expectedCover, normalizedROI: CGRect(x: 0.36, y: 0.31, width: 0.28, height: 0.38)).inside
        guard coverDifference < 0.001 else {
            throw ProjectError("Cover did not obscure callouts painted later in project list order: \(coverDifference).")
        }
        return DirectResults(
            halfOpenDifference: min(startDifference, endDifference),
            blurInsideDifference: blurDifference.inside,
            blurOutsideDifference: blurDifference.outside,
            coverDifference: coverDifference,
            whiteTextPixels: whiteTextPixels
        )
    }

    static func checkerImage(width: Int, height: Int) throws -> CIImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ProjectError("Cannot create the annotation checker fixture.") }
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in stride(from: 0, to: width, by: 12) {
            context.setFillColor((x / 12).isMultiple(of: 2) ? CGColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1) : CGColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 6, height: height))
        }
        guard let image = context.makeImage() else { throw ProjectError("Cannot create the annotation checker fixture.") }
        return CIImage(cgImage: image)
    }

    @MainActor static func frameDifference(_ lhs: PreparedComposition, _ rhs: PreparedComposition, at seconds: Double) async throws -> Difference {
        let left = try await frame(from: lhs, at: seconds)
        let right = try await frame(from: rhs, at: seconds)
        return try pixelDifference(left, right, sampleWidth: 480, sampleHeight: 270)
    }

    @MainActor static func frame(from prepared: PreparedComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: prepared.asset)
        generator.videoComposition = prepared.video
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000)).image
    }

    @MainActor static func frame(from asset: AVAsset, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000)).image
    }

    static func pixelDifference(_ lhs: CGImage, _ rhs: CGImage, sampleWidth: Int, sampleHeight: Int) throws -> Difference {
        let left = try pixels(lhs, width: sampleWidth, height: sampleHeight)
        let right = try pixels(rhs, width: sampleWidth, height: sampleHeight)
        var total = 0.0
        var changed = 0
        var weightedX = 0.0
        var weightedY = 0.0
        var weight = 0.0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let offset = (y * sampleWidth + x) * 4
                let difference = (0..<3).reduce(0.0) { $0 + abs(Double(left[offset + $1]) - Double(right[offset + $1])) }
                total += difference
                if difference > 30 {
                    changed += 1
                    weightedX += Double(x) * difference
                    weightedY += Double(y) * difference
                    weight += difference
                }
            }
        }
        return Difference(
            mean: total / Double(sampleWidth * sampleHeight * 3),
            changedPixels: changed,
            centroidX: weight > 0 ? weightedX / weight / Double(sampleWidth - 1) : 0,
            centroidY: weight > 0 ? weightedY / weight / Double(sampleHeight - 1) : 0
        )
    }

    static func pixelDifference(_ lhs: CIImage, _ rhs: CIImage, bounds: CGRect) throws -> Difference {
        let width = Int(bounds.width.rounded())
        let height = Int(bounds.height.rounded())
        let left = try pixels(lhs, bounds: bounds, width: width, height: height)
        let right = try pixels(rhs, bounds: bounds, width: width, height: height)
        var total = 0.0
        var changed = 0
        for index in stride(from: 0, to: left.count, by: 4) {
            let difference = (0..<3).reduce(0.0) { $0 + abs(Double(left[index + $1]) - Double(right[index + $1])) }
            total += difference
            if difference > 30 { changed += 1 }
        }
        return Difference(mean: total / Double(width * height * 3), changedPixels: changed, centroidX: 0, centroidY: 0)
    }

    static func regionalDifferences(_ lhs: CIImage, _ rhs: CIImage, normalizedROI: CGRect) throws -> (inside: Double, outside: Double) {
        let bounds = lhs.extent
        let width = Int(bounds.width.rounded())
        let height = Int(bounds.height.rounded())
        let left = try pixels(lhs, bounds: bounds, width: width, height: height)
        let right = try pixels(rhs, bounds: bounds, width: width, height: height)
        var insideTotal = 0.0
        var insideCount = 0
        var outsideTotal = 0.0
        var outsideCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let nx = (Double(x) + 0.5) / Double(width)
                let ny = (Double(y) + 0.5) / Double(height)
                let offset = (y * width + x) * 4
                let difference = (0..<3).reduce(0.0) { $0 + abs(Double(left[offset + $1]) - Double(right[offset + $1])) } / 3
                if normalizedROI.contains(CGPoint(x: nx, y: ny)) {
                    insideTotal += difference; insideCount += 1
                } else {
                    outsideTotal += difference; outsideCount += 1
                }
            }
        }
        return (insideTotal / Double(insideCount), outsideTotal / Double(outsideCount))
    }

    static func pixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drew = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw ProjectError("Cannot sample annotation frames.") }
        return data
    }

    static func pixels(_ image: CIImage, bounds: CGRect, width: Int, height: Int) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.cacheIntermediates: false]).render(
            image,
            toBitmap: &data,
            rowBytes: width * 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
        return data
    }

    static func averageRegion(_ image: CGImage, normalized: CGRect) throws -> RegionAverage {
        let width = 480
        let height = 270
        let data = try pixels(image, width: width, height: height)
        var red: [Double] = []
        var green: [Double] = []
        var blue: [Double] = []
        for y in 0..<height where normalized.minY <= Double(y) / Double(height) && Double(y) / Double(height) < normalized.maxY {
            for x in 0..<width where normalized.minX <= Double(x) / Double(width) && Double(x) / Double(width) < normalized.maxX {
                let offset = (y * width + x) * 4
                red.append(Double(data[offset])); green.append(Double(data[offset + 1])); blue.append(Double(data[offset + 2]))
            }
        }
        let average: ([Double]) -> Double = { $0.reduce(0, +) / Double($0.count) }
        let spread = [red, green, blue].map { ($0.max() ?? 0) - ($0.min() ?? 0) }.max() ?? 0
        return RegionAverage(red: average(red), green: average(green), blue: average(blue), spread: spread)
    }

    static func makeMP3(at url: URL, duration: Double) throws {
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/ffmpeg" }
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] + pathCandidates
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ProjectError("Annotation media validation needs ffmpeg to create a local synthetic MP3 hold fixture.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-v", "error", "-nostdin", "-y", "-f", "lavfi", "-i",
            "sine=frequency=920:sample_rate=48000:duration=\(duration)",
            "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "96k", url.path,
        ]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown ffmpeg error"
            throw ProjectError("Cannot create annotation MP3 fixture: \(detail.prefix(500))")
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ProjectError("Cannot prepare the annotated preview PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ProjectError("Cannot write the annotated preview PNG.")
        }
    }

    static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw ProjectError(message) }
        return value
    }
}
