import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ProjectCore

/// Immutable, thread-safe compositor for source-time callouts and privacy masks.
///
/// Geometry and style lengths are evaluated against each input image's extent, so one
/// renderer can be shared by full-resolution export and a proportionally resized editor
/// preview. Create the renderer away from the video render callback: text and arrow
/// rasterization happens only during initialization.
public final class AnnotationRenderer: @unchecked Sendable {
    private struct Sprite: @unchecked Sendable {
        let image: CIImage
    }

    private struct Prepared: Sendable {
        let annotation: Annotation
        let sprite: Sprite?
    }

    private let sourceSize: CGSize
    private let callouts: [Prepared]
    private let masks: [Prepared]

    public init(annotations: [Annotation], sourceWidth: Int, sourceHeight: Int) throws {
        guard sourceWidth > 0, sourceHeight > 0, sourceWidth <= 16_384, sourceHeight <= 16_384 else {
            throw ProjectError("Annotation rendering requires valid source dimensions.")
        }
        guard annotations.count <= 64 else {
            throw ProjectError("A project supports up to 64 annotations.")
        }

        sourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        var prepared: [Prepared] = []
        prepared.reserveCapacity(annotations.count)
        for annotation in annotations {
            try annotation.validate(duration: annotation.end)
            let bounds = Self.pixelBounds(annotation.bounds, in: CGRect(origin: .zero, size: sourceSize))
            let sprite: Sprite?
            switch annotation.kind {
            case .arrow:
                sprite = Sprite(image: try Self.makeArrow(annotation, targetSize: bounds.size, sourceSize: sourceSize))
            case .text:
                sprite = Sprite(image: try Self.makeText(annotation, targetSize: bounds.size, sourceSize: sourceSize))
            case .frame, .blur, .cover:
                sprite = nil
            }
            prepared.append(Prepared(annotation: annotation, sprite: sprite))
        }
        callouts = prepared.filter { !$0.annotation.kind.isMask }
        masks = prepared.filter { $0.annotation.kind.isMask }
    }

    /// Composites visible annotations in untransformed source-pixel coordinates.
    /// Call this after drawing a separate cursor and before Takelet's zoom/fit transform.
    /// Callouts retain project list order, followed by masks in project list order.
    public func composite(over source: CIImage, sourceTime: Double) -> CIImage {
        let extent = source.extent
        guard sourceTime.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return source }

