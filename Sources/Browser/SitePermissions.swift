import Foundation

/// What the user allowed or refused each site to do, remembered until the app quits.
@MainActor
final class SitePermissions {
    enum Permission: String {
        /// Downloading files the user didn't click to download.
        case downloads
        case camera
        case microphone
    }

    private struct Key: Hashable {
        let site: String
        let permission: Permission
    }

    static let shared = SitePermissions()

    private var decisions: [Key: Bool] = [:]
    private var prompts: [String: Task<Bool?, Never>] = [:]

    /// Refused if any of the permissions was refused, allowed only once all of them were allowed.
    func decision(for permissions: Set<Permission>, on site: String) -> Bool? {
        let known = permissions.map { decisions[Key(site: site, permission: $0)] }
        if known.contains(false) { return false }
        return known.allSatisfy { $0 == true } ? true : nil
    }

    /// Asks only when the site's answer isn't known yet, sharing one prompt between requests that arrive together.
    /// A prompt that ends without an answer, because its tab closed, refuses without remembering it.
    func decide(_ permissions: Set<Permission>, on site: String,
                ask: @escaping @MainActor () async -> Bool?) async -> Bool {
        if let decision = decision(for: permissions, on: site) { return decision }
        let promptKey = ([site] + permissions.map(\.rawValue).sorted()).joined(separator: " ")
        if let prompt = prompts[promptKey] { return await prompt.value ?? false }
        let prompt = Task(operation: ask)
        prompts[promptKey] = prompt
        let answer = await prompt.value
        prompts[promptKey] = nil
        guard let isAllowed = answer else { return false }
        for permission in permissions {
            decisions[Key(site: site, permission: permission)] = isAllowed
        }
        return isAllowed
    }
}
