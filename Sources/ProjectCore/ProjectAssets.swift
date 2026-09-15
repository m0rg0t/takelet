import Foundation

public extension Project {
    var assetPaths: Set<String> {
        var paths = Set(narrations.compactMap(\.audioFile))
        if let image = cursorStyle.imageFile { paths.insert(image) }
        return paths
    }
}

public extension ProjectStore {
    /// Only referenced immutable assets are required; unused retakes may remain for Undo.
    static func assetURLs(for project: Project, in directory: URL) throws -> [String: URL] {
        try Dictionary(uniqueKeysWithValues: project.assetPaths.map { path in
            let url = try assetURL(path, in: directory)
            try validateAssetFile(url, path: path)
            return (path, url)
        })
    }

    static func assetURL(_ path: String, in directory: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "media",
              ["cursors", "narration"].contains(components[1]),
              path.range(of: #"^media/(cursors/[A-Za-z0-9_-]+\.png|narration/[A-Za-z0-9_-]+\.mp3)$"#, options: .regularExpression) != nil else {
            throw ProjectError("Invalid project asset path.")
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let target = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { throw ProjectError("A project asset points outside the project folder.") }
        return target
    }

    static func validateAssetFile(_ url: URL, path: String) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let limit = path.hasSuffix(".png") ? 8 * 1024 * 1024 : 64 * 1024 * 1024
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= limit else {
            throw ProjectError("A cursor or narration asset is empty, too large, or missing.")
        }
    }

    /// Copy assets before atomically writing metadata. Never overwrite an existing retake.
    static func copyAssets(for project: Project, from sources: [String: URL], to directory: URL) throws {
        for path in project.assetPaths.sorted() {
            let destination = try assetURL(path, in: directory)
            if let source = sources[path] {
                try validateAssetFile(source, path: path)
                if source.resolvingSymlinksInPath() == destination { continue }
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard FileManager.default.contentsEqual(atPath: source.path, andPath: destination.path) else {
                        throw ProjectError("An existing project asset has different contents. Keep both files under different names.")
                    }
                } else {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
            try validateAssetFile(destination, path: path)
        }
    }
}