        var result = source
        for item in callouts where item.annotation.isVisible(atSource: sourceTime) {
            result = compositeCallout(item, over: result, extent: extent)
        }
        for item in masks where item.annotation.isVisible(atSource: sourceTime) {
            result = compositeMask(item.annotation, over: result, extent: extent)
        }
        return result.cropped(to: extent)
    }

    private func compositeCallout(_ item: Prepared, over source: CIImage, extent: CGRect) -> CIImage {
        let annotation = item.annotation
        let bounds = Self.pixelBounds(annotation.bounds, in: extent)
        switch annotation.kind {
        case .arrow, .text:
            guard let sprite = item.sprite?.image,
                  sprite.extent.width > 0, sprite.extent.height > 0 else { return source }
            let scaleX = bounds.width / sprite.extent.width
            let scaleY = bounds.height / sprite.extent.height
            let placed = sprite
                .transformed(by: CGAffineTransform(translationX: -sprite.extent.minX, y: -sprite.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
                .cropped(to: extent)
            return placed.composited(over: source).cropped(to: extent)
        case .frame:
            let width = Self.stylePixels(annotation.strokeWidth, in: extent)
            let color = CIImage(color: Self.ciColor(annotation.color))
            let rectangles = [
                CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: min(width, bounds.height)),
                CGRect(x: bounds.minX, y: max(bounds.minY, bounds.maxY - width), width: bounds.width, height: min(width, bounds.height)),
                CGRect(x: bounds.minX, y: bounds.minY + min(width, bounds.height), width: min(width, bounds.width), height: max(0, bounds.height - min(width, bounds.height) * 2)),
                CGRect(x: max(bounds.minX, bounds.maxX - width), y: bounds.minY + min(width, bounds.height), width: min(width, bounds.width), height: max(0, bounds.height - min(width, bounds.height) * 2)),
            ]
            return rectangles.reduce(source) { image, rectangle in
                guard rectangle.width > 0, rectangle.height > 0 else { return image }
                return color.cropped(to: rectangle).composited(over: image)
            }.cropped(to: extent)
        case .blur, .cover:
            return source
        }
    }

    private func compositeMask(_ annotation: Annotation, over source: CIImage, extent: CGRect) -> CIImage {
        let bounds = Self.pixelBounds(annotation.bounds, in: extent)
        switch annotation.kind {
        case .blur:
            let radius = Self.stylePixels(annotation.blurRadius, in: extent)
            let blurred = source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: bounds)
            return blurred.composited(over: source).cropped(to: extent)
        case .cover:
            return CIImage(color: Self.ciColor(annotation.color))
                .cropped(to: bounds)
                .composited(over: source)
                .cropped(to: extent)
        case .arrow, .frame, .text:
            return source
        }
    }

    private static func pixelBounds(_ bounds: AnnotationBounds, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + extent.width * bounds.x,
            y: extent.maxY - extent.height * (bounds.y + bounds.height),
            width: extent.width * bounds.width,
            height: extent.height * bounds.height
        )
    }

    private static func stylePixels(_ normalized: Double, in extent: CGRect) -> Double {
        max(0.5, normalized * min(extent.width, extent.height))
    }

    private static func ciColor(_ color: AnnotationColor) -> CIColor {
        CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    private static func cgColor(_ color: AnnotationColor) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    private static func makeArrow(_ annotation: Annotation, targetSize: CGSize, sourceSize: CGSize) throws -> CIImage {
        let raster = rasterSize(for: targetSize)
        guard let context = bitmapContext(size: raster) else {
            throw ProjectError("Cannot prepare an annotation arrow.")
        }
        let sx = raster.width / targetSize.width
        let sy = raster.height / targetSize.height
        let lineWidth = max(1, annotation.strokeWidth * min(sourceSize.width, sourceSize.height) * min(sx, sy))
        let padding = min(min(raster.width, raster.height) * 0.2, lineWidth * 1.5)
        let start: CGPoint
        let end: CGPoint
        switch annotation.direction {
        case .downRight:
            start = CGPoint(x: padding, y: raster.height - padding)
            end = CGPoint(x: raster.width - padding, y: padding)
        case .downLeft:
            start = CGPoint(x: raster.width - padding, y: raster.height - padding)
            end = CGPoint(x: padding, y: padding)
        case .upRight:
            start = CGPoint(x: padding, y: padding)
            end = CGPoint(x: raster.width - padding, y: raster.height - padding)
        case .upLeft:
            start = CGPoint(x: raster.width - padding, y: padding)
            end = CGPoint(x: padding, y: raster.height - padding)
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(cgColor(annotation.color))
        context.setFillColor(cgColor(annotation.color))
        context.setLineWidth(lineWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let headLength = min(length * 0.38, max(lineWidth * 4.5, min(raster.width, raster.height) * 0.2))
        let halfWidth = min(headLength * 0.58, max(lineWidth * 2.1, headLength * 0.45))
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let perpendicular = CGPoint(x: -uy * halfWidth, y: ux * halfWidth)
        context.move(to: end)
        context.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
        context.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
        context.closePath()
        context.fillPath()
        guard let image = context.makeImage() else { throw ProjectError("Cannot prepare an annotation arrow.") }
        return CIImage(cgImage: image)
    }

    private static func makeText(_ annotation: Annotation, targetSize: CGSize, sourceSize: CGSize) throws -> CIImage {
        let raster = rasterSize(for: targetSize)
        guard let context = bitmapContext(size: raster) else {
            throw ProjectError("Cannot prepare annotation text.")
        }
        context.setFillColor(cgColor(annotation.color))
        context.fill(CGRect(origin: .zero, size: raster))

        let sx = raster.width / targetSize.width
        let sy = raster.height / targetSize.height
        let scale = min(sx, sy)
        let requestedSize = annotation.fontSize * min(sourceSize.width, sourceSize.height) * scale
        let padding = min(min(raster.width, raster.height) * 0.18, max(2, requestedSize * 0.22))
        let textRect = CGRect(x: padding, y: padding, width: raster.width - padding * 2, height: raster.height - padding * 2)
        guard textRect.width >= 2, textRect.height >= 2 else {
            throw ProjectError("Text annotation bounds are too small to render text.")
        }

        let minimumSize = max(3, min(7, requestedSize))
        var pointSize = min(requestedSize, textRect.height)
        var selected: CTFramesetter?
        while pointSize >= minimumSize - 0.001 {
            let font = CTFontCreateWithName("Helvetica Neue" as CFString, pointSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            let attributed = NSAttributedString(string: annotation.text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var fit = CFRange()
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                nil,
                CGSize(width: textRect.width, height: textRect.height),
                &fit
            )
            if fit.length == attributed.length, suggested.height <= textRect.height + 0.5 {
                selected = framesetter
                break
            }
            pointSize -= max(0.5, pointSize * 0.08)
        }
        guard let selected else {
            throw ProjectError("Text does not fit its annotation bounds. Enlarge the text box or shorten the text.")
        }

        context.setTextDrawingMode(.fill)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(selected, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        guard let image = context.makeImage() else { throw ProjectError("Cannot prepare annotation text.") }
        return CIImage(cgImage: image)
    }

    /// Caps each cached bitmap at roughly one mebibyte while retaining its aspect ratio.
    private static func rasterSize(for target: CGSize) -> CGSize {
        let width = max(2, target.width)
        let height = max(2, target.height)
        let maxDimensionScale = 1_024 / max(width, height)
        let maxAreaScale = sqrt((512 * 512) / (width * height))
        let scale = min(1, maxDimensionScale, maxAreaScale)
        return CGSize(width: max(2, ceil(width * scale)), height: max(2, ceil(height * scale)))
    }

    private static func bitmapContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
