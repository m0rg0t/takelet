import CoreGraphics
import CoreImage
import Foundation
import ProjectCore

/// Immutable, thread-safe cursor compositor. Decode a custom PNG before initialization;
/// rendering performs no file access and never creates an AppKit cursor.
public final class CursorRenderer: @unchecked Sendable {
    private struct Sprite: @unchecked Sendable {
        let image: CIImage
        let size: CGSize
    }

    private let style: CursorStyle
    private let timeline: CursorTimeline
    private let cursor: Sprite
    private let halo: Sprite

    public init(samples: [CursorSample], style: CursorStyle, customImage: CGImage? = nil) throws {
        try style.validate()
        if style.shape == .customImage {
            guard let customImage else { throw ProjectError("The custom cursor PNG could not be decoded.") }
            guard customImage.width > 0, customImage.height > 0,
                  customImage.width <= 8192, customImage.height <= 8192 else {
                throw ProjectError("The custom cursor PNG is too large or invalid.")
            }
            cursor = Self.customSprite(customImage, width: style.size)
        } else {
            cursor = try Self.vectorSprite(style: style)
        }
        halo = try Self.haloSprite(color: style.color, diameter: style.size * 2.4)
        self.style = style
        timeline = CursorTimeline(samples: samples, smoothing: style.smoothing)
    }

    /// Returns a transparent cursor layer in untransformed source-pixel coordinates.
    /// Composite this layer with the source frame before applying Takelet's zoom transform.
    public func overlay(sourceExtent: CGRect, sourceTime: Double) -> CIImage? {
        guard !style.hidden, sourceExtent.width.isFinite, sourceExtent.height.isFinite,
              sourceExtent.width > 0, sourceExtent.height > 0,
              let frame = timeline.frame(at: sourceTime) else { return nil }

        var result: CIImage?
        if style.clickHalo, let event = frame.halo {
            let center = sourcePoint(event.position, in: sourceExtent)
            let scale = 0.55 + event.progress * 0.75
            let scaled = halo.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let position = CGAffineTransform(
                translationX: center.x - scaled.extent.midX,
                y: center.y - scaled.extent.midY
            )
            result = Self.applyingOpacity(1 - event.progress, to: scaled.transformed(by: position))
        }

        let position = sourcePoint(frame.position, in: sourceExtent)
        let hotspotX = style.hotspotX * cursor.size.width
        let hotspotY = (1 - style.hotspotY) * cursor.size.height
        let placedCursor = cursor.image.transformed(by: CGAffineTransform(
            translationX: position.x - hotspotX - cursor.image.extent.minX,
            y: position.y - hotspotY - cursor.image.extent.minY
        ))
        result = result.map { placedCursor.composited(over: $0) } ?? placedCursor
        return result?.cropped(to: sourceExtent)
    }

    /// Draws onto an untransformed source frame. The caller then applies fit, crop, and zoom once.
    public func composite(over source: CIImage, sourceTime: Double) -> CIImage {
        guard let overlay = overlay(sourceExtent: source.extent, sourceTime: sourceTime) else { return source }
        return overlay.composited(over: source).cropped(to: source.extent)
    }

    private func sourcePoint(_ point: CursorPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX + extent.width * point.x, y: extent.minY + extent.height * (1 - point.y))
    }

    private static func customSprite(_ image: CGImage, width: Double) -> Sprite {
        let source = CIImage(cgImage: image)
        let scale = width / source.extent.width
        let rendered = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return Sprite(image: rendered, size: rendered.extent.size)
    }

    private static func vectorSprite(style: CursorStyle) throws -> Sprite {
        let side = max(1, Int(ceil(style.size)))
        guard let context = bitmapContext(width: side, height: side) else {
            throw ProjectError("Cannot prepare the cursor image.")
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let color = cgColor(style.color)
        let outline = contrastingOutline(for: style.color)
        let size = CGFloat(side)

        switch style.shape {
        case .arrow:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: size * 0.08, y: size * 0.94))
            path.addLine(to: CGPoint(x: size * 0.10, y: size * 0.17))
            path.addLine(to: CGPoint(x: size * 0.29, y: size * 0.35))
            path.addLine(to: CGPoint(x: size * 0.43, y: size * 0.08))
            path.addLine(to: CGPoint(x: size * 0.57, y: size * 0.16))
            path.addLine(to: CGPoint(x: size * 0.42, y: size * 0.43))
            path.addLine(to: CGPoint(x: size * 0.68, y: size * 0.46))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color)
            context.setStrokeColor(outline)
            context.setLineWidth(max(1.5, size * 0.055))
            context.drawPath(using: .fillStroke)
        case .circle:
            let inset = max(2, size * 0.12)
            context.setFillColor(color.copy(alpha: style.color.alpha * 0.3) ?? color)
            context.setStrokeColor(color)
            context.setLineWidth(max(2, size * 0.11))
            context.addEllipse(in: CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
            context.drawPath(using: .fillStroke)
        case .crosshair:
            let center = size / 2
            let gap = size * 0.17
            let inset = size * 0.08
            context.setStrokeColor(outline)
            context.setLineWidth(max(4, size * 0.16))
            addCrosshair(to: context, center: center, gap: gap, inset: inset, size: size)
            context.strokePath()
            context.setStrokeColor(color)
            context.setLineWidth(max(2, size * 0.08))
            addCrosshair(to: context, center: center, gap: gap, inset: inset, size: size)
            context.strokePath()
        case .customImage:
            throw ProjectError("A custom cursor must be prepared from its decoded PNG.")
        }
        guard let image = context.makeImage() else { throw ProjectError("Cannot prepare the cursor image.") }
        return Sprite(image: CIImage(cgImage: image), size: CGSize(width: side, height: side))
    }

    private static func haloSprite(color: CursorRGBA, diameter: Double) throws -> Sprite {
        let side = max(1, Int(ceil(diameter)))
        guard let context = bitmapContext(width: side, height: side) else {
            throw ProjectError("Cannot prepare the cursor click halo.")
        }
        let width = CGFloat(side)
        let line = max(2, width * 0.06)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setStrokeColor(cgColor(color))
        context.setLineWidth(line)
        context.addEllipse(in: CGRect(x: line, y: line, width: width - line * 2, height: width - line * 2))
        context.strokePath()
        guard let image = context.makeImage() else { throw ProjectError("Cannot prepare the cursor click halo.") }
        return Sprite(image: CIImage(cgImage: image), size: CGSize(width: side, height: side))
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
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

    private static func cgColor(_ color: CursorRGBA) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func contrastingOutline(for color: CursorRGBA) -> CGColor {
        let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        let value = luminance > 0.45 ? 0.08 : 0.95
        return CGColor(red: value, green: value, blue: value, alpha: color.alpha)
    }

    private static func addCrosshair(to context: CGContext, center: CGFloat, gap: CGFloat, inset: CGFloat, size: CGFloat) {
        context.move(to: CGPoint(x: center, y: inset))
        context.addLine(to: CGPoint(x: center, y: center - gap))
        context.move(to: CGPoint(x: center, y: center + gap))
        context.addLine(to: CGPoint(x: center, y: size - inset))
        context.move(to: CGPoint(x: inset, y: center))
        context.addLine(to: CGPoint(x: center - gap, y: center))
        context.move(to: CGPoint(x: center + gap, y: center))
        context.addLine(to: CGPoint(x: size - inset, y: center))
    }

    private static func applyingOpacity(_ opacity: Double, to image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, min(1, opacity)))
        ])
    }
}
