import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication.delegate is weak; keep a strong ref alive for the process lifetime.
    objc_setAssociatedObject(app, "limithud.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory) // agent app: no Dock icon, no menu bar item
    app.run()
}
