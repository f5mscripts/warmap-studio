import CoreGraphics
import Foundation

/// A small piece of pixel art, authored as rows of characters.
///
/// Every marker in the pixel style — unit counters, battle markers — is drawn from
/// one of these rather than from an emoji or an SF Symbol. A glyph rendered at 12
/// pixels and blown up 5× is a blurry glyph; a 12×12 sprite blown up 5× is a sprite.
///
/// The art is written as text on purpose. It is the only form in which a
/// twelve-pixel tank can be read, reviewed and corrected in a diff, and it costs
/// nothing at runtime: the rows are turned into horizontal runs once, and each run
/// is a single filled rectangle.
public struct PixelSprite: Equatable, Sendable {

    /// What colour a pixel takes. Kept abstract so one sprite serves every country:
    /// `body` is filled with the owner's colour at draw time.
    public enum Tone: Character, Sendable {
        /// Transparent. Named `empty` rather than `none` so it is never confused
        /// with `Optional.none` at a use site.
        case empty = "."
        /// The dark outline colour.
        case ink = "k"
        /// The owning country's colour.
        case body = "b"
        /// A near-white highlight.
        case light = "l"
        /// Danger red, for explosions and attack arrows.
        case accent = "a"
    }

    /// A horizontal run of one tone — the unit this is actually drawn in.
    public struct Run: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let tone: Tone
    }

    public let rows: [String]

    public init(_ rows: [String]) {
        self.rows = rows
    }

    public var width: Int { rows.map(\.count).max() ?? 0 }
    public var height: Int { rows.count }

    /// The sprite as runs of equal tone, skipping transparent pixels.
    public var runs: [Run] {
        var result: [Run] = []
        for (y, row) in rows.enumerated() {
            var x = 0
            var runStart = 0
            var runTone = Tone.empty
            for character in row {
                let tone = Tone(rawValue: character) ?? .empty
                if tone != runTone {
                    if runTone != .empty, x > runStart {
                        result.append(Run(x: runStart, y: y, width: x - runStart, tone: runTone))
                    }
                    runTone = tone
                    runStart = x
                }
                x += 1
            }
            if runTone != .empty, x > runStart {
                result.append(Run(x: runStart, y: y, width: x - runStart, tone: runTone))
            }
        }
        return result
    }
}

// MARK: - Unit sprites

extension PixelSprite {

    /// The sprite drawn for a formation on the map.
    ///
    /// One per `ArmyIcon`. Section 4 of the plan widens `ArmyIcon` itself — new cases
    /// get their art here, and nothing else in the renderer changes.
    public static func army(_ icon: ArmyIcon) -> PixelSprite {
        switch icon {
        case .infantry: return rifleman
        case .machineGun: return machineGun
        case .airborne: return parachute
        case .marine: return marine
        case .partisan: return partisan
        case .cavalry: return horse
        case .armour: return tank
        case .lightTank: return lightTank
        case .heavyTank: return heavyTank
        case .tankDestroyer: return tankDestroyer
        case .armouredCar: return armouredCar
        case .artillery: return fieldGun
        case .howitzer: return howitzer
        case .rocketArtillery: return rocketLauncher
        case .antiAir: return antiAirGun
        case .airForce: return aeroplane
        case .fighter: return fighter
        case .bomber: return bomber
        case .diveBomber: return diveBomber
        case .heavyBomber: return heavyBomber
        case .transportPlane: return transportPlane
        case .reconnaissance: return scoutPlane
        case .helicopter: return helicopter
        case .jetFighter: return jetFighter
        case .fleet: return warship
        case .destroyer: return destroyer
        case .cruiser: return cruiser
        case .battleship: return battleship
        case .carrier: return carrier
        case .submarine: return submarine
        case .transportShip: return transportShip
        }
    }

    static let rifleman = PixelSprite([
        "............",
        "....kkk..k..",
        "...klllk.k..",
        "...kbbbk.k..",
        "....kkk..k..",
        "..kbbbbbkk..",
        ".kbbbbbbbk..",
        ".kbbbbbk.k..",
        "..kbbbk..k..",
        "..kb.bk.....",
        "..kk.kk.....",
        "............",
    ])

    static let tank = PixelSprite([
        "............",
        "............",
        "....kkkk....",
        "...kbbbbk...",
        "...kbbbbkkkk",
        ".kkkkkkkkk..",
        ".kbbbbbbbbk.",
        ".kbbbbbbbbk.",
        ".kkkkkkkkkk.",
        ".klklklklkk.",
        ".kkkkkkkkkk.",
        "............",
    ])

