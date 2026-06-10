import Foundation

@objc protocol HelperProtocol {
    func deleteBackups(
        _ backups: [[String: String]],
        withReply reply: @escaping ([String: String]) -> Void
    )

    func ping(withReply reply: @escaping (Bool) -> Void)

    func version(withReply reply: @escaping (String) -> Void)
}
