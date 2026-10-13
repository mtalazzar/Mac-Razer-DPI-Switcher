// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import RazerKit

/// Per-mouse settings, keyed by model family so a mouse's wired and wireless
/// product ids share them. Backed by UserDefaults, which is thread-safe, so
/// the sync worker can read it too.
struct FamilySettings {
    static let defaultPresets = [800, 1600]

    private let defaults = UserDefaults.standard

    private func key(_ model: RazerModel, _ name: String) -> String { "mouse.\(model.family).\(name)" }

    func presets(for model: RazerModel) -> [Int] {
        let stored = defaults.array(forKey: key(model, "presets")) as? [Int] ?? []
        let valid = stored.filter { (try? model.validate(dpi: $0)) != nil }
        return valid.isEmpty ? Self.defaultPresets.filter { $0 <= model.maxDPI } : valid
    }

    func setPresets(_ presets: [Int], for model: RazerModel) {
        defaults.set(presets, forKey: key(model, "presets"))
    }

    /// The DPI applied on this Mac.
    func macDPI(for model: RazerModel) -> Int {
        let stored = defaults.object(forKey: key(model, "macDPI")) as? Int
        if let stored, (try? model.validate(dpi: stored)) != nil { return stored }
        return presets(for: model)[0]
    }

    func setMacDPI(_ dpi: Int, for model: RazerModel) {
        defaults.set(dpi, forKey: key(model, "macDPI"))
    }

    /// The user accepted the model's cautions (untested / wireless / saved-only).
    func isConfirmed(_ model: RazerModel) -> Bool {
        !model.needsConfirmation || defaults.bool(forKey: key(model, "confirmed"))
    }

    func setConfirmed(_ model: RazerModel) {
        defaults.set(true, forKey: key(model, "confirmed"))
    }

    /// For saved-only models: the DPI the mouse had before the first change.
    func originalDPI(for model: RazerModel) -> Int? {
        defaults.object(forKey: key(model, "originalDPI")) as? Int
    }

    func setOriginalDPI(_ dpi: Int, for model: RazerModel) {
        defaults.set(dpi, forKey: key(model, "originalDPI"))
    }
}