    static let horse = PixelSprite([
        "............",
        ".......kkk..",
        "......kbbbk.",
        "..kkkkkbbk..",
        ".kbbbbbbbk..",
        ".kbbbbbbk...",
        ".kbbbbbbk...",
        ".kk.kk.kk...",
        ".k..k..k....",
        ".k..k..k....",
        ".kk.kk.kk...",
        "............",
    ])

    static let parachute = PixelSprite([
        "...kkkkkk...",
        "..kllllllk..",
        ".kllllllllk.",
        "..kk.kk.kk..",
        "...k.kk.k...",
        "....k..k....",
        "....kbbk....",
        "...kbbbbk...",
        "....kbbk....",
        "....k..k....",
        "...kk..kk...",
        "............",
    ])

    static let marine = PixelSprite([
        "............",
        "....kkk.....",
        "...klllk....",
        "...kbbbk....",
        "..kbbbbbk...",
        "..kbbbbbk...",
        "...kbbbk....",
        "...kb.bk....",
        "............",
        ".kllkllkllk.",
        "..kllkllkll.",
        "............",
    ])

    static let fieldGun = PixelSprite([
        "..........k.",
        ".........kk.",
        "........kk..",
        ".......kk...",
        "......kk....",
        ".kkk.kk.....",
        "kbbbkk......",
        "kbkbbk.kkkk.",
        "kbbbkk......",
        ".kkk........",
        "............",
        "............",
    ])

    static let warship = PixelSprite([
        "............",
        "......k.....",
        "......k.....",
        "....kkkkk...",
        "....kbbbk...",
        "kkkkkbbbkkk.",
        "kbbbbbbbbbk.",
        ".kbbbbbbbk..",
        "..kkkkkkk...",
        "...llllll...",
        "............",
        "............",
    ])

    static let aeroplane = PixelSprite([
        "............",
        ".....kk.....",
        "....kbbk....",
        "....kbbk....",
        "kkkkkbbkkkkk",
        "kbbbbbbbbbbk",
        "kkkkkbbkkkkk",
        "....kbbk....",
        "...kkbbkk...",
        "...kbbbbk...",
        "....kkkk....",
        "............",
    ])

    static let partisan = PixelSprite([
        "......kkkkk.",
        "....kkkaaak.",
        "...klllkaak.",
        "...kbbbk.k..",
        "..kbbbbbkk..",
        "..kbbbbbk...",
        "...kbbbk....",
        "...kb.bk....",
        "...kb.bk....",
        "..kk...kk...",
        "............",
        "............",
    ])

    // MARK: Infantry

    static let machineGun = PixelSprite([
        "............",
        "............",
        "...kkkkkkkk.",
        "...kbbbbbbk.",
        "...kkkkkkkk.",
        "..kbbbk.....",
        "..kbbbk.....",
        "..kkkkk.....",
        "...k.k......",
        "..k...k.....",
        ".k.....k....",
        "............",
    ])

    // MARK: Armour

    static let lightTank = PixelSprite([
        "............",
        "............",
        "............",
        ".....kkk....",
        "....kbbbk...",
        "....kbbbkkkk",
        "..kkkkkkkk..",
        "..kbbbbbbk..",
        "..kkkkkkkk..",
        "..klklklkk..",
        "..kkkkkkkk..",
        "............",
    ])

    static let heavyTank = PixelSprite([
        "............",
        "....kkkkk...",
        "...kbbbbbk..",
        "...kbbbbbkkk",
        "...kbbbbbkkk",
        ".kkkkkkkkkk.",
        "kbbbbbbbbbbk",
        "kbbbbbbbbbbk",
        "kkkkkkkkkkkk",
        "klklklklklkk",
        "kkkkkkkkkkkk",
        "............",
    ])

    static let tankDestroyer = PixelSprite([
        "............",
        "............",
        "......kkkkkk",
        "....kkkbbk..",
        "...kbbbbbk..",
        "..kbbbbbbk..",
        ".kkkkkkkkkk.",
        ".kbbbbbbbbk.",
        ".kkkkkkkkkk.",
        ".klklklklkk.",
        ".kkkkkkkkkk.",
        "............",
    ])

    static let armouredCar = PixelSprite([
        "............",
        "............",
        ".....kkk....",
        "....kbbbkkkk",
        "..kkkkkkkk..",
        ".kbbbbbbbbk.",
        ".kbbbbbbbbk.",
        ".kkkkkkkkkk.",
        "..klk..klk..",
        "..klk..klk..",
        "..kkk..kkk..",
        "............",
    ])

    // MARK: Artillery

    static let howitzer = PixelSprite([
        "............",
        "........kk..",
        ".......kk...",
        "......kk....",
        "..kkkkk.....",
        ".kbbbbk.....",
        ".kbbbbkkkkkk",
        "klbbbblk....",
        "kllbbllk....",
        "klllllk.....",
        ".kkkkk......",
        "............",
    ])

