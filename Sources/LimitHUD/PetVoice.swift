import Foundation

/// Per-character speech for the mascot bubble. Each pet has its own voice;
/// lines rotate by `seed` (stable between refreshes) so the card feels alive.
///   mochi — soft & squishy baby-talk
///   neko  — aloof, sassy, judging you
///   boo   — deadpan spooky ghost
///   inu   — hyper, loyal, ALL CAPS doggo
enum PetVoice {
    static func title(style: String, state: String, seed: Int) -> String {
        let pool = lines[style]?[state] ?? lines["mochi"]![state] ?? ["…"]
        return pool[((seed % pool.count) + pool.count) % pool.count]
    }

    private static let lines: [String: [String: [String]]] = [
        "mochi": [
            "healthy": ["all squishy & happy ♪", "bouncin' along~", "soft 'n' full :3", "we're okayy~"],
            "caution": ["uh-oh, squishing…", "gettin' a lil flat…", "wobble wobble…", "hold me?"],
            "danger":  ["squish… help!!", "I'm melting!!", "eep!! so low!!", "save meee"],
            "dead":    ["…melted. x_x", "I'm a puddle now", "splat. see ya~", "reset me pls"],
            "party":   ["boing!! we're back!", "full 'n' fluffy!!", "yayyy refill~", "bouncy again ♪"],
            "sleep":   ["zzz… mochi nap", "five more minutes…"],
        ],
        "neko": [
            "healthy": ["whatever, we're fine", "obviously full.", "purrfectly fine", "I allow this."],
            "caution": ["…mildly concerned.", "watch it, human.", "hmph, halfway.", "I'm judging you."],
            "danger":  ["this is on you.", "fix it. now.", "ugh, nearly out.", "do something, human."],
            "dead":    ["see? told you.", "done. nap time.", "your fault, not mine.", "wake me at reset."],
            "party":   ["fine, I'm pleased.", "acceptable. full.", "…purr. we're back.", "you may celebrate."],
            "sleep":   ["…busy. shoo.", "loading, peasant."],
        ],
        "boo": [
            "healthy": ["…still here…", "boo. all good.", "haunting peacefully", "…plenty… ooo"],
            "caution": ["…fading a little…", "ooo, watch out…", "…getting thin…", "spooky, half left"],
            "danger":  ["…I grow weak…", "boo… so low…", "the void nears…", "…help… ooo"],
            "dead":    ["…goodbye…", "I am but a husk", "…off to reset…", "boo. deceased."],
            "party":   ["…resurrected…", "BOO! we're back", "alive again… ish", "…full… spooky"],
            "sleep":   ["…materializing…", "…one moment…"],
        ],
        "inu": [
            "healthy": ["BORK! all good!!", "we're THRIVING!", "tail wag intensifies", "best day ever!!"],
            "caution": ["uh, boss? halfway!", "*concerned woof*", "should we slow??", "hmm hmm hmm…"],
            "danger":  ["BARK BARK!! low!!", "RED ALERT WOOF", "almost out boss!!", "do something!!"],
            "dead":    ["*sad whine* x_x", "tuckered out…", "nap til reset zzz", "I did my best…"],
            "party":   ["BORK BORK YAY!!", "REFILL!! ZOOMIES", "WE'RE BACK!!", "happiest doggo!!"],
            "sleep":   ["*sniff sniff*…", "booting woof…"],
        ],
    ]
}
