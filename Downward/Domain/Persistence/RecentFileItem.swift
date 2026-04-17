import Foundation

struct RecentFileItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let workspaceID: String
    let workspaceRootPath: String
    let relativePath: String
    let displayName: String
    let lastOpenedAt: Date

    nonisolated init(
        workspaceID: String? = nil,
        workspaceRootPath: String,
        relativePath: String,
        displayName: String,
        lastOpenedAt: Date
    ) {
        let normalizedWorkspaceRootPath = WorkspaceIdentity.normalizedPath(workspaceRootPath)
        self.workspaceID = workspaceID ?? WorkspaceIdentity.legacyPathID(forPath: normalizedWorkspaceRootPath)
        self.workspaceRootPath = normalizedWorkspaceRootPath
        self.relativePath = relativePath
        self.displayName = displayName
        self.lastOpenedAt = lastOpenedAt
    }

    nonisolated var id: String {
        "\(workspaceID)::\(relativePath)"
    }

    nonisolated func url(in workspaceRootURL: URL) -> URL? {
        WorkspaceRelativePath.resolveExisting(relativePath, within: workspaceRootURL)
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case workspaceRootPath
        case relativePath
        case displayName
        case lastOpenedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let workspaceRootPath = try container.decode(String.self, forKey: .workspaceRootPath)

        self.init(
            workspaceID: try container.decodeIfPresent(String.self, forKey: .workspaceID),
            workspaceRootPath: workspaceRootPath,
            relativePath: try container.decode(String.self, forKey: .relativePath),
            displayName: try container.decode(String.self, forKey: .displayName),
            lastOpenedAt: try container.decode(Date.self, forKey: .lastOpenedAt)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(workspaceRootPath, forKey: .workspaceRootPath)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    }
}
