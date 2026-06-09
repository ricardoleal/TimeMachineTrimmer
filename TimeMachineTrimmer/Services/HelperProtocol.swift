import Foundation

@objc protocol HelperProtocol {
    func deleteBackups(
        _ backups: [HelperBackup],
        withReply reply: @escaping ([String: String]) -> Void
    )

    func ping(withReply reply: @escaping (Bool) -> Void)

    func version(withReply reply: @escaping (String) -> Void)
}

@objc(HelperBackup) class HelperBackup: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let id: String
    let path: String
    let snapshotName: String
    let volumePath: String

    init(id: String, path: String, snapshotName: String, volumePath: String) {
        self.id = id
        self.path = path
        self.snapshotName = snapshotName
        self.volumePath = volumePath
    }

    required init?(coder: NSCoder) {
        id = coder.decodeObject(of: NSString.self, forKey: "id") as String? ?? ""
        path = coder.decodeObject(of: NSString.self, forKey: "path") as String? ?? ""
        snapshotName = coder.decodeObject(of: NSString.self, forKey: "snapshotName") as String? ?? ""
        volumePath = coder.decodeObject(of: NSString.self, forKey: "volumePath") as String? ?? ""
    }

    func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(path as NSString, forKey: "path")
        coder.encode(snapshotName as NSString, forKey: "snapshotName")
        coder.encode(volumePath as NSString, forKey: "volumePath")
    }
}
