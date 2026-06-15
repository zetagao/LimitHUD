import AppKit

/// Loads illustration / video-frame assets bundled in the app's `Resources/pets`.
///
/// Clips are named `<character>-<group>-v<k>-NN.png`:
///   character ∈ cat | dog | ghost | mochi   (maps from petStyle neko/inu/boo/mochi)
///   group     ∈ idle, stretch, loaf, walk, excited, …  (behaviors)
///   k         = which take of that behavior (so a behavior can have variants)
///   NN        = frame index within the take
///
/// Everything is probed against the bundle, so a partial set still works — drop
/// in `cat-walk-v0-00.png …` and the scheduler starts using it; ship nothing for
/// the dog and it falls back to the procedural pet.
@MainActor
enum PetImage {
    /// Known behavior groups, base ("idle") first. Order here is the catalog we
    /// probe; only the ones actually present are returned by `groups(style:)`.
    static let catalog = ["idle", "stretch", "loaf", "lie", "walk", "pace", "excited", "play", "jump", "sit"]

    /// Settings stores petStyle as mochi/neko/boo/inu; assets use friendly names.
    private static func character(_ style: String) -> String {
        switch style {
        case "neko": return "cat"
        case "inu":  return "dog"
        case "boo":  return "ghost"
        default:     return "mochi"
        }
    }

    private static var groupCache: [String: [String]] = [:]

    /// Which behavior groups have assets for this character (idle first if present).
    static func groups(style: String) -> [String] {
        let c = character(style)
        if let g = groupCache[c] { return g }
        let present = catalog.filter { bundled(String(format: "%@-%@-v0-00", c, $0)) != nil }
        groupCache[c] = present
        return present
    }

    /// True if any clip (or a static illustration) exists — picks image vs. procedural.
    static func hasAssets(style: String) -> Bool {
        !groups(style: style).isEmpty || load(style: style) != nil
    }

    private static var clipCache: [String: [[NSImage]]] = [:]

    /// Every take in a behavior group: `<char>-<group>-v<k>-NN.png` → [[frames]].
    /// Empty if the group has no assets.
    static func clips(style: String, group: String) -> [[NSImage]] {
        let c = character(style)
        let key = "\(c)/\(group)"
        if let cached = clipCache[key] { return cached }
        var result: [[NSImage]] = []
        var k = 0
        while true {
            var imgs: [NSImage] = []
            var i = 0
            while let img = bundled(String(format: "%@-%@-v%d-%02d", c, group, k, i)) { imgs.append(img); i += 1 }
            if imgs.isEmpty { break }
            result.append(imgs); k += 1
        }
        clipCache[key] = result
        return result
    }

    private static var loadCache: [String: NSImage?] = [:]

    /// Static fallback illustration: first idle frame, or a bundled `<char>-healthy.png`.
    static func load(style: String) -> NSImage? {
        let c = character(style)
        if let cached = loadCache[c] { return cached }
        let img = bundled("\(c)-idle-v0-00") ?? bundled("\(c)-healthy") ?? bundled("\(c)-idle")
        loadCache[c] = img
        return img
    }

    private static func bundled(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "pets")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Pre-load every pet's frames into cache so switching characters is instant.
    /// Without this, the first switch to a pet does ~140 synchronous file loads on
    /// the main thread, freezing the UI on the *previous* pet's frame (a flash).
    static func warmAll() {
        for style in ["mochi", "neko", "inu", "boo"] {
            for g in groups(style: style) {
                for clip in clips(style: style, group: g) {
                    // touch the first frame so its PNG header/decode is ready
                    _ = clip.first?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
            }
        }
    }
}
