import AppKit

func getActiveApplication() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
}
