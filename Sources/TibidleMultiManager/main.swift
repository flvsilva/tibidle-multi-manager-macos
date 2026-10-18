import AppKit

// One manager per user: a second launch brings the running window forward instead.
if let bundleID = Bundle.main.bundleIdentifier,
   let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .first(where: { $0 != NSRunningApplication.current }) {
    other.activate()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
