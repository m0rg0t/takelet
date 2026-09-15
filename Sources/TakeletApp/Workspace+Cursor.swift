import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import ProjectCore

extension Workspace {
    func updateCursor(_ style: CursorStyle) {
        guard canEdit, var next = project, next.cursorMode == .separate else { return }
        next.cursorStyle = style
        if next == project || edit(next, name: "Change Cursor") { cursorDraft = nil }
    }

    func importCursorImage() {
        guard canEdit, project?.cursorMode == .separate else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try installCursorImage(from: url) }
        catch { self.error = error.localizedDescription }
    }

    func installCursorImage(from url: URL) throws {
        guard canEdit, var next = project, next.cursorMode == .separate else { return }
        try ProjectStore.validateAssetFile(url, path: "cursor.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...2048).contains(width), (1...2048).contains(height),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ProjectError("Choose a PNG image no larger than 2048×2048 pixels and 8 MB. Transparent backgrounds work best.")
        }
        let path = "media/cursors/\(UUID().uuidString).png"
        try stageAsset(Data(contentsOf: url), path: path)
        next.cursorStyle = cursorDraft ?? next.cursorStyle
        next.cursorStyle.shape = .customImage; next.cursorStyle.imageFile = path
        next.cursorStyle.hotspotX = 0.5; next.cursorStyle.hotspotY = 0.5
        if edit(next, name: "Import Cursor Image") {
            cursorDraft = nil
            status = "Custom cursor imported. Adjust its hotspot to the point that marks a click."
        }
    }

    func stageAsset(_ data: Data, path: String) throws {
        let destination = try ProjectStore.assetURL(path, in: assetDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectError("An asset already uses this filename.") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        try ProjectStore.validateAssetFile(destination, path: path)
        assetURLs[path] = destination
    }
}
