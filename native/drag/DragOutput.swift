import Foundation
import Darwin

/// Stage in the destination filesystem and publish with exclusive rename.
/// A failed job leaves no half-written result and never replaces a file/symlink.
enum DragOutput {
    static func write(input: URL, preferences: DragConvertPreferences, suffix: String = "", ext: String,
                      directoryOutput: Bool = false, baseName: String? = nil, build: (URL) throws -> Void) throws -> URL {
        let directory = preferences.outputDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? input.deletingLastPathComponent()
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        var template = Array(directory.appendingPathComponent(".nuphy-convert-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else { throw DragConvertError.output }
        let staging = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let payload = staging.appendingPathComponent(directoryOutput ? "pages" : "result.\(ext)")
        if directoryOutput { try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false) }
        try build(payload)
        let stem = String((baseName ?? input.deletingPathExtension().lastPathComponent).prefix(80)) + suffix
        for number in 0..<10_000 {
            let name = stem + (number == 0 ? "" : "-\(number)") + (directoryOutput ? "" : ".\(ext)")
            let output = directory.appendingPathComponent(name)
            if renamex_np(payload.path, output.path, UInt32(RENAME_EXCL)) == 0 { return output }
            guard errno == EEXIST else { throw DragConvertError.output }
        }
        throw DragConvertError.output
    }
    static func validate(_ input: URL, maxBytes: Int) throws {
        let resource = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resource.isRegularFile == true else { throw DragConvertError.unreadable }
        guard (resource.fileSize ?? Int.max) <= maxBytes else { throw DragConvertError.tooLarge }
    }
}
