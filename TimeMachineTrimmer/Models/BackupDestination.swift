import Foundation

struct BackupDestination: Identifiable, Codable {
    let id: String
    let name: String
    let kind: String
    let mountPoint: String?
}
