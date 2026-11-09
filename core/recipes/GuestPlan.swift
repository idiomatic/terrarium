import Foundation

extension GuestManifest {
    /// The plan for booting it: its kind, over the blank base disk (a macOS guest keeps its identity in the overlay).
    /// With `guest`, an overlay lies over that guest's layer, and what is saved is an overlay named for the guest's `id`.
    func plan(over guest: URL? = nil, in directory: URL) throws -> Plan {
        var plan = Plan(kind: kind, baseDisk: try Recipe.blankDisk(gigabytes: diskGB, in: directory), mac: kind == .macos ? MacPlan() : nil, installed: true, diskGB: diskGB)
        if let guest {
            plan.installed = false
            plan.guestLayer = guest.appendingPathComponent(MacFiles.layer)
            plan.guestID = id
        }
        return plan
    }
}