    static let rocketLauncher = PixelSprite([
        "........kkk.",
        ".......kaak.",
        "......kaak..",
        ".....kaak...",
        "....kaak....",
        "...kkkk.....",
        "..kbbbbbk...",
        "..kbbbbbk...",
        "..kkkkkkk...",
        "..klk.klk...",
        "..kkk.kkk...",
        "............",
    ])

    static let antiAirGun = PixelSprite([
        "..kk...kk...",
        "..kk...kk...",
        "..kk...kk...",
        "..kkkkkkk...",
        "...kbbbk....",
        "..kbbbbbk...",
        ".kbbbbbbbk..",
        ".kkkkkkkkk..",
        "..klk.klk...",
        "..klk.klk...",
        "..kkk.kkk...",
        "............",
    ])

    // MARK: Aircraft

    static let fighter = PixelSprite([
        "............",
        "............",
        ".....kk.....",
        "....kllk....",
        "....kbbk....",
        "..kkkbbkkk..",
        "..kbbbbbbk..",
        "..kkkbbkkk..",
        "....kbbk....",
        "...kkbbkk...",
        "....kkkk....",
        "............",
    ])

    static let bomber = PixelSprite([
        "............",
        ".....kk.....",
        "....kbbk....",
        ".kk.kbbk.kk.",
        "kkkkkbbkkkkk",
        "kbbbbbbbbbbk",
        "kkkkkbbkkkkk",
        "....kbbk....",
        "...kkbbkk...",
        "...kbbbbk...",
        "....kkkk....",
        "............",
    ])

    static let diveBomber = PixelSprite([
        "............",
        ".....kk.....",
        "....kbbk....",
        "..kk.bb.kk..",
        ".kbbkbbkbbk.",
        ".kkkkbbkkkk.",
        "....kbbk....",
        "...kkbbkk...",
        "....kaak....",
        "....kaak....",
        "....kkkk....",
        "............",
    ])

    static let heavyBomber = PixelSprite([
        "............",
        ".....kk.....",
        "....kbbk....",
        ".k.k.kk.k.k.",
        "kkkkkbbkkkkk",
        "kbbbbbbbbbbk",
        "kkkkkbbkkkkk",
        "....kbbk....",
        "..kkkbbkkk..",
        "..kbbbbbbk..",
        "...kkkkkk...",
        "............",
    ])

    static let transportPlane = PixelSprite([
        "............",
        "....kkkk....",
        "...kbbbbk...",
        "kkkkbbbbkkkk",
        "kbbbbbbbbbbk",
        "kkkkbbbbkkkk",
        "...kbbbbk...",
        "...kbbbbk...",
        "..kkbbbbkk..",
        "..kbbbbbbk..",
        "...kkkkkk...",
        "............",
    ])

    static let scoutPlane = PixelSprite([
        "............",
        "....kllk....",
        "....kbbk....",
        "kkkkkbbkkkkk",
        "kbbbbbbbbbbk",
        "kkkkkbbkkkkk",
        "....kbbk....",
        "....kbbk....",
        "....kbbk....",
        "...kkbbkk...",
        "....kkkk....",
        "............",
    ])

    static let helicopter = PixelSprite([
        "kkkkkkkkkkk.",
        ".....k......",
        "...kkkkk....",
        "..kbbbbbk...",
        "..kbbbbbkkkk",
        "..kbbbbbk.kk",
        "..kkkkkkk.k.",
        "...k...k....",
        "..kkk.kkk...",
        "............",
        "............",
        "............",
    ])

    static let jetFighter = PixelSprite([
        "............",
        ".....kk.....",
        "....kbbk....",
        "....kbbk....",
        "...kkbbkk...",
        "..kbkbbkbk..",
        ".kbbkbbkbbk.",
        "kbbkkbbkkbbk",
        "kkk.kbbk.kkk",
        "....kbbk....",
        "...kkaakk...",
        "....kkkk....",
    ])

    // MARK: Naval

    static let destroyer = PixelSprite([
        "............",
        "............",
        "......k.....",
        "...kk.k.kk..",
        "...kbkkkbk..",
        "kkkkbbbbbkkk",
        "kbbbbbbbbbbk",
        ".kbbbbbbbbk.",
        "..kkkkkkkk..",
        "...llllll...",
        "............",
        "............",
    ])

    static let cruiser = PixelSprite([
        "............",
        "............",
        ".....kk.....",
        "..kk.kk.kk..",
        "..kbkkkkkbk.",
        "kkkkbbbbbkkk",
        "kbbbbbbbbbbk",
        "kbbbbbbbbbbk",
        ".kkkkkkkkkk.",
        "..llllllll..",
        "............",
        "............",
    ])

