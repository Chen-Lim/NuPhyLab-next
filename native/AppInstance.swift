import Foundation
import Darwin
import ApplicationServices
import IOKit.hid

// Run the same signed host as a short-lived, read-only permission probe. A new
// process observes a grant even when the long-lived host/helper cache a denial.
// This entry point creates no NSApplication, event tap, worker or HID manager.
enum PermissionProbe {
    static let argument="--nuphylab-permission-probe"
    static let keys=["inputMonitoring","accessibility","canPostEvents"]
    static func snapshot()->[String:Any] {
        ["inputMonitoring":IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
         "accessibility":AXIsProcessTrusted(),
         "canPostEvents":IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted,"promptsRequested":false]
    }
    static func allGranted(_ value:[String:Any])->Bool {keys.allSatisfy{value[$0] as? Bool==true}}
    static func decode(_ data:Data)->[String:Any]? {
        guard data.count<=1024,let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              keys.allSatisfy({key in guard let number=value[key] as? NSNumber else{return false};return CFGetTypeID(number)==CFBooleanGetTypeID()}) else{return nil}
        return Dictionary(uniqueKeysWithValues:keys.map{($0,value[$0]!)})
    }
    static func runIfRequested() {
        guard CommandLine.arguments.count==2,CommandLine.arguments[1]==argument else{return}
        guard let data=try? JSONSerialization.data(withJSONObject:snapshot()) else{exit(1)}
        FileHandle.standardOutput.write(data);exit(0)
    }
}

struct AppInstanceOwner: Codable {
    let pid: Int32
    let bundleIdentifier: String
    let executablePath: String
}

// The descriptor stays open for the host lifetime, but must never reach Node or
// HIDBridge. The kernel releases this lock even after an unexpected host exit.
final class AppInstanceLock {
    enum Acquisition {
        case acquired(AppInstanceLock)
        case existing(AppInstanceOwner?)
    }
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }

    static func acquire(directory: URL, bundleIdentifier: String, executableURL: URL) throws -> Acquisition {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("app-instance.lock")
        let fd = Darwin.open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var keep = false
        defer { if !keep { Darwin.close(fd) } }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_uid == getuid(),
              attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1 else {
            throw POSIXError(.EPERM)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            guard code == EWOULDBLOCK || code == EAGAIN else {
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = pread(fd, &bytes, bytes.count, 0)
            let owner = count > 0 ? try? JSONDecoder().decode(AppInstanceOwner.self, from: Data(bytes.prefix(count))) : nil
            return .existing(owner)
        }
        let owner = AppInstanceOwner(pid: getpid(), bundleIdentifier: bundleIdentifier,
                                     executablePath: executableURL.resolvingSymlinksInPath().path)
        let bytes = try JSONEncoder().encode(owner)
        guard ftruncate(fd, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let written = bytes.withUnsafeBytes { buffer in pwrite(fd, buffer.baseAddress, buffer.count, 0) }
        guard written == bytes.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        keep = true
        return .acquired(AppInstanceLock(descriptor: fd))
    }
}

struct AppUpdateHandoff: Codable {
    let token: String
    let sourcePID: Int32
    let targetVersion: String
    let createdAt: TimeInterval
    var acknowledgedPID: Int32?

    func isCurrent(token: String, version: String, now: TimeInterval) -> Bool {
        self.token == token && targetVersion == version && now >= createdAt && now - createdAt < 60
    }

    static func read(from file: URL) -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write(to file: URL) throws {
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

// A single recovery after a live TCC grant. Some macOS releases keep an old
// process's event authorization cached even after a fresh tap is attempted.
struct PermissionCaptureRecovery {
    var previousGranted:Bool?
    var grantAt:TimeInterval?
    var attempted=false
    mutating func observe(granted:Bool,captureReady:Bool,now:TimeInterval,freshGrantNeedsRelaunch:Bool=false) {
        if !granted {grantAt=nil}
        else if previousGranted==false || (freshGrantNeedsRelaunch && grantAt==nil) {grantAt=now}
        previousGranted=granted
        if captureReady {grantAt=nil}
    }
    mutating func shouldRecover(now:TimeInterval,idle:Bool)->Bool {
        guard !attempted,idle,let grantAt=grantAt,now>=grantAt+3 else{return false}
        attempted=true;return true
    }
}

enum PermissionAppRelaunch {
    static let argument="--nuphylab-permission-relaunch"
    static var file:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Air Studio/permission-relaunch.json")}
    static func validatedHandoff()->AppUpdateHandoff? {
        guard let index=CommandLine.arguments.firstIndex(of:argument),CommandLine.arguments.count==index+2,
              let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String,
              let record=AppUpdateHandoff.read(from:file),record.sourcePID>0,
              record.isCurrent(token:CommandLine.arguments[index+1],version:version,now:Date().timeIntervalSince1970) else{return nil}
        return record
    }
    static func launch() throws {
        guard let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String else{throw POSIXError(.EINVAL)}
        let record=AppUpdateHandoff(token:UUID().uuidString,sourcePID:getpid(),targetVersion:version,createdAt:Date().timeIntervalSince1970,acknowledgedPID:nil)
        try record.write(to:file)
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/open")
        process.arguments=["-n",Bundle.main.bundleURL.path,"--args",argument,record.token]
        try process.run()
    }
}