    static let battleship = PixelSprite([
        "............",
        ".....kk.....",
        ".....kk.....",
        "..kkkkkkk...",
        ".kkbbbbbkk..",
        "kkbbbbbbbkkk",
        "kbbbbbbbbbbk",
        "kbbbbbbbbbbk",
        "kbbbbbbbbbbk",
        ".kkkkkkkkkk.",
        "..llllllll..",
        "............",
    ])

    static let carrier = PixelSprite([
        "............",
        "............",
        "........kk..",
        "kkkkkkkkkkkk",
        "klllllllkbbk",
        "kkkkkkkkkkkk",
        "kbbbbbbbbbbk",
        ".kbbbbbbbbk.",
        "..kkkkkkkk..",
        "...llllll...",
        "............",
        "............",
    ])

    static let submarine = PixelSprite([
        "............",
        ".....k......",
        "....kkk.....",
        "....kbbk....",
        "....kbbk....",
        ".kkkkbbkkkk.",
        "kbbbbbbbbbbk",
        "kbbbbbbbbbbk",
        ".kkkkkkkkkk.",
        "............",
        "............",
        "............",
    ])

    static let transportShip = PixelSprite([
        "............",
        "......k.....",
        "...kk.k.....",
        "...kkkk.....",
        "..kbbbbk....",
        "kkkkkkkkkkk.",
        "kbbbbbbbbbk.",
        "kbbbbbbbbbk.",
        ".kkkkkkkkk..",
        "..lllllll...",
        "............",
        "............",
    ])
}

// MARK: - Battle markers

extension PixelSprite {

    /// The sprite drawn where a battle happens.
    public static func battle(_ kind: BattleKind) -> PixelSprite {
        switch kind {
        case .battle: return crossedSwords
        case .majorBattle: return explosion
        case .cityCapture: return capturedCity
        case .offensive: return attackArrow
        case .defensive: return shield
        case .siege: return fortress
        case .naval: return anchor
        case .airBattle: return dogfight
        }
    }

    static let crossedSwords = PixelSprite([
        ".k........k.",
        ".lk......kl.",
        "..lk....kl..",
        "...lk..kl...",
        "....lkkl....",
        ".....ll.....",
        "....lkkl....",
        "...kl..lk...",
        "..kl....lk..",
        ".kk......kk.",
        ".k........k.",
        "............",
    ])

    static let explosion = PixelSprite([
        "....k..k....",
        ".k..kaak..k.",
        "..k.kaak.k..",
        "...kaaaak...",
        ".kkaaaaaakk.",
        "..aaallaaa..",
        ".kkaaaaaakk.",
        "...kaaaak...",
        "..k.kaak.k..",
        ".k..kaak..k.",
        "....k..k....",
        "............",
    ])

    static let capturedCity = PixelSprite([
        "....kkkk....",
        "....kaaak...",
        "....kaak....",
        "....k.......",
        "....k.......",
        ".kkkkkkkk...",
        ".klllllk....",
        ".klkllklk...",
        ".kllllllk...",
        ".klkllklk...",
        ".kkkkkkkk...",
        "............",
    ])

    static let attackArrow = PixelSprite([
        "............",
        "............",
        "......kk....",
        "......kak...",
        "kkkkkkkaak..",
        "kaaaaaaaaak.",
        "kaaaaaaaaak.",
        "kkkkkkkaak..",
        "......kak...",
        "......kk....",
        "............",
        "............",
    ])

    static let shield = PixelSprite([
        "............",
        "..kkkkkkkk..",
        "..kllllllk..",
        "..kllbbllk..",
        "..kllbbllk..",
        "..klbbbblk..",
        "...kllllk...",
        "...kllllk...",
        "....kllk....",
        ".....kk.....",
        "............",
        "............",
    ])

    static let fortress = PixelSprite([
        "............",
        "............",
        ".k.k.k.k.k..",
        ".kkkkkkkkk..",
        ".klllllllk..",
        ".klkkkkklk..",
        ".klkllklk...",
        ".klkllklk...",
        ".kkkkkkkkk..",
        "............",
        "............",
        "............",
    ])

    static let anchor = PixelSprite([
        ".....kk.....",
        "....klllk...",
        ".....kk.....",
        "...kkkkkk...",
        ".....ll.....",
        ".....ll.....",
        ".k...ll...k.",
        ".kl..ll..lk.",
        "..kl.ll.lk..",
        "...klllk....",
        "....kkk.....",
        "............",
    ])

    static let dogfight = PixelSprite([
        "............",
        ".....kk..a..",
        "....kllk.aa.",
        "....kllk.a..",
        "kkkkkllkkkkk",
        "kllllllllllk",
        "kkkkkllkkkkk",
        "....kllk....",
        "...kkllkk.a.",
        "...kllllk.a.",
        "....kkkk....",
        "............",
    ])
}
