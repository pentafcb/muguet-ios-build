// muguet - Launcher.swift
// Constantin Clerc (c22dev) - 0.1

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine

let configURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("config.json")

final class Settings: ObservableObject {
    @Published var mode = 2
    @Published var scale = 0.5
    @Published var fps = 60
    @Published var textures = 0
    @Published var touch = 1.5
    @Published var aimSensitivity = 0.8
    @Published var padSensitivity = 2.0
    @Published var aimMode = "toggle"
    @Published var fireAim = true
    @Published var mute = false
    @Published var multiplayer = false
    @Published var host = false
    @Published var server = "18.143.103.253"
    @Published var name = "Pentacampeon"
    @Published var roomDigits = String(Int.random(in: 1000...9999))
    @Published var joinCode = ""
    @Published var roomPass = ""
    @Published var roomMode = "create" // "create", "join", "public", "lan"
    @Published var pvp = false
    @Published var promotionSync = false
    // Last promotionSync value seen by any Settings init/save. The
    // render thread reads this instead of building a fresh Settings(),
    // which would re-read config.json from disk and re-apply the saved
    // button layout on every FPS change.
    static var cachedPromotionSync = false
    @Published var deepOptimization = false
    @Published var ultraLow = false
    @Published var sandboxAutoSpawn = true
    @Published var sandboxVehicles: [String] = ["loweyezv"]
    @Published var maxPlayers = 32

    // Granular GTA V Graphics Options
    @Published var shadowQuality = 1 // 1: Normal, 2: High, 3: Very High
    @Published var shadowDistance = 1.0 // 0.5: Short, 1.0: Normal, 1.5: Far
    @Published var reflectionQuality = 1 // 1: Normal, 2: High, 3: Very High
    @Published var grassQuality = 0 // 0: Normal, 1: High, 2: Very High
    @Published var waterQuality = 0 // 0: Normal, 1: High, 2: Very High
    @Published var particleQuality = 0 // 0: Normal, 1: High, 2: Very High
    @Published var postFx = 0 // 0: Normal, 1: High, 2: Very High
    @Published var anisotropicFiltering = 0 // 0: Off, 4: x4, 8: x8, 16: x16
    @Published var fxaa = true // true / false
    @Published var cityDensity = 0.5 // 0.0: Empty, 0.5: Medium, 1.0: Dense
    @Published var pedDensity = 0.5 // 0.0: Low, 0.5: Medium, 1.0: High
    @Published var noTraffic = false // built-in mod: no traffic cars, no peds, no parked cars (single-player)
    @Published var sky = "off" // built-in mod: FiveM PvP sky pack (pink/black/cyan/purple), default off
    @Published var stretch = "off" // built-in option: stretched resolution (4:3 / 5:4), default off
    @Published var distanceScaling = 0.0 // -0.5: Potato, 0.0: Normal, 0.5: Extended

    @Published var buttonScale = 1.0
    @Published var buttonOffsetX = 0.0
    @Published var buttonOffsetY = 0.0
    @Published var buttonOpacity = 0.22
    @Published var stickOffsetX = 0.0
    @Published var stickOffsetY = 0.0
    @Published var customButtons: [Int: [Double]] = [:]
    var extra: [String: Any] = [:]

    func apply120FpsBoost() {
        fps = 120
        scale = 0.5
        textures = 0
        shadowQuality = 1
        shadowDistance = 0.5
        reflectionQuality = 1
        grassQuality = 0
        waterQuality = 0
        particleQuality = 0
        postFx = 0
        anisotropicFiltering = 0
        fxaa = true
        cityDensity = 0.0
        pedDensity = 0.0
        distanceScaling = -0.5
        deepOptimization = true
        ultraLow = false
        promotionSync = true
        do { try save() } catch {}
        muguet_reload_settings()
    }

    func applyLowRamMode() {
        fps = 30
        scale = 0.35
        textures = 0
        shadowQuality = 1
        shadowDistance = 0.5
        reflectionQuality = 1
        grassQuality = 0
        waterQuality = 0
        particleQuality = 0
        postFx = 0
        anisotropicFiltering = 0
        fxaa = false
        cityDensity = 0.0
        pedDensity = 0.0
        distanceScaling = -0.5
        deepOptimization = true
        ultraLow = false
        promotionSync = false
        do { try save() } catch {}
        _ = muguet_apply_low_ram_preset()
        muguet_reload_settings()
    }

    func applyUltraLowMode() {
        fps = 30
        scale = 0.25
        textures = 0
        shadowQuality = 0
        shadowDistance = 0.5
        reflectionQuality = 0
        grassQuality = 0
        waterQuality = 0
        particleQuality = 0
        postFx = 0
        anisotropicFiltering = 0
        fxaa = false
        cityDensity = 0.0
        pedDensity = 0.0
        distanceScaling = -0.5
        deepOptimization = true
        ultraLow = true
        promotionSync = false
        do { try save() } catch {}
        _ = muguet_apply_ultra_low_preset()
        muguet_reload_settings()
    }

    /// Rockstar defaults: wipe the in-game settings.xml, then set the
    /// launcher fields to the safe defaults (Shader High, MSAA Off,
    /// Shadows Normal, 120 FPS) and save + reload. Shared by the home
    /// presets card and the settings drawer.
    func applyRockstarDefaults() {
        resetGraphicsSettings()
        scale = 0.5
        textures = 0
        fps = 120
        shadowQuality = 1
        shadowDistance = 1.0
        reflectionQuality = 1
        grassQuality = 0
        waterQuality = 0
        particleQuality = 0
        postFx = 0
        anisotropicFiltering = 0
        fxaa = true
        cityDensity = 0.5
        pedDensity = 0.5
        distanceScaling = 0.0
        deepOptimization = true
        ultraLow = false
        promotionSync = true
        do { try save() } catch {}
        muguet_reload_settings()
    }

    var formattedCreateCode: String {
        let m = mode == 1 ? "S" : "B"
        let p = pvp ? "X" : "P"
        return "\(m)\(p)-\(roomDigits)"
    }

    init() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        extra = json
        if let v = json["start_mode"] as? Int, (1...2).contains(v) { mode = v }
        if let v = json["scale"] as? Double { scale = v }
        if let v = json["fps_limit"] as? Int, [30, 60, 120].contains(v) { fps = v }
        if let v = json["max_players"] as? Int, [16, 32, 64].contains(v) { maxPlayers = v }
        if let v = json["texture_quality"] as? Int, (0...2).contains(v) { textures = v }
        if let v = json["touch_sensitivity"] as? Double { touch = max(0.1, min(10.0, v)) }
        if let v = json["aim_sensitivity"] as? Double { aimSensitivity = max(0.1, min(5.0, v)) }
        if let v = json["pad_sensitivity"] as? Double { padSensitivity = max(0.1, min(10.0, v)) }
        if let v = json["aim_mode"] as? String, ["toggle", "hold"].contains(v) { aimMode = v }
        if let v = json["fire_aim"] as? Bool { fireAim = v }
        if let v = json["mute"] as? Bool { mute = v }
        if let v = json["multiplayer"] as? Bool { multiplayer = v }
        if let v = json["host"] as? Bool { host = v }
        if let v = json["server"] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { server = v }
        if let v = json["room_digits"] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty {
            roomDigits = v
        } else if let v = json["room"] as? String {
            let digits = v.filter { $0.isNumber }
            if !digits.isEmpty { roomDigits = String(digits.prefix(4)) }
        }
        if let v = json["join_code"] as? String { joinCode = v }
        if let v = json["room_pass"] as? String { roomPass = v }
        if let v = json["room_mode"] as? String, ["create", "join", "public", "lan"].contains(v) { roomMode = v }
        if let v = json["pvp"] as? Bool { pvp = v }
        if let v = json["promotion_sync"] as? Bool { promotionSync = v }
        if let v = json["deep_optimization"] as? Bool { deepOptimization = v }
        if let v = json["ultra_low"] as? Bool { ultraLow = v }
        if let v = json["sandbox_auto_spawn"] as? Bool { sandboxAutoSpawn = v }
        if let arr = json["sandbox_vehicles"] as? [String] {
            let cleaned = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
            if !cleaned.isEmpty { sandboxVehicles = cleaned }
        } else if let v = json["sandbox_vehicle"] as? String {
            let c = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !c.isEmpty { sandboxVehicles = [c] }
        }
        if let v = json["shadow_quality"] as? Int, (0...3).contains(v) { shadowQuality = v }
        if let v = json["shadow_distance"] as? Double { shadowDistance = max(0.5, min(2.0, v)) }
        if let v = json["reflection_quality"] as? Int, (0...3).contains(v) { reflectionQuality = v }
        if let v = json["grass_quality"] as? Int, (0...2).contains(v) { grassQuality = v }
        if let v = json["water_quality"] as? Int, (0...2).contains(v) { waterQuality = v }
        if let v = json["particle_quality"] as? Int, (0...2).contains(v) { particleQuality = v }
        if let v = json["postfx"] as? Int, (0...2).contains(v) { postFx = v }
        if let v = json["anisotropic_filtering"] as? Int, [0, 2, 4, 8, 16].contains(v) { anisotropicFiltering = v }
        if let v = json["fxaa"] as? Bool { fxaa = v }
        if let v = json["city_density"] as? Double { cityDensity = max(0.0, min(1.0, v)) }
        if let v = json["ped_density"] as? Double { pedDensity = max(0.0, min(1.0, v)) }
        if let v = json["no_traffic"] as? Bool { noTraffic = v }
        if let v = json["sky"] as? String, ["off", "pink", "black", "cyan", "purple"].contains(v) { sky = v }
        if let v = json["stretch"] as? String, ["off", "4:3", "5:4"].contains(v) { stretch = v }
        if let v = json["distance_scaling"] as? Double { distanceScaling = max(-0.5, min(1.0, v)) }
        if let v = json["button_scale"] as? Double { buttonScale = max(0.6, min(2.0, v)) }
        if let v = json["button_offset_x"] as? Double { buttonOffsetX = max(-150.0, min(150.0, v)) }
        if let v = json["button_offset_y"] as? Double { buttonOffsetY = max(-150.0, min(150.0, v)) }
        if let v = json["button_opacity"] as? Double { buttonOpacity = max(0.1, min(0.9, v)) }
        if let v = json["stick_offset_x"] as? Double { stickOffsetX = max(-100.0, min(150.0, v)) }
        if let v = json["stick_offset_y"] as? Double { stickOffsetY = max(-100.0, min(150.0, v)) }
        if let v = json["player_name"] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty && v != "iPhone" && v != "iPad" {
            name = v
        }
        if let dict = json["custom_buttons"] as? [String: [Double]] {
            for (k, v) in dict {
                if let idx = Int(k), v.count >= 3 {
                    customButtons[idx] = v
                }
            }
        }
        applyCustomLayout()
        Settings.cachedPromotionSync = promotionSync
    }

    func parseJoinCode(_ code: String) {
        let clean = code.trimmingCharacters(in: .whitespaces).uppercased()
        if clean.hasPrefix("S") {
            mode = 1
        } else if clean.hasPrefix("B") {
            mode = 2
        }
        if clean.contains("X") {
            pvp = true
        } else if clean.contains("P") {
            pvp = false
        }
    }

    func save() throws {
        var json = extra
        let srv = server.trimmingCharacters(in: .whitespaces)
        json["server"] = srv.isEmpty ? "18.143.103.253" : srv
        json["multiplayer"] = multiplayer
        json["host"] = (roomMode == "lan")
        json["room_mode"] = roomMode
        json["promotion_sync"] = promotionSync
        json["deep_optimization"] = deepOptimization
        json["ultra_low"] = ultraLow
        json["sandbox_auto_spawn"] = sandboxAutoSpawn
        json["sandbox_vehicles"] = sandboxVehicles
        json["max_players"] = maxPlayers
        json["room_digits"] = roomDigits
        json["join_code"] = joinCode

        if multiplayer {
            if roomMode == "create" {
                let m = mode == 1 ? "story" : "sandbox"
                let r = pvp ? "pvp" : "peace"
                let rm = "\(m)-\(r)-\(roomDigits)"
                json["room"] = rm
                json["room_pass"] = roomPass.trimmingCharacters(in: .whitespaces)
                json["start_mode"] = mode
                json["pvp"] = pvp
            } else if roomMode == "join" {
                parseJoinCode(joinCode)
                let m = mode == 1 ? "story" : "sandbox"
                let r = pvp ? "pvp" : "peace"
                let digits = joinCode.filter { $0.isNumber }
                let rm = "\(m)-\(r)-\(digits.isEmpty ? "default" : digits)"
                json["room"] = rm
                json["room_pass"] = roomPass.trimmingCharacters(in: .whitespaces)
                json["start_mode"] = mode
                json["pvp"] = pvp
            } else if roomMode == "public" {
                let m = mode == 1 ? "story" : "sandbox"
                json["room"] = "\(m)-public"
                json["room_pass"] = ""
                json["start_mode"] = mode
                json["pvp"] = false
            } else { // lan
                let m = mode == 1 ? "story" : "sandbox"
                json["room"] = "\(m)-lan"
                json["room_pass"] = ""
                json["start_mode"] = mode
                json["pvp"] = pvp
            }
        } else {
            json["start_mode"] = mode
            json["room"] = "default"
            json["room_pass"] = ""
            json["pvp"] = false
        }

        json["scale"] = scale
        json["fps_limit"] = fps
        json["texture_quality"] = textures
        json["shadow_quality"] = shadowQuality
        json["shadow_distance"] = shadowDistance
        json["reflection_quality"] = reflectionQuality
        json["grass_quality"] = grassQuality
        json["water_quality"] = waterQuality
        json["particle_quality"] = particleQuality
        json["postfx"] = postFx
        json["anisotropic_filtering"] = anisotropicFiltering
        json["fxaa"] = fxaa
        json["city_density"] = cityDensity
        json["ped_density"] = pedDensity
        json["no_traffic"] = noTraffic
        json["sky"] = sky
        json["stretch"] = stretch
        json["distance_scaling"] = distanceScaling
        json["touch_sensitivity"] = (touch * 100).rounded() / 100
        json["aim_sensitivity"] = (aimSensitivity * 100).rounded() / 100
        json["pad_sensitivity"] = (padSensitivity * 10).rounded() / 10
        json["aim_mode"] = aimMode
        json["fire_aim"] = fireAim
        json["mute"] = mute
        json["button_scale"] = (buttonScale * 100).rounded() / 100
        json["button_offset_x"] = (buttonOffsetX * 10).rounded() / 10
        json["button_offset_y"] = (buttonOffsetY * 10).rounded() / 10
        json["button_opacity"] = (buttonOpacity * 100).rounded() / 100
        json["stick_offset_x"] = (stickOffsetX * 10).rounded() / 10
        json["stick_offset_y"] = (stickOffsetY * 10).rounded() / 10
        let nm = name.trimmingCharacters(in: .whitespaces)
        json["player_name"] = nm.isEmpty ? "Pentacampeon" : nm
        var cbJson: [String: [Double]] = [:]
        for (idx, v) in customButtons {
            cbJson[String(idx)] = v
        }
        json["custom_buttons"] = cbJson
        if json["extra_args"] == nil { json["extra_args"] = [String]() }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL)
        Settings.cachedPromotionSync = promotionSync
    }

    func resetLayout() {
        buttonScale = 1.0
        buttonOffsetX = 0.0
        buttonOffsetY = 0.0
        buttonOpacity = 0.22
        stickOffsetX = 0.0
        stickOffsetY = 0.0
        customButtons.removeAll()
        muguet_reset_button_layout()
        muguet_apply_button_layout()
    }

    func applyCustomLayout() {
        muguet_reset_button_layout()
        for (idx, v) in customButtons {
            if v.count >= 3 {
                muguet_set_button_layout(UInt32(idx), v[0], v[1], v[2])
            }
        }
        muguet_apply_button_layout()
    }
}

@_silgen_name("muguet_import")
func muguet_import(_ zip: UnsafePointer<CChar>, _ progress: @convention(c) (UInt64, UInt64) -> Void) -> Bool
@_silgen_name("muguet_import_error")
func muguet_import_error() -> UnsafePointer<CChar>?
@_silgen_name("muguet_game_ready")
func muguet_game_ready() -> Bool
@_silgen_name("muguet_has_game_code")
func muguet_has_game_code() -> Bool
@_silgen_name("muguet_reload_settings")
func muguet_reload_settings()
@_silgen_name("muguet_debug_log")
func muguet_debug_log(_ msg: UnsafePointer<CChar>)
@_silgen_name("muguet_apply_cheat")
func muguet_apply_cheat(_ code: UnsafePointer<CChar>)

@_silgen_name("muguet_spawn_vehicle")
func muguet_spawn_vehicle(_ code: UnsafePointer<CChar>)
@_silgen_name("muguet_console_tail")
func muguet_console_tail() -> UnsafePointer<CChar>?
@_silgen_name("muguet_ram_tracker_text")
func muguet_ram_tracker_text() -> UnsafePointer<CChar>?
@_silgen_name("muguet_console_command")
func muguet_console_command(_ code: UnsafePointer<CChar>)
@_silgen_name("muguet_is_multiplayer")
func muguet_is_multiplayer() -> Bool
@_silgen_name("muguet_toggle_first_person")
func muguet_toggle_first_person()
@_silgen_name("muguet_set_button_layout")
func muguet_set_button_layout(_ idx: UInt32, _ dx: Double, _ dy: Double, _ scale: Double)
@_silgen_name("muguet_reset_button_layout")
func muguet_reset_button_layout()
@_silgen_name("muguet_apply_button_layout")
func muguet_apply_button_layout()
@_silgen_name("muguet_reset_game_settings")
func muguet_reset_game_settings() -> Bool
@_silgen_name("muguet_apply_low_ram_preset")
func muguet_apply_low_ram_preset() -> Bool

@_silgen_name("muguet_apply_ultra_low_preset")
func muguet_apply_ultra_low_preset() -> Bool

@_silgen_name("muguet_install_mod")
func muguet_install_mod(_ path: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_remove_mod")
func muguet_remove_mod(_ name: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_mod_error")
func muguet_mod_error() -> UnsafePointer<CChar>?
@_silgen_name("muguet_mod_name")
func muguet_mod_name() -> UnsafePointer<CChar>?
@_silgen_name("muguet_install_vehicles_meta")
func muguet_install_vehicles_meta(_ modName: UnsafePointer<CChar>, _ metaPath: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_vehicles_meta_models")
func muguet_vehicles_meta_models() -> UnsafePointer<CChar>?
@_silgen_name("muguet_install_handling_meta")
func muguet_install_handling_meta(_ modName: UnsafePointer<CChar>, _ metaPath: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_handling_meta_models")
func muguet_handling_meta_models() -> UnsafePointer<CChar>?
@_silgen_name("muguet_install_carvariations_meta")
func muguet_install_carvariations_meta(_ modName: UnsafePointer<CChar>, _ metaPath: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_carvariations_meta_models")
func muguet_carvariations_meta_models() -> UnsafePointer<CChar>?
@_silgen_name("muguet_install_carcols_meta")
func muguet_install_carcols_meta(_ modName: UnsafePointer<CChar>, _ metaPath: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_carcols_meta_models")
func muguet_carcols_meta_models() -> UnsafePointer<CChar>?
@_silgen_name("muguet_install_mod_folder")
func muguet_install_mod_folder(_ folderPath: UnsafePointer<CChar>, _ nameHint: UnsafePointer<CChar>) -> Bool

final class Importer: ObservableObject {
    static let shared = Importer()
    @Published var ready = muguet_game_ready()
    @Published var progress: Double?
    @Published var error: String?
    private var lastProgressTime = 0.0

    func run(_ url: URL) {
        // A second Import tap while one is running used to start a
        // second muguet_import on the same destination. Ignore it.
        guard progress == nil else { return }
        error = nil
        progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // File providers must finish materializing the selected ZIP before
            // Rust seeks to its central directory at the end of the archive.
            var coordinationError: NSError?
            var ok = false
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { localURL in
                ok = localURL.path.withCString { muguet_import($0) { done, total in
                    let now = ProcessInfo.processInfo.systemUptime
                    guard done == total || now - Importer.shared.lastProgressTime >= 0.05 else { return }
                    Importer.shared.lastProgressTime = now
                    let p = total > 0 ? Double(done) / Double(total) : 0
                    DispatchQueue.main.async { Importer.shared.progress = p }
                } }
            }
            let message = ok ? nil : coordinationError?.localizedDescription
                ?? muguet_import_error().map { String(cString: $0) } ?? "unknown error"
            DispatchQueue.main.async {
                self.progress = nil
                self.ready = muguet_game_ready()
                if let message { self.error = "Import failed: \(message)" }
            }
        }
    }
}

struct CheatItem: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let desc: String
    let category: String
}

let CHEAT_LIST: [CheatItem] = [
    CheatItem(code: "PAINKILLER", name: "Invincible for 5 minutes", desc: "Take no damage for 5 minutes", category: "Character"),
    CheatItem(code: "TURTLE", name: "Full Health & Armor", desc: "Restore 100% health and armor, and repair your vehicle", category: "Character"),
    CheatItem(code: "TOOLUP", name: "All Weapons", desc: "Get every weapon with full ammo", category: "Character"),
    CheatItem(code: "LAWYERUP", name: "Clear Wanted Level", desc: "Drop your wanted level to 0", category: "Character"),
    CheatItem(code: "FUGITIVE", name: "Add 1 Wanted Star", desc: "Raise your wanted level by 1", category: "Character"),
    CheatItem(code: "POWERUP", name: "Full Special Ability", desc: "Fully refill your character's special ability bar", category: "Character"),
    CheatItem(code: "CATCHME", name: "Super Fast Run", desc: "Max out your movement speed", category: "Character"),
    CheatItem(code: "GOTGILLS", name: "Super Fast Swim", desc: "Max out your underwater swim speed", category: "Character"),
    CheatItem(code: "HOPTOIT", name: "Super Jump", desc: "Jump 10x higher than normal", category: "Character"),
    CheatItem(code: "SKYDIVE", name: "Parachute Equipped", desc: "Get a parachute to jump from high up", category: "Character"),
    CheatItem(code: "LIQUOR", name: "Drunk Mode", desc: "Stagger around with a drunk effect", category: "Character"),

    CheatItem(code: "BUZZOFF", name: "Buzzard Helicopter", desc: "Attack helicopter with guns & missiles", category: "Vehicles"),
    CheatItem(code: "COMET", name: "Comet Sports Car", desc: "Super-fast 2-door Porsche", category: "Vehicles"),
    CheatItem(code: "RAPIDGT", name: "Rapid GT Race Car", desc: "High-end sports car", category: "Vehicles"),
    CheatItem(code: "ROCKET", name: "PCJ-600 Race Bike", desc: "High-speed big-engine motorcycle", category: "Vehicles"),
    CheatItem(code: "OFFROAD", name: "Sanchez Dirt Bike", desc: "Off-road bike for hills and rough terrain", category: "Vehicles"),
    CheatItem(code: "BANDIT", name: "BMX Bike", desc: "Stunt bike for tricks", category: "Vehicles"),
    CheatItem(code: "BARNSTORM", name: "Stunt Plane", desc: "Propeller stunt plane", category: "Vehicles"),
    CheatItem(code: "VINEWOOD", name: "Limousine", desc: "Long luxury car", category: "Vehicles"),
    CheatItem(code: "TRASHED", name: "Trashmaster Garbage Truck", desc: "Armored garbage truck that rams other cars", category: "Vehicles"),
    CheatItem(code: "DEATHCAR", name: "Duke O'Death Armored Car", desc: "Bulletproof, explosion-proof muscle car", category: "Vehicles"),
    CheatItem(code: "BUBBLES", name: "Kraken Submarine", desc: "Submersible for exploring the ocean floor", category: "Vehicles"),
    CheatItem(code: "FLYSPRAY", name: "Duster Plane", desc: "Classic propeller plane", category: "Vehicles"),

    CheatItem(code: "HOTHANDS", name: "Exploding Punches", desc: "Punch enemies flying and make them explode", category: "Combat"),
    CheatItem(code: "INCENDIARY", name: "Fire Bullets", desc: "Fire bullets that set targets ablaze", category: "Combat"),
    CheatItem(code: "HIGHEX", name: "Exploding Bullets", desc: "Every shot causes a big explosion", category: "Combat"),
    CheatItem(code: "DEADEYE", name: "Slow-Mo Aim", desc: "Slow down time while holding the aim button", category: "Combat"),

    CheatItem(code: "SKYFALL", name: "Freefall From the Sky", desc: "Drop your character from high in the clouds", category: "World"),
    CheatItem(code: "SLOWMO", name: "Slow Down the Game", desc: "Cinematic slow-motion effect", category: "World"),
    CheatItem(code: "FLOATER", name: "Moon Gravity", desc: "Cars and people float around lightly", category: "World"),
    CheatItem(code: "MAKEITRAIN", name: "Change Weather", desc: "Change sun, rain, thunderstorms", category: "World"),
    CheatItem(code: "SNOW", name: "Snowfall", desc: "Turn on snowfall across the whole map", category: "World")
]

struct CheatMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customCode = ""
    @State private var toastMessage: String?
    let onApply: (String) -> Void

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Enter a custom code")) {
                    HStack {
                        TextField("Enter a code (e.g. PAINKILLER)", text: $customCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Apply") {
                            let c = customCode.trimmingCharacters(in: .whitespaces).uppercased()
                            guard !c.isEmpty else { return }
                            apply(c)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                ForEach(["Character", "Vehicles", "Combat", "World"], id: \.self) { cat in
                    Section(header: Text(cat)) {
                        ForEach(CHEAT_LIST.filter { $0.category == cat }) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(item.name).fontWeight(.semibold)
                                        Text("(\(item.code))").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Text(item.desc).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(action: { apply(item.code) }) {
                                    Text("On").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("GTA V Cheat Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    Text(msg)
                        .font(.callout.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func apply(_ code: String) {
        onApply(code)
        withAnimation { toastMessage = "Cheat code sent: \(code)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

// Post FX menu (from the MENU button): ReShade-style visual
// effects, live — no restart. Talks to Rust only through the
// existing muguet_console_command extern (fx ... commands, same as
// the console); reads Documents/muguet-fx-state.json on appear to
// show the current values, and Documents/muguet-fx-presets.json
// for the preset list. Toggles send at once; sliders send once
// when the drag ends, so a drag does not spam the state file.
// After loading a preset the view polls the state file briefly
// (the Rust handler rewrites it when the preset applies) and then
// refreshes the controls from disk.
private struct FxStateFile: Decodable {
    var version: Int = 1
    var state: FxState = FxState()
}

private struct FxState: Codable, Equatable {
    var grade: Bool = false
    var sat: Double = 1.0
    var con: Double = 1.0
    var bri: Double = 0.0
    var sharpen: Bool = false
    var sharp: Double = 0.5
    var fxaa: Bool = false
    var vignette: Bool = false
    var vig: Double = 0.45
    var bloom: Bool = false
    var bloom_strength: Double = 0.6
    var bloom_threshold: Double = 0.8
}

private struct FxPresetsFile: Decodable {
    var version: Int = 1
    var presets: [String: FxState] = [:]
}

struct FxMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = FxState()
    @State private var presets: [String] = []
    @State private var presetName = ""
    @State private var toastMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Color grade")) {
                    Toggle("Color grade", isOn: fxToggle(\.grade, "grade"))
                    if state.grade {
                        fxSlider("Saturation", value: $state.sat, range: 0...2, command: "sat")
                        fxSlider("Contrast", value: $state.con, range: 0...2, command: "con")
                        fxSlider("Brightness", value: $state.bri, range: -0.5...0.5, command: "bri")
                    }
                }
                Section(header: Text("Sharpen")) {
                    Toggle("Sharpen", isOn: fxToggle(\.sharpen, "sharpen"))
                    if state.sharpen {
                        fxSlider("Amount", value: $state.sharp, range: 0...1, command: "sharp")
                    }
                }
                Section(header: Text("Anti-aliasing")) {
                    Toggle("FXAA", isOn: fxToggle(\.fxaa, "fxaa"))
                    Text("Cheap edge smoothing. SMAA is not built — too heavy for the phone on top of the game.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section(header: Text("Vignette")) {
                    Toggle("Vignette", isOn: fxToggle(\.vignette, "vignette"))
                    if state.vignette {
                        fxSlider("Amount", value: $state.vig, range: 0...1, command: "vig")
                    }
                }
                Section(header: Text("Bloom (lite)")) {
                    Toggle("Bloom", isOn: fxToggle(\.bloom, "bloom"))
                    if state.bloom {
                        fxSlider("Strength", value: $state.bloom_strength, range: 0...2, command: "bloom")
                        fxSlider("Threshold", value: $state.bloom_threshold, range: 0...1, command: "thr")
                    }
                    Text("Soft glow from bright areas. Two quarter-res passes — the cheapest effect here after FXAA.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section(header: Text("Presets")) {
                    HStack {
                        TextField("Preset name", text: $presetName)
                            .autocorrectionDisabled()
                        Button("Save") {
                            let name = presetName.trimmingCharacters(in: .whitespaces)
                            guard fxValidPresetName(name) else {
                                toast("Bad name — letters, numbers, spaces, - and _ only (1-48 chars)")
                                return
                            }
                            send("fx save \(name)")
                            presetName = ""
                            loadPresets()
                            toast("Preset saved: \(name)")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if presets.isEmpty {
                        Text("No presets saved yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(presets, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Load") {
                                send("fx load \(name)")
                                refreshAfterLoad()
                                toast("Preset loaded: \(name)")
                            }
                            .buttonStyle(.bordered)
                            Button("Delete") {
                                send("fx delete \(name)")
                                loadPresets()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
                Section {
                    Button("Reset all effects") {
                        send("fx reset")
                        state = FxState()
                        toast("All effects off")
                    }
                    .tint(.red)
                    Text("Applies live, next frame — no restart. Visual only, works in multiplayer. No depth effects (AO, depth of field) in this build.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Post FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    Text(msg)
                        .font(.callout.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadState()
            loadPresets()
        }
    }

    // A Toggle binding that sends the command on tap. Programmatic
    // state changes (loading the state file) do not go through the
    // setter, so opening the menu never spams commands for values
    // that are already on.
    private func fxToggle(_ key: WritableKeyPath<FxState, Bool>, _ command: String) -> Binding<Bool> {
        Binding(
            get: { state[keyPath: key] },
            set: { v in
                state[keyPath: key] = v
                send("fx \(command) \(v ? "on" : "off")")
            }
        )
    }

    // A slider row that sends its value once, when the drag ends.
    private func fxSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, command: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01) { editing in
                if !editing {
                    send("fx \(command) \(String(format: "%.2f", value.wrappedValue))")
                }
            }
        }
    }

    private func send(_ cmd: String) {
        cmd.withCString { muguet_console_command($0) }
    }

    // Same rule as Rust's valid_preset_name: no separators, no dots,
    // 1-48 chars. Checked here so the toast cannot claim a save
    // that Rust then rejects.
    private func fxValidPresetName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 48 else { return false }
        return name.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " || $0 == "-" || $0 == "_" }
    }

    private func toast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { toastMessage = nil }
        }
    }

    private static func documentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func loadState() {
        guard let url = Self.documentsURL()?.appendingPathComponent("muguet-fx-state.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FxStateFile.self, from: data) else { return }
        state = file.state
    }

    private func loadPresets() {
        guard let url = Self.documentsURL()?.appendingPathComponent("muguet-fx-presets.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FxPresetsFile.self, from: data) else {
            presets = []
            return
        }
        presets = file.presets.keys.sorted()
    }

    // The Rust handler rewrites the state file when a preset
    // applies; poll it briefly, then refresh the controls from
    // disk so they show the loaded values.
    private func refreshAfterLoad() {
        let before = state
        var tries = 0
        func tick() {
            tries += 1
            loadState()
            if state != before || tries >= 10 {
                loadPresets()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: tick)
        }
        tick()
    }
}

struct VehicleMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toastMessage: String?
    let codes: [String]
    let onSpawn: (String) -> Void

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Saved vehicles")) {
                    if codes.isEmpty {
                        Text("No vehicles saved. Add codes in Settings > Sandbox Vehicles.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(codes, id: \.self) { code in
                        HStack {
                            Text(code).font(.body.monospaced())
                            Spacer()
                            Button(action: { spawn(code) }) {
                                Text("Spawn").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Spawn a Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    Text(msg)
                        .font(.callout.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func spawn(_ code: String) {
        onSpawn(code)
        withAnimation { toastMessage = "Spawning \(code)…" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

struct HUDButtonDef: Identifiable {
    let id: Int
    let name: String
    let label: String
    let anchorType: AnchorType
    let baseOffset: CGPoint
    let baseRadius: CGFloat
}

enum AnchorType {
    case topLeft
    case topRight
    case bottomRight
    case stick
}

let HUD_BUTTON_DEFS: [HUDButtonDef] = [
    HUDButtonDef(id: 0, name: "FIRE (Shoot / Gas)", label: "FIRE", anchorType: .bottomRight, baseOffset: CGPoint(x: 62, y: 68), baseRadius: 44),
    HUDButtonDef(id: 1, name: "AIM (Aim / Brake)", label: "AIM", anchorType: .bottomRight, baseOffset: CGPoint(x: 158, y: 46), baseRadius: 31),
    HUDButtonDef(id: 2, name: "JUMP (Jump / Handbrake)", label: "JUMP", anchorType: .bottomRight, baseOffset: CGPoint(x: 58, y: 168), baseRadius: 28),
    HUDButtonDef(id: 3, name: "ENTER (Enter/Exit vehicle)", label: "ENTER", anchorType: .bottomRight, baseOffset: CGPoint(x: 140, y: 132), baseRadius: 26),
    HUDButtonDef(id: 4, name: "RELOAD (Reload / Horn)", label: "RELOAD", anchorType: .bottomRight, baseOffset: CGPoint(x: 222, y: 98), baseRadius: 24),
    HUDButtonDef(id: 5, name: "WEAPON (Weapons)", label: "WEAPON", anchorType: .topRight, baseOffset: CGPoint(x: 30, y: 30), baseRadius: 22),
    HUDButtonDef(id: 6, name: "COVER (Take cover / Radio)", label: "COVER", anchorType: .topRight, baseOffset: CGPoint(x: 84, y: 30), baseRadius: 22),
    HUDButtonDef(id: 7, name: "CROUCH (Crouch / Look behind)", label: "CROUCH", anchorType: .topRight, baseOffset: CGPoint(x: 138, y: 30), baseRadius: 22),
    HUDButtonDef(id: 8, name: "CAM (Camera angle)", label: "CAM", anchorType: .topRight, baseOffset: CGPoint(x: 192, y: 30), baseRadius: 22),
    HUDButtonDef(id: 9, name: "MENU (GTA V Menu)", label: "MENU", anchorType: .topRight, baseOffset: CGPoint(x: 246, y: 30), baseRadius: 22),
    HUDButtonDef(id: 10, name: "PAUSE (Pause)", label: "PAUSE", anchorType: .topLeft, baseOffset: CGPoint(x: 30, y: 30), baseRadius: 22),
    HUDButtonDef(id: 11, name: "PHONE (Phone)", label: "PHONE", anchorType: .topLeft, baseOffset: CGPoint(x: 84, y: 30), baseRadius: 22),
    HUDButtonDef(id: 12, name: "MENU KEYS (Arrow keys)", label: "MENU\nKEYS", anchorType: .topLeft, baseOffset: CGPoint(x: 138, y: 30), baseRadius: 22),
    HUDButtonDef(id: 13, name: "SWITCH (Switch character)", label: "SWITCH", anchorType: .topLeft, baseOffset: CGPoint(x: 192, y: 30), baseRadius: 22),
    HUDButtonDef(id: 14, name: "1ST POV (First-person view)", label: "1ST\nPOV", anchorType: .topLeft, baseOffset: CGPoint(x: 246, y: 30), baseRadius: 22),
    HUDButtonDef(id: 15, name: "Extra FIRE (Shoot left)", label: "FIRE", anchorType: .topLeft, baseOffset: CGPoint(x: 45, y: 112), baseRadius: 29),
    HUDButtonDef(id: 16, name: "JOYSTICK (Move stick)", label: "", anchorType: .stick, baseOffset: CGPoint(x: 0, y: 0), baseRadius: 58)
]

struct HUDEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: Settings
    @State private var selectedId: Int = 0
    @State private var offsets: [Int: CGSize] = [:]
    @State private var scales: [Int: Double] = [:]
    @State private var draggingId: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var toastMessage: String?
    @State private var isCollapsed: Bool = false
    @State private var manualDockTop: Bool? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Subtle grid background
                Path { path in
                    let step: CGFloat = 40
                    for x in stride(from: 0, through: geo.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, through: geo.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .ignoresSafeArea()

                // Screen center crosshair
                Path { path in
                    let cx = geo.size.width / 2
                    let cy = geo.size.height / 2
                    path.move(to: CGPoint(x: cx - 20, y: cy))
                    path.addLine(to: CGPoint(x: cx + 20, y: cy))
                    path.move(to: CGPoint(x: cx, y: cy - 20))
                    path.addLine(to: CGPoint(x: cx, y: cy + 20))
                }
                .stroke(Color.white.opacity(0.15), lineWidth: 1)

                // Render Buttons Canvas
                ForEach(HUD_BUTTON_DEFS) { def in
                    renderButton(def, in: geo)
                }

                // Floating Dynamic Toolbar (never obscures selected button)
                VStack(spacing: 6) {
                    if isCollapsed {
                        if shouldDockTop(in: geo) {
                            collapsedBar(geo: geo, isTop: true)
                        } else {
                            collapsedBar(geo: geo, isTop: false)
                        }
                    } else {
                        let isTop = shouldDockTop(in: geo)
                        if isTop {
                            editorToolbar(geo: geo, isTop: true)
                            selectedButtonControls
                        } else {
                            selectedButtonControls
                            editorToolbar(geo: geo, isTop: false)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                // Disable only the transparent background; disabling this parent
                // also disables its toolbar buttons and sliders.
                .background(Color.clear.allowsHitTesting(false))
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: shouldDockTop(in: geo) ? .top : .bottom)
                .animation(.easeInOut(duration: 0.25), value: isCollapsed)
                .animation(.easeInOut(duration: 0.25), value: manualDockTop)
                .animation(.easeInOut(duration: 0.25), value: selectedId)

                // Toast notification
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.callout.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue, lineWidth: 1))
                            .shadow(radius: 6)
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "hudCanvas")
        }
        .onAppear(perform: loadLayout)
    }

    private func shouldDockTop(in geo: GeometryProxy) -> Bool {
        if let manual = manualDockTop { return manual }
        return false
    }

    private func editorToolbar(geo: GeometryProxy, isTop: Bool) -> some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button(action: {
                let current = shouldDockTop(in: geo)
                manualDockTop = !current
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isTop ? "arrow.down.to.line" : "arrow.up.to.line")
                    Text(isTop ? "Move down" : "Move up")
                }
                .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.cyan)

            Spacer()

            Text("HUD EDITOR")
                .font(.subheadline.bold())
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                isCollapsed = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Collapse")
                }
                .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button("Reset all") {
                for i in 0..<17 {
                    offsets[i] = .zero
                    scales[i] = 1.0
                }
                showToast("All buttons reset to default")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button("Save & Apply") {
                saveLayout()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(true)
    }

    private func collapsedBar(geo: GeometryProxy, isTop: Bool) -> some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.secondary)

            Spacer()

            Button(action: { isCollapsed = false }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Show HUD Editor panel")
                }
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Spacer()

            Button("Save & Apply") {
                saveLayout()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6)
        .allowsHitTesting(true)
    }

    private var selectedButtonControls: some View {
        let currentDef = HUD_BUTTON_DEFS.first(where: { $0.id == selectedId }) ?? HUD_BUTTON_DEFS[0]
        let currentScale = scales[selectedId] ?? 1.0

        return HStack(spacing: 14) {
            // Button selector picker
            Menu {
                ForEach(HUD_BUTTON_DEFS) { def in
                    Button(def.name) {
                        selectedId = def.id
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentDef.name)
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider().frame(height: 20)

            // Scale slider & buttons
            HStack(spacing: 6) {
                Text("Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { adjustScale(-0.05) }) {
                    Image(systemName: "minus.circle")
                        .font(.caption.bold())
                }

                Slider(value: Binding(
                    get: { scales[selectedId] ?? 1.0 },
                    set: { scales[selectedId] = (round($0 * 20) / 20) }
                ), in: 0.5...2.2, step: 0.05)
                .frame(width: 110)

                Button(action: { adjustScale(0.05) }) {
                    Image(systemName: "plus.circle")
                        .font(.caption.bold())
                }

                Text(String(format: "%.2f×", currentScale))
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }

            Divider().frame(height: 20)

            // D-Pad nudge arrows
            HStack(spacing: 3) {
                Text("Move:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { nudge(dx: -4, dy: 0) }) {
                    Image(systemName: "arrow.left.square.fill")
                }
                Button(action: { nudge(dx: 0, dy: -4) }) {
                    Image(systemName: "arrow.up.square.fill")
                }
                Button(action: { nudge(dx: 0, dy: 4) }) {
                    Image(systemName: "arrow.down.square.fill")
                }
                Button(action: { nudge(dx: 4, dy: 0) }) {
                    Image(systemName: "arrow.right.square.fill")
                }
            }
            .font(.body)

            Divider().frame(height: 20)

            Button("Reset button") {
                offsets[selectedId] = .zero
                scales[selectedId] = 1.0
                showToast("Reset \(currentDef.name)")
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(true)
    }

    private func renderButton(_ def: HUDButtonDef, in geo: GeometryProxy) -> some View {
        let isSelected = (selectedId == def.id)
        let pos = buttonCenter(for: def, in: geo)
        let bScale = CGFloat(settings.buttonScale)
        let cScale = CGFloat(scales[def.id] ?? 1.0)
        let radius = def.baseRadius * bScale * cScale
        let diameter = radius * 2.0

        return ZStack {
            if def.id == 16 {
                Circle()
                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.35), lineWidth: isSelected ? 3 : 1.5)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .frame(width: diameter, height: diameter)
                Circle()
                    .fill(isSelected ? Color.yellow.opacity(0.7) : Color.white.opacity(0.35))
                    .frame(width: diameter * (26.0 / 58.0), height: diameter * (26.0 / 58.0))
            } else {
                Circle()
                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.4), lineWidth: isSelected ? 3 : 1.5)
                    .background(Circle().fill(isSelected ? Color.white.opacity(0.45) : Color.white.opacity(settings.buttonOpacity)))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: isSelected ? Color.yellow.opacity(0.8) : Color.black.opacity(0.3), radius: isSelected ? 6 : 2)

                Text(def.label)
                    .font(.system(size: max(8, min(16, radius * 0.42)), weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
            }
        }
        // Keep the hit region the size of the button, before positioning it.
        .frame(width: diameter, height: diameter)
        .contentShape(Circle().scale(1.3))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("hudCanvas"))
                .onChanged { value in
                    if selectedId != def.id {
                        selectedId = def.id
                    }
                    draggingId = def.id
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    let base = offsets[def.id] ?? .zero
                    offsets[def.id] = CGSize(
                        width: base.width + value.translation.width,
                        height: base.height + value.translation.height
                    )
                    dragTranslation = .zero
                    draggingId = nil
                }
        )
        .position(x: pos.x, y: pos.y)
    }

    private func buttonCenter(for def: HUDButtonDef, in geo: GeometryProxy) -> CGPoint {
        let sw = geo.size.width
        let sh = geo.size.height

        let bScale = CGFloat(settings.buttonScale)
        let bOx = CGFloat(settings.buttonOffsetX)
        let bOy = CGFloat(settings.buttonOffsetY)

        let saved = offsets[def.id] ?? .zero
        let currentDrag = (draggingId == def.id) ? dragTranslation : .zero
        let cDx = saved.width + currentDrag.width
        let cDy = saved.height + currentDrag.height
        let cScale = CGFloat(scales[def.id] ?? 1.0)

        var x: CGFloat = 0
        var y: CGFloat = 0

        switch def.anchorType {
        case .bottomRight:
            x = sw - def.baseOffset.x * bScale - bOx + cDx
            y = sh - def.baseOffset.y * bScale - bOy + cDy
        case .topRight:
            x = sw - def.baseOffset.x * bScale + cDx
            y = def.baseOffset.y * bScale + cDy
        case .topLeft:
            x = def.baseOffset.x * bScale + cDx
            y = def.baseOffset.y * bScale + cDy
        case .stick:
            let sOx = CGFloat(settings.stickOffsetX)
            let sOy = CGFloat(settings.stickOffsetY)
            let stickRadius = 58.0 * bScale * cScale
            x = 40.0 + stickRadius + sOx + cDx
            y = sh - 30.0 - stickRadius - sOy + cDy
        }

        return CGPoint(x: x, y: y)
    }

    private func loadLayout() {
        for i in 0..<17 {
            if let arr = settings.customButtons[i], arr.count >= 3 {
                offsets[i] = CGSize(width: arr[0], height: arr[1])
                scales[i] = arr[2]
            } else {
                offsets[i] = .zero
                scales[i] = 1.0
            }
        }
    }

    private func saveLayout() {
        for i in 0..<17 {
            let off = offsets[i] ?? .zero
            let sc = scales[i] ?? 1.0
            if abs(off.width) < 0.5 && abs(off.height) < 0.5 && abs(sc - 1.0) < 0.01 {
                settings.customButtons.removeValue(forKey: i)
            } else {
                settings.customButtons[i] = [Double(off.width), Double(off.height), sc]
            }
        }
        do { try settings.save() } catch {}
        settings.applyCustomLayout()
    }

    private func adjustScale(_ delta: Double) {
        let current = scales[selectedId] ?? 1.0
        let next = max(0.5, min(2.2, (round((current + delta) * 20) / 20)))
        scales[selectedId] = next
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        let current = offsets[selectedId] ?? .zero
        offsets[selectedId] = CGSize(width: current.width + dx, height: current.height + dy)
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { toastMessage = nil }
        }
    }
}

// UIKit document picker, replacing SwiftUI .fileImporter. The SwiftUI picker
// swallowed taps on iOS 26: tapping a .zip did nothing and the .failure
// branch was never handled, so the failure was silent. The UIKit delegate
// reports a pick, a cancel, and a missing file separately, and errors are
// surfaced in the launcher instead of disappearing.
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    // The game import takes .zip only; the Mods section passes
    // [.zip, .rpf] so a bare dlc.rpf is tappable too.
    var contentTypes: [UTType] = [UTType.zip]
    // Folders cannot be copied: a folder pick opens the original
    // in place (asCopy: false) and the caller holds security-scoped
    // access while Rust reads it.
    var copy: Bool = true
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: copy)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick, onError: onError)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding var isPresented: Bool
        var onPick: (URL) -> Void
        var onError: (String) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void, onError: @escaping (String) -> Void) {
            self._isPresented = isPresented
            self.onPick = onPick
            self.onError = onError
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            isPresented = false
            if let url = urls.first {
                onPick(url)
            } else {
                onError("Picker returned no file.")
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
            isPresented = false
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
            "picker cancelled".withCString { muguet_debug_log($0) }
        }
    }
}

// CloudLauncher-style shared pieces (CL prefix). The Muguet target has no
// Color(hex:) helper, so the standard 6-digit hex init lives here too.
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255.0,
                  green: Double((value >> 8) & 0xFF) / 255.0,
                  blue: Double(value & 0xFF) / 255.0)
    }
}

// Small shared panel header (title + close X), mirroring CloudLauncher.
struct CLPanelHeader: View {
    let title: String
    var onClose: () -> Void
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

// Uppercase section label wrapper, mirroring CloudLauncher's panel sections.
// Uses kerning instead of tracking so it still compiles on the iOS 15 target.
struct CLSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).kerning(1.2)
                .foregroundColor(.white.opacity(0.55))
            content
        }
    }
}

// Console-style toggle switch, mirroring CloudLauncher's SettingsToggle.
struct CLToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            HStack {
                // 12.5pt and wrapping: at the default 17pt the title
                // was cut off at the column edge — "Auto-spawn vehicle
                // in Sand…" — in the narrow drawer columns.
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? muguetPink : Color.white.opacity(0.18))
                        .frame(width: 50, height: 30)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .padding(.horizontal, 3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Capsule option chips, mirroring CloudLauncher's chip rows. Selected chip
// is white with dark text, unselected is white 0.1 fill. Chips wrap into
// rows: the old horizontal ScrollView made the column as wide as the whole
// chip row, so the 3-column drawer overflowed the panel and options were
// cut off at the column edge — Sandbox F…, Standard… — with no
// visible way to reach them.
struct CLChipPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(String, Value)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(chipRows(), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { i in
                            let option = options[i]
                            Button { selection = option.1 } label: {
                                Text(option.0)
                                    .font(.system(size: 12, weight: selection == option.1 ? .bold : .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Capsule().fill(selection == option.1 ? muguetPink : Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // Greedy wrap on an estimated character width (chips are 12pt).
    // Budget ~160pt: the drawer panel caps at 600pt, three columns,
    // minus column + group padding. Widths are overestimated on
    // purpose so a row breaks early instead of overflowing.
    private func chipRows() -> [[Int]] {
        var rows: [[Int]] = [[]]
        var width = 0
        for i in options.indices {
            let w = options[i].0.count * 7 + 22
            if width + w > 160 && !rows[rows.count - 1].isEmpty {
                rows.append([])
                width = 0
            }
            rows[rows.count - 1].append(i)
            width += w + 8
        }
        return rows
    }
}

// Dark text field, mirroring CloudLauncher's DarkField.
struct CLDarkField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var autocapitalization: TextInputAutocapitalization = .never
    var keyboardType: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6))
            TextField(placeholder, text: $text)
                .foregroundColor(.white)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
        }
    }
}

// Dark navigation row, mirroring CloudLauncher's tile rows: white 0.05 fill,
// 10pt radius, chevron.right at 0.4 opacity.
struct CLRow: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = Color.white.opacity(0.55)
    var showChevron: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                Spacer()
                if let value {
                    Text(value).font(.system(size: 14)).foregroundColor(valueColor)
                }
                if showChevron {
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

// White capsule button with dark text, mirroring CloudLauncher's Play button.
struct CLCapsuleButton: View {
    let title: String
    var icon: String? = nil
    var fill: Color = .white
    var textColor: Color = Color(hex: "0B0D12")
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(fill))
            .foregroundColor(textColor)
        }
        .buttonStyle(.plain)
    }
}

// The three graphics presets, shared by the home chips row and the settings
// panel so the actions and alert messages can never drift apart.
// The three graphics presets, shared by the home card and the settings
// drawer so the actions and alert messages can never drift apart.
// Web style: dark segmented buttons, the active preset pink.
struct CLPresetButtons: View {
    @ObservedObject var s: Settings
    @Binding var resetAlertMessage: String
    @Binding var showingResetAlert: Bool

    var body: some View {
        HStack(spacing: 4) {
            presetButton(title: "Ultra Low", active: currentPresetName(s) == "ULTRA LOW") {
                s.applyUltraLowMode()
                resetAlertMessage = "Ultra Low setup enabled — shadows & reflections off, 25% resolution!"
                showingResetAlert = true
            }
            presetButton(title: "Save RAM", active: currentPresetName(s) == "SAVE RAM") {
                s.applyLowRamMode()
                resetAlertMessage = "Super RAM Saver setup enabled (~800MB)!"
                showingResetAlert = true
            }
            presetButton(title: "120 FPS", active: currentPresetName(s) == "120 FPS") {
                s.apply120FpsBoost()
                resetAlertMessage = "120 FPS Super Smooth setup enabled!"
                showingResetAlert = true
            }
        }
    }

    private func presetButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background((active ? muguetPink : Color(hex: "1b1d22")))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? muguetPink : Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// Slide-in settings panel, mirroring CloudLauncher's panelOverlay: dim
// backdrop 0.55 tap-to-close, panel min(92% screen width, 600) — 92% (not
// CloudLauncher's 60%) because this launcher runs on iPhone landscape,
// #11131B at 0.97 opacity, rounded 18, shadow. Every control from the old
// Form lives here with the same bindings, actions and alert messages.
// The 11 packs that ship with the game, lowercased. They are never
// listed as mods and never offered for removal, here or in Rust.
private let stockPacks: Set<String> = ["mpbeach", "mpbusiness", "mpbusiness2", "mpchristmas", "mphipster", "mpindependence", "mplts", "mppilot", "mpvalentines", "spupgrade", "verityradio"]


// ---- Muguet web-launcher look: palette, live facts, shared cards ----
// Colors taken from fivem-home-screen.html (:root). Pink/red is the accent.
private let muguetPink = Color(hex: "f40552")
private let muguetPink2 = Color(hex: "ff2e63")
private let muguetPanel = Color(hex: "101216")
private let muguetPanel2 = Color(hex: "14161b")
private let muguetPanel3 = Color(hex: "1b1e24")
private let muguetInset = Color(hex: "1d2026")
private let muguetMuted = Color(hex: "a9afb8")
private let muguetMuted2 = Color(hex: "7f868f")
private let muguetGreen = Color(hex: "3ddc58")
private let muguetAmber = Color(hex: "ffb020")
private let muguetRed = Color(hex: "ff4d4d")
private let muguetGold = Color(hex: "f5c518")

/// App version/build read from Info.plist at runtime — never hardcoded.
private var appVersionShort: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
}
private var appBuildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
}
/// "v0.1 · Build 8" style.
private var appVersionLabel: String { "v\(appVersionShort) · Build \(appBuildNumber)" }
/// "0.1 (B8)" style used by the web design.
private var appVersionCompact: String { "\(appVersionShort) (B\(appBuildNumber))" }
/// Upstream Build 8.9 is a static repo fact: the latest official Muguet release.
private let upstreamBuild = "8.9"

/// The 11 stock packs, in the web design's order (same set as stockPacks / Rust STOCK_PACKS).
/// Derived from stockPacks so the two lists can never drift apart.
private let stockPackList: [String] = stockPacks.sorted()

/// Full console command list from the web design (see help in the console).
private let consoleCommands: [String] = ["car <code>", "spawn <code>", "heal", "kill", "fix", "dv", "tpm", "tp <x> <y> <z>", "coords", "weather", "cheat <CODE>", "fp", "ram", "dlc", "rpf <mod>", "spawninfo <code>", "reload", "lowram", "ultralow", "quit", "clear", "close"]

/// Current preset name from live settings, for the drawer chip and home card.
/// Rockstar defaults share fps 120 / scale 0.5 with 120 FPS, so test
/// its full signature first — otherwise the 120 FPS button lights up
/// pink after applying Rockstar defaults and the Rockstar row can
/// never show ACTIVE.
private func currentPresetName(_ s: Settings) -> String {
    if s.ultraLow { return "ULTRA LOW" }
    if s.fps == 120 && s.shadowDistance == 1.0 && s.cityDensity == 0.5 && s.distanceScaling == 0.0 { return "ROCKSTAR" }
    if s.fps == 120 { return "120 FPS" }
    if s.fps == 30 && s.scale == 0.35 { return "SAVE RAM" }
    return "CUSTOM"
}

private func dlcPacksDir() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let game = docs.appendingPathComponent("game")
    let normal = game.appendingPathComponent("data/x64/dlcPacks")
    if FileManager.default.fileExists(atPath: normal.path) { return normal }
    return game.appendingPathComponent("gamedat/data/x64/dlcPacks")
}

/// Installed add-on mod folder names, read from disk (stock packs excluded).
private func installedModNames() -> [String] {
    let dir = dlcPacksDir()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return names.sorted().filter { name in
        var isDir: ObjCBool = false
        let full = dir.appendingPathComponent(name)
        return !stockPacks.contains(name.lowercased())
            && FileManager.default.fileExists(atPath: full.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// Size of a mod's dlc.rpf on disk, or "" when it cannot be read.
private func installedModSize(_ name: String) -> String {
    let rpf = dlcPacksDir().appendingPathComponent(name).appendingPathComponent("dlc.rpf")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: rpf.path),
       let size = attrs[.size] as? NSNumber {
        return ByteCountFormatter.string(fromByteCount: Int64(size.intValue), countStyle: .file)
    }
    return ""
}

/// Live RAM tracker line, read straight from the tracker slot
/// ("—" when the game has not started yet). The tracker never logs
/// to the console, so grepping the tail for "[RAM]" always came up
/// empty and the home RAM card permanently showed "—".
private func ramTrackerText() -> String? {
    guard let ptr = muguet_ram_tracker_text() else { return nil }
    let text = String(cString: ptr)
    return text.isEmpty ? nil : text
}

// Dark web-style card: #101216 panel, 1px white-10% border, 4pt radius.
private func webCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) { content() }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(muguetPanel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10), lineWidth: 1))
}

private func webCardTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 11.5, weight: .black))
        .kerning(0.7)
        .foregroundColor(.white)
        .padding(.bottom, 4)
}

private func webKV(_ k: String, _ v: String, mono: Bool = false) -> some View {
    HStack(alignment: .top, spacing: 6) {
        Text(k)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(muguetMuted)
            .frame(width: 86, alignment: .leading)
        Text(v)
            .font(.system(size: 10, design: mono ? .monospaced : .default))
            .foregroundColor(Color(hex: "dde0e3"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2)
}

private func webNote(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10))
        .lineSpacing(1.5)
        .foregroundColor(Color(hex: "c9ccd0"))
        .fixedSize(horizontal: false, vertical: true)
}

private func webChip(_ text: String, gold: Bool = false) -> some View {
    Text(text)
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(gold ? muguetGold : Color(hex: "cfd3d8"))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(muguetInset)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(gold ? muguetGold.opacity(0.25) : Color.white.opacity(0.10), lineWidth: 1))
}

/// One feed post, as in THE PROJECT / IN THIS BUILD.
/// avatarURL loads the person's real GitHub avatar (AsyncImage); when
/// it is nil or the image fails to load, the letter tile shows instead.
private func feedPost(avatar: String, name: String, time: String, body: String, avatarURL: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 7) {
            if let urlString = avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        avatarLetter(avatar)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                avatarLetter(avatar)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    Text(time).font(.system(size: 10)).foregroundColor(muguetMuted2)
                }
                Text(body)
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundColor(Color(hex: "dde0e3"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 5)
        Divider().background(Color.white.opacity(0.06))
    }
}

/// The letter tile feedPost falls back to when no avatar image loads.
private func avatarLetter(_ letter: String) -> some View {
    Text(letter)
        .font(.system(size: 12, weight: .black))
        .foregroundColor(.white)
        .frame(width: 26, height: 26)
        .background(Color(hex: "2b2e35"))
        .clipShape(RoundedRectangle(cornerRadius: 3))
}

/// Live RAM tracker line from the tracker slot ("—" when the game has not started yet).
struct RamLiveLineView: View {
    @State private var line: String?
    @State private var tick = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    var body: some View {
        Text(line ?? "—")
            .font(.system(size: 10))
            .foregroundColor(muguetMuted)
            .onReceive(tick) { _ in line = ramTrackerText() }
            .onAppear { line = ramTrackerText() }
    }
}

/// Console preview for the settings drawer: last lines of the live tail,
/// auto-scroll toggle, and a command input that sends to muguet_console_command.
struct ConsolePreviewView: View {
    @State private var logText = ""
    @State private var input = ""
    @State private var autoScroll = true
    @State private var tick = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        // ScrollViewReader so Auto-scroll can follow the tail to the
        // bottom like the real console does. Without it the toggle
        // promised following but the offset never moved and new lines
        // arrived below the fold, out of view.
        ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Console").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button(autoScroll ? "Auto-scroll: On" : "Auto-scroll: Off") {
                    autoScroll.toggle()
                    if autoScroll { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                    .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    .buttonStyle(.plain)
            }
            ScrollView {
                Text(logText.isEmpty ? "Console ready — type help for commands." : logText)
                    .font(.system(size: 9.5, design: .monospaced))
                    .lineSpacing(2)
                    .foregroundColor(Color(hex: "9fe8a9"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("bottom")
            }
            .frame(height: 84)
            .padding(6)
            .background(Color(hex: "0a0b0d"))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.10), lineWidth: 1))
            HStack(spacing: 6) {
                TextField("Command — car, dv, tpm, ram, weather, quit…", text: $input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { submit(proxy: proxy) }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "0a0b0d")))
                Button("RUN") { submit(proxy: proxy) }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "1b1d22")))
                    .buttonStyle(.plain)
            }
        }
        .onReceive(tick) { _ in poll(proxy: proxy) }
        .onAppear { poll(proxy: proxy) }
        }
    }

    private func poll(proxy: ScrollViewProxy) {
        if !autoScroll { return }
        guard let ptr = muguet_console_tail() else { return }
        let text = String(cString: ptr)
        let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(30).joined(separator: "\n")
        if tail != logText {
            logText = tail
            // Next runloop turn, after the text has re-laid out, so
            // the scroll lands on the new bottom instead of the old one.
            DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func submit(proxy: ScrollViewProxy) {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        input = ""
        cmd.withCString { muguet_console_command($0) }
        if !autoScroll { autoScroll = true }
        poll(proxy: proxy)
    }
}

private struct ModEntry: Identifiable {
    let name: String
    let size: String
    var id: String { name }
}

// Name prompt for a bare dlc.rpf install. The picker copy is named
// dlc.rpf, so the folder name cannot be derived from the file — the
// user types it (e.g. loweyezv). Zip installs skip this: Rust takes
// the name from the zip structure. The model name is a second field:
// the spawn code inside the .rpf cannot be read out of the file and
// may differ from the folder name, so the user types it too.
struct ModNameSheet: View {
    @Binding var name: String
    @Binding var modelName: String
    @Binding var metaURL: URL?
    @Binding var metaFileName: String
    @Binding var handlingURL: URL?
    @Binding var handlingFileName: String
    @Binding var carvariationsURL: URL?
    @Binding var carvariationsFileName: String
    @Binding var carcolsURL: URL?
    @Binding var carcolsFileName: String
    var onCancel: () -> Void
    var onInstall: () -> Void

    @State private var pickingMeta = false
    @State private var pickingMetaKind = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mod name").font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
            Text("Folder is the folder name under dlcPacks and the line in dlcList.xml. Model is the spawn code (what CAR and auto-spawn use) — the .rpf file cannot be read, so type it if it differs from the folder, or leave it blank to use the folder name. Use lowercase letters, digits and underscores — e.g. loweyezv.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            TextField("Mod folder (e.g. loweyezv)", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
            TextField("Model name — spawn code (optional)", text: $modelName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("vehicles.meta").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    if !metaFileName.isEmpty {
                        Text(metaFileName).font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    }
                    Button(metaFileName.isEmpty ? "Choose…" : "Change…") { pickingMetaKind = "vehicles"; pickingMeta = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "0B0D12"))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                        .buttonStyle(.plain)
                }
                Text("Optional. Some packs ship a vehicles.meta inside the .rpf that the game cannot read — if the model will not spawn, pick the mod's vehicles.meta here and the launcher merges its models into the game's vehicles.meta.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("handling.meta").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    if !handlingFileName.isEmpty {
                        Text(handlingFileName).font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    }
                    Button(handlingFileName.isEmpty ? "Choose…" : "Change…") { pickingMetaKind = "handling"; pickingMeta = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "0B0D12"))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                        .buttonStyle(.plain)
                }
                Text("Optional. Without the mod's handling the game traps while loading once the model is registered — pick the mod's handling.meta here and the launcher merges it into the game's handling.meta.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("carvariations.meta").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    if !carvariationsFileName.isEmpty {
                        Text(carvariationsFileName).font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    }
                    Button(carvariationsFileName.isEmpty ? "Choose…" : "Change…") { pickingMetaKind = "carvariations"; pickingMeta = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "0B0D12"))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                        .buttonStyle(.plain)
                }
                Text("Optional. Pick the mod's carvariations.meta here and the launcher merges its colors into the game's carvariations.meta — otherwise the car spawns with default colors.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("carcols.meta").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    if !carcolsFileName.isEmpty {
                        Text(carcolsFileName).font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    }
                    Button(carcolsFileName.isEmpty ? "Choose…" : "Change…") { pickingMetaKind = "carcols"; pickingMeta = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "0B0D12"))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                        .buttonStyle(.plain)
                }
                Text("Optional. Pick the mod's carcols.meta here and the launcher merges its tuning kit and lights into the game's carcols.meta — otherwise the car has no mod kit at LS Customs and stock lights.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .buttonStyle(.plain)
                Spacer()
                Button("Install", action: onInstall)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "0B0D12"))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .background(Color(hex: "11131B"))
        .preferredColorScheme(.dark)
        // The meta picker is this sheet's own sheet: it is opened
        // from a button tap, never in the same turn as a dismissal.
        .sheet(isPresented: $pickingMeta) {
            DocumentPicker(isPresented: $pickingMeta, contentTypes: [UTType(tag: "meta", tagClass: .filenameExtension, conformingTo: .data) ?? UTType.data], onPick: { url in
                switch pickingMetaKind {
                case "handling":
                    handlingURL = url
                    handlingFileName = url.lastPathComponent
                case "carvariations":
                    carvariationsURL = url
                    carvariationsFileName = url.lastPathComponent
                case "carcols":
                    carcolsURL = url
                    carcolsFileName = url.lastPathComponent
                default:
                    metaURL = url
                    metaFileName = url.lastPathComponent
                }
            }, onError: { _ in })
        }
    }
}

// Settings drawer, rebuilt to the web design: a full-screen landscape
// panel with a pinned header (SETTINGS, version, current-preset chip,
// close X) and a three-column body that scrolls internally. Every control
// from the old side panel lives here with the same bindings, actions and
// alert messages; only the layout changed.
struct CLSettingsPanel: View {
    @ObservedObject var s: Settings
    @Binding var showingCheatSheet: Bool
    @Binding var showingHUDEditor: Bool
    @Binding var showingResetAlert: Bool
    @Binding var resetAlertMessage: String
    @Binding var newVehicleCode: String
    @Binding var jumpSection: String?
    var onClose: () -> Void
    var onLaunch: () -> Void = {}

    // Mods manager state. The installed list is read from disk, never
    // stored: the folders under dlcPacks are the truth.
    @State private var installedMods: [ModEntry] = []
    @State private var pickingMod = false
    @State private var modNameSheetURL: URL?
    @State private var modNameText = ""
    @State private var modModelText = ""
    @State private var modMetaURL: URL?
    @State private var modMetaFileName = ""
    @State private var modHandlingURL: URL?
    @State private var modHandlingFileName = ""
    @State private var modCarvariationsURL: URL?
    @State private var modCarvariationsFileName = ""
    @State private var modCarcolsURL: URL?
    @State private var modCarcolsFileName = ""
    @State private var pickingFolder = false
    @State private var pickingMetaFor: String?
    @State private var pickingMeta = false
    @State private var modToDelete: String?
    @State private var modsStatus = ""
    @State private var modsWorking = false
    @State private var verifyStatus = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                // Pinned header.
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SETTINGS")
                            .font(.system(size: 15, weight: .black))
                            .kerning(0.7)
                            .foregroundColor(.white)
                        Text("\(appVersionLabel) · iOS 15+")
                            .font(.system(size: 10.5))
                            .foregroundColor(muguetMuted)
                    }
                    Text(currentPresetName(s))
                        .font(.system(size: 10, weight: .black))
                        .kerning(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(muguetPink)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(muguetPanel2)
                Divider().background(Color.white.opacity(0.10))
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            settingsColumn1
                            Divider().background(Color.white.opacity(0.10))
                            settingsColumn2
                            Divider().background(Color.white.opacity(0.10))
                            settingsColumn3
                        }
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        // Next runloop turn: scrollTo in onAppear commonly
                        // runs before the ScrollView content is laid out,
                        // so the first open from a home shortcut jumped
                        // nowhere.
                        DispatchQueue.main.async {
                            if let j = jumpSection { proxy.scrollTo(j, anchor: .top) }
                        }
                    }
                    .onChange(of: jumpSection) { _ in
                        if let j = jumpSection {
                            withAnimation { proxy.scrollTo(j, anchor: .top) }
                        }
                    }
                }
            }
            .background(muguetPanel2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.75), radius: 30)
            .padding(7)
        }
        .environment(\.colorScheme, .dark)
        // No follow-up sheet after the picker: presenting the name
        // prompt as a sheet blacked the screen on three tries
        // (same-turn present, onDismiss, next-runloop present — the
        // picker dismissal was still settling every time). The prompt
        // is an inline card in the Mods section instead, so there is
        // no second presentation to go wrong.
        .sheet(isPresented: $pickingMod) {
            DocumentPicker(isPresented: $pickingMod, contentTypes: [UTType.zip, UTType(tag: "rpf", tagClass: .filenameExtension, conformingTo: .data) ?? UTType.data], onPick: { url in
                installModFile(url)
            }, onError: { message in
                modsStatus = "Could not pick a file: \(message)"
                message.withCString { muguet_debug_log($0) }
            })
        }
        // Whole-folder install (FiveM resource layout): the folder
        // name is the mod name, so there is no name prompt. The
        // folder opens in place, not as a copy — Rust reads it
        // directly while the pick holds security-scoped access.
        .sheet(isPresented: $pickingFolder) {
            DocumentPicker(isPresented: $pickingFolder, contentTypes: [UTType.folder], copy: false, onPick: { url in
                runFolderInstall(url: url)
            }, onError: { message in
                modsStatus = "Could not pick a folder: \(message)"
                message.withCString { muguet_debug_log($0) }
            })
        }
        // Meta picker for a mod that is already installed (META
        // button on its row): no follow-up sheet, the pick installs
        // the .meta straight away.
        .sheet(isPresented: $pickingMeta) {
            DocumentPicker(isPresented: $pickingMeta, contentTypes: [UTType(tag: "meta", tagClass: .filenameExtension, conformingTo: .data) ?? UTType.data], onPick: { url in
                if let mod = pickingMetaFor {
                    runMetaInstall(mod: mod, url: url)
                }
                pickingMetaFor = nil
            }, onError: { message in
                modsStatus = "Could not pick a file: \(message)"
                pickingMetaFor = nil
            })
        }
        .alert("Remove mod?", isPresented: Binding(get: { modToDelete != nil }, set: { if !$0 { modToDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let name = modToDelete { removeMod(name) }
                modToDelete = nil
            }
            Button("Cancel", role: .cancel) { modToDelete = nil }
        } message: {
            if let name = modToDelete {
                Text("This deletes the \(name) folder and its line in dlcList.xml, and removes its vehicles.meta, handling.meta, carvariations.meta and carcols.meta entries from the game's files. Other mods are not touched.")
            }
        }
    }

    // MARK: - Column 1: Character + Graphics + Save Data

    private var settingsColumn1: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Text("◆ CHARACTER")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    CLDarkField(label: "Character name", text: $s.name, placeholder: "Enter a character name...", autocapitalization: .words)
                    Text("This name will show above your character's head when you play with friends.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .id("character")

            if !s.multiplayer {
                VStack(alignment: .leading, spacing: 5) {
                    Text("◆ MODE")
                        .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                    webGroup {
                        CLChipPicker(label: "Mode", selection: $s.mode, options: [
                            ("Story Mode", 1),
                            ("Sandbox (Free Roam)", 2)
                        ])
                    }
                }
                .id("mode")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("◆ GRAPHICS")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    Text("PRESET")
                        .font(.system(size: 10, weight: .black)).kerning(0.7).foregroundColor(muguetMuted)
                    CLPresetButtons(s: s, resetAlertMessage: $resetAlertMessage, showingResetAlert: $showingResetAlert)
                    Text(presetDescription)
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                }
                webGroup {
                    CLChipPicker(label: "Frame rate (Frame Limit)", selection: $s.fps, options: [
                        ("30 fps", 30),
                        ("60 fps", 60),
                        ("120 fps", 120)
                    ])
                    CLChipPicker(label: "Resolution", selection: $s.scale, options: [
                        ("25%", 0.25),
                        ("35%", 0.35),
                        ("50%", 0.5),
                        ("65%", 0.65),
                        ("75%", 0.75),
                        ("100%", 1.0)
                    ])
                    CLChipPicker(label: "Stretched Resolution", selection: $s.stretch, options: [
                        ("Off", "off"),
                        ("4:3 Stretched", "4:3"),
                        ("5:4 Stretched", "5:4")
                    ])
                    Text("Built-in option: the FiveM PvP stretched look — the game renders narrow (4:3 or 5:4) at the same height and the display stretches it to fill the wide screen, so things look larger and wider and fewer pixels means more FPS. The game's own HUD stretches too, like on PC; the touch buttons stay put. Applies on Play (the render size is fixed when the game starts); also check it in the console with stretch.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Texture Quality").foregroundColor(.white)
                        Spacer()
                        Text("\(s.textures)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    }
                    .font(.system(size: 11.5))
                    CLChipPicker(label: "", selection: $s.textures, options: [
                        ("Normal / Low", 0),
                        ("High", 1),
                        ("Very High", 2)
                    ])
                    CLToggle(title: "Lock ProMotion V-Sync 120Hz pacing", isOn: $s.promotionSync)
                    Text("Syncs precisely with your iPhone screen's 60Hz/120Hz refresh rate to remove stutter and keep 120 FPS as smooth as possible.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    CLToggle(title: "Deep graphics optimization", isOn: $s.deepOptimization)
                    Text("Automatically limits shadows, dense grass, and anti-aliasing in GTA V settings.xml to hold max FPS when the device heats up.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    Button(action: {
                        s.applyRockstarDefaults()
                        resetAlertMessage = "Restored Rockstar GTA V graphics to safe defaults (Shader High, MSAA Off, Shadows Normal, 120 FPS). The black screen caused by Max Settings is fully fixed!"
                        showingResetAlert = true
                    }) {
                        Label("Rockstar defaults", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .id("graphics")

            VStack(alignment: .leading, spacing: 5) {
                Text("◆ SAVE DATA")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    Text("Phone > Quick Save · Files > saves")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Share / Backup saves") { shareSaves() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .buttonStyle(.plain)
                    Button("Verify game files") {
                        verifyStatus = muguet_game_ready()
                            ? "Game files OK — manifest.json · game.wasm present."
                            : "Game files missing — import game data to play."
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .buttonStyle(.plain)
                    if !verifyStatus.isEmpty {
                        Text(verifyStatus).font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .id("savedata")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
    }

    private var presetDescription: String {
        switch currentPresetName(s) {
        case "ULTRA LOW":
            return "Ultra Low — 25% resolution · Texture 0 · Shadow 0 · Reflection 0 · FXAA off · Water 0 · Particle 0 · Grass 0 · PostFX 0 · CityDensity 0 · PedVariety 0 · LOD −0.5."
        case "SAVE RAM":
            return "Save RAM — 800 MB–1 GB · 30 FPS · 35%."
        case "ROCKSTAR":
            return "Rockstar defaults — 120 FPS · 50% · Shadows Normal · Shader High."
        case "120 FPS":
            return "120 FPS — 120 · 50% · V-Sync · Deep Opt."
        default:
            return "Custom — \(s.fps) FPS · \(Int(s.scale * 100))% resolution."
        }
    }

    // MARK: - Column 2: Detailed Graphics + Controls

    private var settingsColumn2: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Text("◆ DETAILED GRAPHICS")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    Text("Set GTA V graphics options right here without changing them in-game.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    CLChipPicker(label: "Shadow Quality", selection: $s.shadowQuality, options: [
                        ("Off", 0),
                        ("Normal", 1),
                        ("High", 2),
                        ("Very High", 3)
                    ])
                    CLChipPicker(label: "Shadow Distance", selection: $s.shadowDistance, options: [
                        ("Short (0.5×)", 0.5),
                        ("Standard (1.0×)", 1.0),
                        ("Far (1.5×)", 1.5)
                    ])
                    CLChipPicker(label: "Reflection Quality", selection: $s.reflectionQuality, options: [
                        ("Off", 0),
                        ("Normal", 1),
                        ("High", 2),
                        ("Very High", 3)
                    ])
                    CLChipPicker(label: "Grass & Vegetation", selection: $s.grassQuality, options: [
                        ("Normal", 0),
                        ("High", 1),
                        ("Very High", 2)
                    ])
                    CLChipPicker(label: "Water Quality", selection: $s.waterQuality, options: [
                        ("Normal", 0),
                        ("High", 1),
                        ("Very High", 2)
                    ])
                    CLChipPicker(label: "Particle & Explosion Effects", selection: $s.particleQuality, options: [
                        ("Normal", 0),
                        ("High", 1),
                        ("Very High", 2)
                    ])
                    CLChipPicker(label: "Post FX & Lighting", selection: $s.postFx, options: [
                        ("Normal", 0),
                        ("High", 1),
                        ("Very High", 2)
                    ])
                    CLChipPicker(label: "Anisotropic Filtering", selection: $s.anisotropicFiltering, options: [
                        ("Off (x0)", 0),
                        ("x4", 4),
                        ("x8", 8),
                        ("x16", 16)
                    ])
                    CLToggle(title: "Edge anti-aliasing (FXAA)", isOn: $s.fxaa)
                    CLChipPicker(label: "Traffic Density", selection: $s.cityDensity, options: [
                        ("Empty (0%)", 0.0),
                        ("Medium (50%)", 0.5),
                        ("Heavy (100%)", 1.0)
                    ])
                    CLChipPicker(label: "Pedestrian Density & Variety", selection: $s.pedDensity, options: [
                        ("Low (0%)", 0.0),
                        ("Medium (50%)", 0.5),
                        ("Heavy (100%)", 1.0)
                    ])
                    CLToggle(title: "No Traffic / No Peds", isOn: $s.noTraffic)
                    Text("Built-in mod: no traffic cars, no peds, no parked cars. Stronger than the Empty chip — zeroes spawning every frame. Single-player only; also toggles live in the console with notraffic.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    CLChipPicker(label: "Sky Pack (built-in visuals)", selection: $s.sky, options: [
                        ("Off", "off"),
                        ("Pink Sky", "pink"),
                        ("Black Sky", "black"),
                        ("Cyan Sky", "cyan"),
                        ("Purple Sky", "purple")
                    ])
                    Text("Built-in mod: FiveM PvP sky pack — pink, black, cyan or purple sky, no clouds, no rain, no shadows. Applies on Play (the sky colour needs a restart to change); also switches in the console with sky <pink|black|cyan|purple|off>. No painted starfield — the packs' stars live in a texture this port cannot author; the engine's own stars still show at night on Black.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    CLChipPicker(label: "Draw Distance & LOD Scale", selection: $s.distanceScaling, options: [
                        ("Save RAM (-0.5)", -0.5),
                        ("Standard (0.0)", 0.0),
                        ("Far view (+0.5)", 0.5)
                    ])
                }
            }
            .id("detailed")

            VStack(alignment: .leading, spacing: 5) {
                Text("◆ CONTROLS")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    Button(action: { showingHUDEditor = true }) {
                        Label("Adjust button position & size visually (HUD Editor)", systemImage: "hand.draw.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white))
                            .foregroundColor(Color(hex: "0B0D12"))
                    }
                    .buttonStyle(.plain)
                    Button("Reset buttons to default") {
                        s.resetLayout()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    HStack {
                        Text("Look sensitivity").foregroundColor(.white)
                        Slider(value: $s.touch, in: 0.25...6.0, step: 0.25).tint(.white)
                        Text(String(format: "%.2f×", s.touch)).monospacedDigit().frame(width: 48, alignment: .trailing).foregroundColor(.white)
                    }
                    .font(.system(size: 11.5))
                    HStack {
                        Text("Gamepad sensitivity").foregroundColor(.white)
                        Slider(value: $s.padSensitivity, in: 0.25...4.0, step: 0.25).tint(.white)
                        Text(String(format: "%.2f×", s.padSensitivity)).monospacedDigit().frame(width: 48, alignment: .trailing).foregroundColor(.white)
                    }
                    .font(.system(size: 11.5))
                    CLChipPicker(label: "Aim button", selection: $s.aimMode, options: [
                        ("Tap to toggle", "toggle"),
                        ("Hold to aim", "hold")
                    ])
                    CLToggle(title: "Aim while firing", isOn: $s.fireAim)
                    HStack {
                        Text("Aim sensitivity").foregroundColor(.white)
                        Slider(value: $s.aimSensitivity, in: 0.1...3.0, step: 0.1).tint(.white)
                        Text(String(format: "%.2f×", s.aimSensitivity)).monospacedDigit().frame(width: 48, alignment: .trailing).foregroundColor(.white)
                    }
                    .font(.system(size: 11.5))
                    Text("Drag on the right FIRE button to adjust aim while shooting. The left FIRE button frees your right thumb to aim.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    CLToggle(title: "Mute audio", isOn: $s.mute)
                }
            }
            .id("controls")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
    }

    // MARK: - Column 3: Multiplayer + Cheats + Sandbox + Mods + Diagnostics

    private var settingsColumn3: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Text("◆ MULTIPLAYER")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    CLToggle(title: "Enable Multiplayer", isOn: $s.multiplayer)
                    if s.multiplayer {
                        CLChipPicker(label: "Room mode", selection: $s.roomMode, options: [
                            ("Create", "create"),
                            ("Join", "join"),
                            ("Public", "public"),
                            ("LAN", "lan")
                        ])
                        if s.roomMode == "create" {
                            createForm
                        } else if s.roomMode == "join" {
                            joinForm
                        } else if s.roomMode == "public" {
                            publicForm
                        } else {
                            lanForm
                        }
                        DisclosureGroup("Server (Advanced)") {
                            CLDarkField(label: "Server IP", text: $s.server, placeholder: "18.143.103.253", keyboardType: .numbersAndPunctuation)
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("AWS iOSVN Singapore server (Supports 32 / 64 players)")
                                    .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .foregroundColor(.white)
                        Text("Host sync")
                            .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .id("multiplayer")

            if !s.multiplayer {
                VStack(alignment: .leading, spacing: 5) {
                    Text("◆ CHEATS — OFFLINE ONLY")
                        .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                    webGroup {
                        Button(action: { showingCheatSheet = true }) {
                            Label("View & Activate Cheat Codes", systemImage: "wand.and.stars")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white))
                                .foregroundColor(Color(hex: "0B0D12"))
                        }
                        .buttonStyle(.plain)
                        Text("Invincibility, full weapons, helicopter, race cars... Cheat codes are auto-locked in Online mode.")
                            .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .id("cheats")
            }

            if !s.multiplayer {
                VStack(alignment: .leading, spacing: 5) {
                    Text("◆ SANDBOX VEHICLES")
                        .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                    webGroup {
                        CLToggle(title: "Auto-spawn vehicle in Sandbox", isOn: $s.sandboxAutoSpawn)
                            .onChange(of: s.sandboxAutoSpawn) { _ in try? s.save() }
                        Text("When on, every Sandbox session starts you inside the first vehicle below. Turn it off if the spawn ever causes trouble — the CAR button and the in-game menu still work.")
                            .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 6) {
                            ForEach(s.sandboxVehicles, id: \.self) { code in
                                HStack {
                                    Text(code).font(.body.monospaced()).foregroundColor(.white)
                                    Spacer()
                                    if code == s.sandboxVehicles.first {
                                        Text("starter").font(.system(size: 11)).foregroundColor(muguetMuted)
                                    }
                                    Button(action: {
                                        s.sandboxVehicles.removeAll { $0 == code }
                                        try? s.save()
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                            }
                        }
                        HStack {
                            TextField("Add a vehicle code (e.g. loweyezv)", text: $newVehicleCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                            Button("Add") {
                                let c = newVehicleCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                guard !c.isEmpty, !s.sandboxVehicles.contains(c) else { return }
                                s.sandboxVehicles.append(c)
                                newVehicleCode = ""
                                try? s.save()
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "0B0D12"))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.white))
                            .buttonStyle(.plain)
                            .disabled(newVehicleCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("CODES — FIRST = STARTER · CAR · 30s max")
                            .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .id("sandbox")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("◆ MODS")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    Text("Add-on DLC packs (dlc.rpf). Install a mod zip, a bare dlc.rpf, or a whole mod folder (FiveM resource layout: dlc.rpf plus loose .meta files) and the game will mount it. If the pack's own .meta files cannot be read, pick them — vehicles.meta, handling.meta, carvariations.meta and carcols.meta are merged into the game's own files so the vehicle can spawn with its handling, colors, tuning kit and lights. The game reads the mod list at launch — restart the game after installing or removing a mod.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    if installedMods.isEmpty {
                        Text("No add-on mods installed. The 11 built-in packs are not listed here.")
                            .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(installedMods) { mod in
                                HStack {
                                    Text(mod.name).font(.body.monospaced()).foregroundColor(.white)
                                    Spacer()
                                    if !mod.size.isEmpty {
                                        Text(mod.size).font(.system(size: 11)).foregroundColor(muguetMuted)
                                    }
                                    Button(action: {
                                        pickingMetaFor = mod.name
                                        pickingMeta = true
                                    }) {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { modToDelete = mod.name }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button(action: { pickingMod = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Mod…")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "0B0D12"))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .disabled(modsWorking)
                        Button(action: { pickingFolder = true }) {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("Add Folder…")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "0B0D12"))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .disabled(modsWorking)
                    }
                    // Bare .rpf name prompt, inline in the Mods
                    // section — NOT a sheet. Presenting it as a
                    // sheet blacked the screen on three tries
                    // (same-turn present, onDismiss, next
                    // runloop turn): the picker dismissal was
                    // still settling every time. An inline card
                    // needs no UIKit presentation at all, so it
                    // cannot black-screen; it appears as soon as
                    // installModFile stashes the picked URL.
                    if let url = modNameSheetURL {
                        ModNameSheet(name: $modNameText, modelName: $modModelText, metaURL: $modMetaURL, metaFileName: $modMetaFileName, handlingURL: $modHandlingURL, handlingFileName: $modHandlingFileName, carvariationsURL: $modCarvariationsURL, carvariationsFileName: $modCarvariationsFileName, carcolsURL: $modCarcolsURL, carcolsFileName: $modCarcolsFileName, onCancel: {
                            modNameSheetURL = nil
                            modMetaURL = nil
                            modMetaFileName = ""
                            modHandlingURL = nil
                            modHandlingFileName = ""
                            modCarvariationsURL = nil
                            modCarvariationsFileName = ""
                            modCarcolsURL = nil
                            modCarcolsFileName = ""
                        }, onInstall: {
                            let folder = modNameText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let model = modModelText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let meta = modMetaURL
                            let handling = modHandlingURL
                            let carvariations = modCarvariationsURL
                            let carcols = modCarcolsURL
                            modNameSheetURL = nil
                            modMetaURL = nil
                            modMetaFileName = ""
                            modHandlingURL = nil
                            modHandlingFileName = ""
                            modCarvariationsURL = nil
                            modCarvariationsFileName = ""
                            modCarcolsURL = nil
                            modCarcolsFileName = ""
                            runModInstall(url: url, name: folder, modelName: model, metaURL: meta, handlingURL: handling, carvariationsURL: carvariations, carcolsURL: carcols)
                        })
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    if modsWorking {
                        ProgressView().tint(.white)
                    }
                    if !modsStatus.isEmpty {
                        Text(modsStatus).font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("dlc.rpf → dlcPacks/ · Restart · Stock: 11 packs")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                }
                .onAppear { refreshMods() }
            }
            .id("mods")

            VStack(alignment: .leading, spacing: 5) {
                Text("◆ DIAGNOSTICS")
                    .font(.system(size: 11, weight: .black)).kerning(1.0).foregroundColor(.white)
                webGroup {
                    HStack {
                        Text("RAM tracker").foregroundColor(.white)
                        Spacer()
                        Text("LIVE").font(.system(size: 9, weight: .black)).foregroundColor(Color(hex: "86efac"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "14532d"))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .font(.system(size: 11.5))
                    RamLiveLineView()
                    Text("T1 <768 · T2 <384 · T3 <192 MB · T3 = pause")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Share startup / memory logs") { shareDiagnostics() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .buttonStyle(.plain)
                    Text("After a crash, reopen GTA V and share the previous log. Logs contain connection addresses and runtime errors, not game files.")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                    ConsolePreviewView()
                    Text("car · heal · dv · ram · quit")
                        .font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .id("diagnostics")

            Button(action: onLaunch) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                    Text("LAUNCH GTA V").font(.system(size: 11, weight: .black)).kerning(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(muguetPink)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
    }

    // Web drawer group: translucent white fill, 1px border, 4pt radius.
    private func webGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    // Mods manager helpers. The folders under dlcPacks are the source
    // of truth; the stock packs are filtered out here, and Rust refuses
    // them again on install/remove.
    private func modsPacksDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let game = docs.appendingPathComponent("game")
        let normal = game.appendingPathComponent("data/x64/dlcPacks")
        if FileManager.default.fileExists(atPath: normal.path) { return normal }
        return game.appendingPathComponent("gamedat/data/x64/dlcPacks")
    }

    private func refreshMods() {
        let dir = modsPacksDir()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var entries: [ModEntry] = []
        for name in names.sorted() {
            if stockPacks.contains(name.lowercased()) { continue }
            var isDir: ObjCBool = false
            let full = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: full.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let rpf = full.appendingPathComponent("dlc.rpf")
            var sizeText = ""
            if let attrs = try? FileManager.default.attributesOfItem(atPath: rpf.path), let size = attrs[.size] as? NSNumber {
                sizeText = ByteCountFormatter.string(fromByteCount: Int64(size.intValue), countStyle: .file)
            }
            entries.append(ModEntry(name: name, size: sizeText))
        }
        installedMods = entries
    }

    private func installModFile(_ url: URL) {
        if url.pathExtension.lowercased() == "rpf" {
            // A bare dlc.rpf carries no folder name, so ask for it.
            // A zip skips this: Rust takes the name from the zip.
            // Only stash the URL here — the inline name card in the
            // Mods section appears from the stashed URL; there is no
            // follow-up sheet (the sheet blacked the screen).
            let stem = url.deletingPathExtension().lastPathComponent
            let prefill = stem.lowercased() == "dlc" ? "" : stem.lowercased()
            modNameText = prefill
            modModelText = prefill
            modNameSheetURL = url
            return
        }
        runModInstall(url: url, name: "")
    }

    // modelName is the spawn code for a bare .rpf install (typed in
    // the name sheet; blank falls back to the folder name). For a zip
    // it is empty and the folder name Rust returns is the code, as
    // before. The folder name always goes to Rust for the dlcPacks
    // path and the dlcList.xml line; only the sandboxVehicles entry
    // takes the model name.
    // Install a .meta for an already-installed mod (META button on
    // its row): the mod does not have to be reinstalled. The picked
    // file's name decides which merge runs — vehicles.meta,
    // handling.meta, carvariations.meta or carcols.meta — so one
    // button covers all four; anything else is refused with a plain
    // message.
    private func runMetaInstall(mod: String, url: URL) {
        let file = url.lastPathComponent.lowercased()
        let label: String
        let install: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Bool
        let modelsFn: () -> UnsafePointer<CChar>?
        switch file {
        case "handling.meta":
            label = "handling.meta"
            install = muguet_install_handling_meta
            modelsFn = muguet_handling_meta_models
        case "carvariations.meta":
            label = "carvariations.meta"
            install = muguet_install_carvariations_meta
            modelsFn = muguet_carvariations_meta_models
        case "carcols.meta":
            label = "carcols.meta"
            install = muguet_install_carcols_meta
            modelsFn = muguet_carcols_meta_models
        case "vehicles.meta":
            label = "vehicles.meta"
            install = muguet_install_vehicles_meta
            modelsFn = muguet_vehicles_meta_models
        default:
            modsStatus = "Not a supported .meta — pick vehicles.meta, handling.meta, carvariations.meta or carcols.meta."
            return
        }
        modsWorking = true
        modsStatus = "Installing \(label)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mod.withCString { m in
                url.path.withCString { p in install(m, p) }
            }
            let models = modelsFn().map { String(cString: $0) } ?? ""
            let err = muguet_mod_error().map { String(cString: $0) } ?? "\(label) install failed."
            DispatchQueue.main.async {
                modsWorking = false
                if ok {
                    modsStatus = models.isEmpty
                        ? "\(label) installed for \(mod). Restart the game to use it."
                        : "\(label) installed for \(mod): \(models). Restart the game to use it."
                } else {
                    modsStatus = "\(label) install failed: \(err)"
                }
            }
        }
    }

    private func runModInstall(url: URL, name: String, modelName: String = "", metaURL: URL? = nil, handlingURL: URL? = nil, carvariationsURL: URL? = nil, carcolsURL: URL? = nil) {
        modsWorking = true
        modsStatus = "Installing…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.path.withCString { path in
                name.withCString { n in muguet_install_mod(path, n) }
            }
            let installed = muguet_mod_name().map { String(cString: $0) } ?? ""
            let err = muguet_mod_error().map { String(cString: $0) } ?? "Install failed."
            // Each .meta picked in the name sheet installs right
            // after the .rpf, in the same background turn, so the
            // status can report all parts at once.
            var metaNote = ""
            func installMeta(_ label: String, _ picked: URL?, _ install: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Bool, _ modelsFn: () -> UnsafePointer<CChar>?) {
                guard let picked else { return }
                let metaOk = installed.withCString { m in
                    picked.path.withCString { p in install(m, p) }
                }
                let models = modelsFn().map { String(cString: $0) } ?? ""
                if metaOk {
                    metaNote += models.isEmpty ? " \(label) registered." : " \(label) registered \(models)."
                } else {
                    let metaErr = muguet_mod_error().map { String(cString: $0) } ?? "\(label) install failed."
                    metaNote += " \(label) failed: \(metaErr)"
                }
            }
            if ok, !installed.isEmpty {
                installMeta("vehicles.meta", metaURL, muguet_install_vehicles_meta, muguet_vehicles_meta_models)
                installMeta("handling.meta", handlingURL, muguet_install_handling_meta, muguet_handling_meta_models)
                installMeta("carvariations.meta", carvariationsURL, muguet_install_carvariations_meta, muguet_carvariations_meta_models)
                installMeta("carcols.meta", carcolsURL, muguet_install_carcols_meta, muguet_carcols_meta_models)
            }
            DispatchQueue.main.async {
                modsWorking = false
                if ok, !installed.isEmpty {
                    let vehicleCode = modelName.isEmpty ? installed : modelName
                    if vehicleCode == installed {
                        modsStatus = "Installed \(installed).\(metaNote) Restart the game to use it."
                    } else {
                        modsStatus = "Installed \(installed) — spawn it with \(vehicleCode).\(metaNote) Restart the game to use it."
                    }
                    if !s.sandboxVehicles.contains(vehicleCode) {
                        s.sandboxVehicles.append(vehicleCode)
                        try? s.save()
                    }
                    refreshMods()
                } else {
                    modsStatus = "Install failed: \(err)"
                }
            }
        }
    }

    // Whole-folder install (Add Folder…): the folder name is the
    // mod name, so there is no name prompt. The folder opens in
    // place, so the pick holds security-scoped access until the
    // background install finishes reading it.
    private func runFolderInstall(url: URL) {
        modsWorking = true
        modsStatus = "Installing folder…"
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.path.withCString { path in
                "".withCString { n in muguet_install_mod_folder(path, n) }
            }
            let installed = muguet_mod_name().map { String(cString: $0) } ?? ""
            let err = muguet_mod_error().map { String(cString: $0) } ?? "Install failed."
            if scoped { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                modsWorking = false
                if ok, !installed.isEmpty {
                    modsStatus = "Installed \(installed) from folder. Restart the game to use it."
                    if !s.sandboxVehicles.contains(installed) {
                        s.sandboxVehicles.append(installed)
                        try? s.save()
                    }
                    refreshMods()
                } else {
                    modsStatus = "Install failed: \(err)"
                }
            }
        }
    }

    private func removeMod(_ name: String) {
        modsWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = name.withCString { muguet_remove_mod($0) }
            let err = muguet_mod_error().map { String(cString: $0) } ?? "Remove failed."
            DispatchQueue.main.async {
                modsWorking = false
                if ok {
                    modsStatus = "Removed \(name)."
                    // Folder names come from disk and may carry capitals
                    // while sandboxVehicles entries are lowercased at add
                    // time, so compare lowercased or a removed mod keeps
                    // auto-spawning.
                    s.sandboxVehicles.removeAll { $0.lowercased() == name.lowercased() }
                    try? s.save()
                    refreshMods()
                } else {
                    modsStatus = "Remove failed: \(err)"
                }
            }
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Pick a room mode:").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                CLChipPicker(label: "Mode", selection: $s.mode, options: [
                    ("Story Mode", 1),
                    ("Sandbox (Free Roam)", 2)
                ])
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("2. Damage rules (PvP):").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                CLChipPicker(label: "PvP", selection: $s.pvp, options: [
                    ("Peaceful (Co-op)", false),
                    ("Arena (PvP)", true)
                ])
                Text(s.pvp ? "PvP On: Players can shoot and kill each other." : "Peaceful: No damage to each other, no spawn killing.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("3. Max players (Server capacity):").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                CLChipPicker(label: "Player limit", selection: $s.maxPlayers, options: [
                    ("32 players", 32),
                    ("64 players", 64)
                ])
                Text("Creating a room supports up to \(s.maxPlayers) players online at the same time.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("4. Room code to share with friends:").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(s.formattedCreateCode)
                        .font(.title2.monospaced().bold())
                        .foregroundStyle(Color(hex: "7EE787"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "7EE787").opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    Spacer(minLength: 4)
                    Button(action: {
                        s.roomDigits = String(Int.random(in: 1000...9999))
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                    .help("Change code")
                    Button(action: {
                        UIPasteboard.general.string = s.formattedCreateCode
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                }
            }
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                TextField("Room password (Optional)", text: $s.roomPass)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
            }
            HStack(spacing: 8) {
                Label(s.mode == 1 ? "Story Mode" : "Sandbox", systemImage: "gamecontroller")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(s.mode == 1 ? .orange : .cyan)
                Text("•").foregroundColor(.white.opacity(0.55))
                Label(s.pvp ? "PvP On" : "Peaceful Co-op", systemImage: s.pvp ? "burst.fill" : "shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(s.pvp ? .red : .green)
                Text("•").foregroundColor(.white.opacity(0.55))
                Label(s.roomPass.isEmpty ? "Open Room" : "Has Password", systemImage: s.roomPass.isEmpty ? "lock.open" : "lock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter room code:").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                TextField("Example: SP-8621 or BX-5520", text: $s.joinCode)
                    .font(.title3.monospaced().bold())
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                    .onChange(of: s.joinCode) { val in
                        s.parseJoinCode(val)
                    }
            }
            let clean = s.joinCode.trimmingCharacters(in: .whitespaces).uppercased()
            if !clean.isEmpty {
                HStack(spacing: 8) {
                    Label(s.mode == 1 ? "Story Mode" : "Sandbox", systemImage: "gamecontroller")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(s.mode == 1 ? .orange : .cyan)
                    Text("•").foregroundColor(.white.opacity(0.55))
                    Label(s.pvp ? "PvP On" : "Peaceful Co-op", systemImage: s.pvp ? "burst.fill" : "shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(s.pvp ? .red : .green)
                    Spacer()
                    Text("Auto-synced")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(hex: "7EE787").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Game mode (Story / Sandbox) and PvP rules auto-sync to the host's room code.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                TextField("Room password (if the host set one)", text: $s.roomPass)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
            }
            Text("Note: PvP damage rules and game mode follow the host completely, you can't change them yourself.")
                .font(.system(size: 12)).foregroundColor(.orange)
        }
    }

    private var publicForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            CLChipPicker(label: "Public region", selection: $s.mode, options: [
                ("Story Mode Public", 1),
                ("Sandbox Public", 2)
            ])
            HStack {
                Image(systemName: "globe.americas.fill").foregroundStyle(.green)
                Text("Public shared lobby (Supports 32 / 64 players per room)")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            Text("Auto-connects to the shared lobby with players online on the AWS iOSVN server. Peaceful mode is on by default.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
        }
    }

    private var lanForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            CLChipPicker(label: "LAN Mode", selection: $s.mode, options: [
                ("Story Mode", 1),
                ("Sandbox", 2)
            ])
            Text("Host a room on Wi-Fi (Up to \(s.maxPlayers) players): Connect via: \(localIPs().joined(separator: " or "))")
                .font(.system(size: 15)).textSelection(.enabled).foregroundColor(.white)
        }
    }
}


struct LauncherView: View {
    @StateObject private var s = Settings()
    @ObservedObject private var importer = Importer.shared
    @State private var error: String?
    @State private var picking = false
    @State private var showingCheatSheet = false
    @State private var showingHUDEditor = false
    @State private var showingResetAlert = false
    @State private var resetAlertMessage = ""
    @State private var newVehicleCode = ""
    @State private var showingSettings = false
    @State private var settingsSection: String?
    @State private var showingConsole = false
    @State private var infoMessage: String?
    var isOverlay: Bool = false
    let play: () -> Void

    // Mode rail selection, derived from the same vars the old pickers set:
    // 0 Story, 1 Sandbox, 2 Online.
    private var selectedMode: Int {
        if s.multiplayer { return 2 }
        return s.mode == 1 ? 0 : 1
    }

    private func selectMode(_ index: Int) {
        if index == 2 {
            s.multiplayer = true
        } else {
            s.multiplayer = false
            s.mode = index == 0 ? 1 : 2
        }
    }

    private var modeName: String {
        if s.multiplayer { return "Online" }
        return s.mode == 1 ? "Story" : "Sandbox"
    }

    private var statusLine: String {
        if !muguet_has_game_code() { return "No game code in this build" }
        if importer.progress != nil { return "Importing game data…" }
        if !importer.ready { return "Import game data to play" }
        return "\(modeName) · Game data ready"
    }

    private func openSettings(section: String? = nil) {
        settingsSection = section
        showingSettings = true
    }

    private func closeSettings() {
        // Panel edits only reached disk via Play/Continue
        // before, so closing the panel silently lost
        // them. Save here; Play still saves again.
        try? s.save()
        settingsSection = nil
        showingSettings = false
    }

    var body: some View {
        GeometryReader { geo in
            if !isOverlay && geo.size.width < geo.size.height {
                rotateView
            } else {
                ZStack(alignment: .topLeading) {
                    Color(hex: "070708").ignoresSafeArea()
                    VStack(spacing: 0) {
                        topBar
                        ScrollView(.vertical, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 5) {
                                leftColumn(width: (geo.size.width - 15) * 0.465)
                                middleColumn(width: (geo.size.width - 15) * 0.26)
                                rightColumn(width: (geo.size.width - 15) * 0.26)
                            }
                            .padding(5)
                        }
                    }
                    if showingSettings {
                        CLSettingsPanel(s: s, showingCheatSheet: $showingCheatSheet, showingHUDEditor: $showingHUDEditor, showingResetAlert: $showingResetAlert, resetAlertMessage: $resetAlertMessage, newVehicleCode: $newVehicleCode, jumpSection: $settingsSection, onClose: closeSettings, onLaunch: { start() })
                            .transition(.opacity)
                            .zIndex(20)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: showingSettings)
        // checkStartupError used to run only from importView, so a
        // startup-error file was never shown (or cleared) once the
        // game data was already ready. Check on every appearance.
        .onAppear(perform: { checkStartupError(); checkLowMemoryHint() })
        .sheet(isPresented: $picking) {
            DocumentPicker(isPresented: $picking, onPick: { url in
                importer.run(url)
            }, onError: { message in
                importer.error = "Import failed: \(message)"
                message.withCString { muguet_debug_log($0) }
            })
        }
        .sheet(isPresented: $showingCheatSheet) {
            CheatMenuView(onApply: { code in
                code.withCString { muguet_apply_cheat($0) }
            })
        }
        .fullScreenCover(isPresented: $showingHUDEditor) {
            HUDEditorView(settings: s)
        }
        .fullScreenCover(isPresented: $showingConsole) {
            ConsoleView(onClose: { showingConsole = false })
        }
        .alert("Graphics Notice", isPresented: $showingResetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resetAlertMessage)
        }
        .alert("Muguet", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
            Button("OK", role: .cancel) { infoMessage = nil }
        } message: {
            if let infoMessage { Text(infoMessage) }
        }
    }

    // MARK: - Rotate prompt (portrait)

    private var rotateView: some View {
        ZStack {
            Color(hex: "060607").ignoresSafeArea()
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 54, height: 88)
                Text("ROTATE YOUR iPHONE")
                    .font(.system(size: 20, weight: .bold))
                    .kerning(1)
                    .foregroundColor(.white)
                Text("Landscape only — turn sideways.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "c9ccd0"))
                Text("λ Muguet · GTA V iOS Port · \(appVersionLabel)")
                    .font(.system(size: 11))
                    .foregroundColor(muguetMuted2)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                topNavButton("GITHUB") {
                    infoMessage = "Source — github.com/pentafcb/muguet-gta"
                }
                topNavButton("UPSTREAM") {
                    infoMessage = "Fork of c22dev/muguet via iOSVNNews/muguet-ios-build"
                }
                topNavButton("BUILD 8.9") {
                    infoMessage = "This fork: \(appVersionLabel) · latest official release: Build \(upstreamBuild)"
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("IPA ≈70 MB · iOS 15+")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: "cfd3d8"))
                Text(appVersionLabel)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: "cfd3d8"))
            }
            .padding(.trailing, 6)
            Button(action: {
                if importer.ready {
                    infoMessage = "Game data: Ready — manifest.json · game.wasm on disk."
                } else {
                    picking = true
                }
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(importer.ready ? muguetGreen : muguetAmber)
                        .frame(width: 6, height: 6)
                    Text(importer.ready ? "GAME DATA READY" : "IMPORT GAME DATA")
                        .font(.system(size: 10.5, weight: .black))
                        .kerning(0.6)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(Color(hex: "0d0e12"))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(muguetPink, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            Button(action: { showingConsole = true }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Button(action: { infoMessage = "Close is disabled in the launcher." }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: "0d0e12"))
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .bottom)
    }

    private func topNavButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.7)
                .foregroundColor(Color(hex: "e8e9eb"))
                .padding(.horizontal, 8)
                .frame(height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Left column

    private func leftColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            playCard
            modeStrip
            midRow
            bottomRow
            presetsCard
            consoleCard
            footer
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var playCard: some View {
        webCard {
            HStack(spacing: 8) {
                Text("λ")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(muguetPink2)
                Text("PLAY")
                    .font(.system(size: 23, weight: .black))
                    .foregroundColor(.white)
                Spacer()
                Text("\(s.fps) fps")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text("GTA V · iOS · c22dev · game.zip · manifest.json · game.wasm · shaders")
                .font(.system(size: 10.5))
                .lineSpacing(1.5)
                .foregroundColor(Color(hex: "d6d8db"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            Button(action: {
                if importer.ready { start() } else { picking = true }
            }) {
                HStack(spacing: 8) {
                    Image("HeroIcon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("GTA V files")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(importer.ready ? "READY" : "IMPORT")
                        .font(.system(size: 10.5))
                        .foregroundColor(muguetMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(muguetInset)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            HStack(spacing: 5) {
                Circle().fill(muguetGreen).frame(width: 6, height: 6)
                Text("\(statusLine) · \(appVersionCompact) · 70 MB · iOS 15+ · \(Int(s.scale * 100))% · \(s.fps) fps · \(s.name)")
                    .font(.system(size: 10))
                    .foregroundColor(muguetMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            if let error {
                Text(error).foregroundStyle(.red).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            actionArea
                .padding(.top, 6)
        }
    }

    @ViewBuilder private var actionArea: some View {
        if !muguet_has_game_code() {
            Text("This build has no game code: build it with ./make-ios.sh <game.zip>.")
                .foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
        } else if !importer.ready || importer.progress != nil {
            importView
        } else if isOverlay {
            Button(action: resumeAndSave) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 13))
                    Text("Continue").font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.white))
                .foregroundColor(Color(hex: "0B0D12"))
            }
            .buttonStyle(.plain)
            Button(action: { suspendApp() }) {
                Text("Quit the app")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        } else {
            playButton
            Button("Import other game data…") { picking = true }
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder var importView: some View {
        VStack(spacing: 10) {
            if let p = importer.progress {
                ProgressView(value: p)
                Text("Importing… \(Int(p * 100)) %").font(.callout).monospacedDigit()
            } else {
                Button("Import game data .zip") { picking = true }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Quick install guide using the Files app:")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text("1. Unzip the zip file with the data on your computer or in the Files app.\n2. Open the Files app > On My iPhone/iPad > GTA V.\n3. Create a folder named 'game' (lowercase).\n4. Paste the 2 folders 'data' and 'b' inside the 'game' folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Divider().padding(.vertical, 2)
                    Text("Storage note: The full game takes ~21 GB. If you unzip directly on iPhone/iPad you need at least 42 GB free (21 GB zip + 21 GB unzipped; after finishing, delete the zip and it goes back to 21 GB). Unzipping on your computer first and copying it over only uses 21 GB on the device.")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let e = importer.error { Text(e).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
        }
        .onAppear(perform: checkStartupError)
    }

    @ViewBuilder var playButton: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 13))
                Text("Play").font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(muguetPink))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var modeStrip: some View {
        HStack(spacing: 5) {
            modeButton(title: "Story", sub: "Campaign", index: 0)
            modeButton(title: "Sandbox", sub: "Free roam", index: 1)
            modeButton(title: "Online", sub: "Public · LAN", index: 2)
        }
    }

    private func modeButton(title: String, sub: String, index: Int) -> some View {
        let focused = selectedMode == index
        return Button { selectMode(index) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("▷ \(title)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundColor(muguetMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(focused ? muguetPink.opacity(0.25) : muguetPanel3)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(focused ? muguetPink : Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var midRow: some View {
        HStack(spacing: 5) {
            Button { selectMode(0) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("▷ STORY")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                    Text("Phone > Quick Save")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "c9ccd0"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(muguetPanel)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { openSettings(section: "sandbox") } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("▷ SANDBOX VEHICLES")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                    Text("First code = starter · CAR = spawn")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "c9ccd0"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(muguetPanel)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 5) {
            bottomCard(title: "MULTIPLAYER", sub: "\(s.server) · \(s.maxPlayers) max") { openSettings(section: "multiplayer") }
            bottomCard(title: "MODS & DLC", sub: "\(installedModNames().count) mods · 11 packs") { openSettings(section: "mods") }
            bottomCard(title: "PRESETS", sub: "120 FPS · Save RAM · Ultra Low") { openSettings(section: "graphics") }
            bottomCard(title: "ABOUT MUGUET", sub: "muguet-gta · B\(upstreamBuild)") {
                infoMessage = "Muguet \(appVersionLabel) · by c22dev · latest official release Build \(upstreamBuild) · iOS 15+"
            }
        }
    }

    private func bottomCard(title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .black))
                    .kerning(0.3)
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "c9ccd0"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(muguetPanel)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var presetsCard: some View {
        webCard {
            webCardTitle("PRESETS")
            presetInfoRow(title: "120 FPS", desc: "120 fps · 50% · V-Sync · Deep Opt") {
                s.apply120FpsBoost()
                resetAlertMessage = "120 FPS Super Smooth setup enabled!"
                showingResetAlert = true
            }
            presetInfoRow(title: "Save RAM", desc: "800 MB–1 GB") {
                s.applyLowRamMode()
                resetAlertMessage = "Super RAM Saver setup enabled (~800MB)!"
                showingResetAlert = true
            }
            presetInfoRow(title: "Ultra Low", desc: "25% · Tex 0 · Shader 1 · rest 0") {
                s.applyUltraLowMode()
                resetAlertMessage = "Ultra Low setup enabled — shadows & reflections off, 25% resolution!"
                showingResetAlert = true
            }
            presetInfoRow(title: "Rockstar", desc: "Shader High · MSAA Off · 120 FPS") {
                s.applyRockstarDefaults()
                resetAlertMessage = "Restored Rockstar GTA V graphics to safe defaults (Shader High, MSAA Off, Shadows Normal, 120 FPS). The black screen caused by Max Settings is fully fixed!"
                showingResetAlert = true
            }
        }
    }

    private func presetInfoRow(title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .font(.system(size: 10.5, weight: .black))
                        .foregroundColor(.white)
                    if currentPresetName(s) == title.uppercased() {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(muguetPink)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    Spacer()
                }
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "c9ccd0"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var consoleCard: some View {
        webCard {
            webCardTitle("CONSOLE")
            Button(action: { showingConsole = true }) {
                VStack(alignment: .leading, spacing: 4) {
                    FlowChips(items: consoleCommands)
                    webNote("weather: SUNNY · CLEAR · RAIN · SNOW · XMAS +9")
                    webNote("Scroll off = frozen")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("proudly made by c22dev").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            Text("Rebuild: Pentacampeon").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: - Middle column: The Project

    private func middleColumn(width: CGFloat) -> some View {
        let mods = installedModNames()
        return VStack(alignment: .leading, spacing: 5) {
            webCard {
                Text("THE PROJECT")
                    .font(.system(size: 12.5, weight: .black))
                    .kerning(0.7)
                    .foregroundColor(Color(hex: "dfe2e6"))
                    .padding(.bottom, 2)
                feedPost(avatar: "λ", name: "pentafcb / muguet-gta", time: "this build",
                         body: "\(appVersionCompact) · 70 MB · iOS 15+",
                         avatarURL: "https://avatars.githubusercontent.com/u/68836355?v=4")
                feedPost(avatar: "c", name: "c22dev / muguet", time: "upstream",
                         body: "c22dev · iOSVNNews · B\(upstreamBuild)",
                         avatarURL: "https://avatars.githubusercontent.com/u/102235607?v=4")
                feedPost(avatar: "λ", name: "Build", time: "CI",
                         body: "Rust 1.98.1 · aarch64")
                feedPost(avatar: "▣", name: "Game data", time: "on this iPhone",
                         body: importer.ready
                            ? "Ready · \(Int(s.scale * 100))% · \(s.fps) fps · \(modeName)"
                            : "Not imported yet")
            }
            webCard {
                webCardTitle("MULTIPLAYER")
                webKV("Server IP", s.server, mono: true)
                webKV("Host", "AWS · SG")
                webKV("Ping", "—")
                webKV("Players", "Max \(s.maxPlayers)")
                webKV("Rooms", "Create · Join · Public · LAN")
                webNote("Host sync · Cheats offline")
                    .padding(.top, 3)
            }
            .onTapGesture { openSettings(section: "multiplayer") }
            webCard {
                webCardTitle("MODS & STOCK DLC")
                webNote("dlc.rpf → dlcPacks/ · Restart")
                if mods.isEmpty {
                    webNote("No add-on mods installed.")
                } else {
                    ForEach(mods, id: \.self) { name in
                        HStack(spacing: 5) {
                            Text(name).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                            Text(installedModSize(name)).font(.system(size: 10)).foregroundColor(muguetMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Stock (11):")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 3)
                FlowChips(items: stockPackList, gold: true)
            }
            .onTapGesture { openSettings(section: "mods") }
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: - Right column: In This Build

    private func rightColumn(width: CGFloat) -> some View {
        let mods = installedModNames()
        return VStack(alignment: .leading, spacing: 5) {
            webCard {
                Text("IN THIS BUILD")
                    .font(.system(size: 12.5, weight: .black))
                    .kerning(0.7)
                    .foregroundColor(Color(hex: "dfe2e6"))
                    .padding(.bottom, 2)
                feedPost(avatar: "λ", name: "RAM tracker", time: "Build 8",
                         body: "<768 · <384 · <192 MB")
                feedPost(avatar: "λ", name: "In-game console", time: "Build 8",
                         body: "car · heal · dv · ram · quit +16")
                feedPost(avatar: "λ", name: "Presets", time: "launcher",
                         body: "120 FPS · Save RAM · Ultra Low")
                feedPost(avatar: "λ", name: "Mods", time: "Build 8",
                         body: mods.isEmpty ? "No mods installed" : mods.joined(separator: " · "))
                feedPost(avatar: "λ", name: "Patcher & spawn", time: "Build 8",
                         body: "[patch] off · spawninfo ✓")
            }
            webCard {
                webCardTitle("RAM")
                RamLiveLineView()
                VStack(alignment: .leading, spacing: 2) {
                    ramTierRow("T0", "OK", color: muguetGreen)
                    ramTierRow("T1", "< 768 MB", color: muguetAmber)
                    ramTierRow("T2", "< 384 MB · 30 FPS", color: muguetRed)
                    ramTierRow("T3", "< 192 MB · pause", color: muguetRed)
                }
                .padding(.top, 2)
                webNote("Fallback: 2.0 / 2.3 / 2.55 GB")
                    .padding(.top, 3)
            }
            webCard {
                webCardTitle("BUILD · SAVES · DIAGNOSTICS")
                webKV("Version", "\(appVersionCompact) · B\(upstreamBuild)")
                webKV("Creator", "c22dev")
                webKV("Needs", "game.zip · game.wasm · iOS 15+")
                webKV("Built with", "Rust 1.98.1")
                webKV("Entitlements", "mem-limit · virt-addr")
                webKV("Save", "Files > GTA V > saves")
                Button(action: { shareDiagnostics() }) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("Diagnostics")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(muguetMuted)
                            .frame(width: 86, alignment: .leading)
                        Text("Logs · previous log")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "dde0e3"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func ramTierRow(_ tier: String, _ desc: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(tier).font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text(desc).font(.system(size: 10)).foregroundColor(Color(hex: "c9ccd0"))
        }
    }

    // MARK: - Startup / launch

    // The Rust engine writes Documents/muguet-startup-error.txt when
    // config fails before the game window exists (main.rs); the app
    // then exits, so surface it here on the next launch instead of
    // leaving the user with a silent quit. Deleted after one show.
    // A session that ran low on memory leaves a hint file; the next
    // launch starts on Ultra Low instead of walking into the same
    // wall. The file is deleted after applying, so this runs once.
    // Called on appearance and at Play, so the preset is in effect
    // for the launch that follows.
    private func checkLowMemoryHint() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("muguet-low-memory-hint.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["preset"] as? String == "ultra_low" else { return }
        try? FileManager.default.removeItem(at: url)
        s.applyUltraLowMode()
        infoMessage = "Last session ran low on memory — started on Ultra Low. Raise the settings again whenever you like."
    }

    private func checkStartupError() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("muguet-startup-error.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return }
        error = text
        try? FileManager.default.removeItem(at: url)
    }

    func resumeAndSave() {
        do { try s.save() } catch {}
        s.applyCustomLayout()
        play()
        muguet_reload_settings()
    }

    func start() {
        // Belt-and-braces with onAppear: the preset must be in
        // effect for this launch even if the view never re-appeared.
        checkLowMemoryHint()
        if s.multiplayer && s.roomMode == "join" {
            let digits = s.joinCode.filter { $0.isNumber }
            if digits.isEmpty {
                error = "Enter the room code (e.g. SP-8621) to play with friends."
                return
            }
        }
        if s.multiplayer && s.roomMode != "lan" && s.server.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter the server address to connect."
            return
        }
        if s.name.trimmingCharacters(in: .whitespaces).isEmpty {
            // Settled default is Pentacampeon, not a random Player name.
            s.name = "Pentacampeon"
        }
        do { try s.save() } catch { self.error = "Could not save settings: \(error.localizedDescription)"; return }
        s.applyCustomLayout()
        play()
    }
}

// Wrapping chip flow for the console command list / stock packs.
private struct FlowChips: View {
    let items: [String]
    var gold: Bool = false
    var body: some View {
        // Simple left-aligned wrapping layout via flexible rows.
        VStack(alignment: .leading, spacing: 3) {
            ForEach(chipRows(), id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { item in
                        webChip(item, gold: gold)
                    }
                }
            }
        }
    }

    // Greedy wrap on an estimated character width (chips are ~9pt mono).
    private func chipRows() -> [[String]] {
        var rows: [[String]] = [[]]
        var width = 0
        for item in items {
            // ~6pt per char + 12pt padding, budget ~230pt per row.
            let w = item.count * 6 + 14
            if width + w > 230 && !rows[rows.count - 1].isEmpty {
                rows.append([])
                width = 0
            }
            rows[rows.count - 1].append(item)
            width += w
        }
        return rows
    }
}

@_cdecl("muguet_physical_memory")
public func muguetPhysicalMemory() -> UInt64 { ProcessInfo.processInfo.physicalMemory }

private final class RefreshHint: NSObject {
    static let shared = RefreshHint()
    var link: CADisplayLink?
    private let condition = NSCondition()
    private var vsyncCount: UInt64 = 0
    var lockedPacingEnabled: Bool = false

    @objc func tick(_ link: CADisplayLink) {
        guard lockedPacingEnabled else { return }
        condition.lock()
        vsyncCount &+= 1
        condition.broadcast()
        condition.unlock()
    }

    func set(_ requested: UInt32, lockedPacing: Bool = false) {
        self.lockedPacingEnabled = lockedPacing
        let screenMax = Float(UIScreen.main.maximumFramesPerSecond)
        let maximum = max(120.0, screenMax)
        let rate = requested == 0 ? maximum : min(maximum, Float(requested))
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
        if lockedPacing {
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        } else {
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, rate), maximum: rate, preferred: rate)
        }
    }

    func waitVsync(timeoutMs: UInt32) -> Bool {
        guard lockedPacingEnabled else { return true }
        condition.lock()
        let current = vsyncCount
        let deadline = Date(timeIntervalSinceNow: Double(timeoutMs) / 1000.0)
        var signaled = false
        while vsyncCount == current {
            if !condition.wait(until: deadline) {
                break
            }
            signaled = true
        }
        condition.unlock()
        return signaled
    }
}

@_cdecl("muguet_set_refresh_rate")
public func muguetSetRefreshRate(_ fps: UInt32) {
    // Do NOT build a Settings() here: init() reads config.json from
    // disk and re-applies the saved button layout, so every FPS change
    // used to do disk I/O and clobber unsaved layout edits. The cached
    // value is updated by every Settings init/save instead.
    DispatchQueue.main.async { RefreshHint.shared.set(fps, lockedPacing: Settings.cachedPromotionSync) }
}

@_cdecl("muguet_wait_vsync")
public func muguetWaitVsync(_ timeoutMs: UInt32) -> Bool {
    return RefreshHint.shared.waitVsync(timeoutMs: timeoutMs)
}

// The foreground-active scene's key window. connectedScenes.first
// can be a background scene (iPad / multi-scene), so menus and share
// sheets used to present on the wrong window or silently do nothing.
func foregroundKeyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
        ?? scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
}

func foregroundRootViewController() -> UIViewController? {
    foregroundKeyWindow()?.rootViewController
}

// Apple treats programmatic exit(0) as a crash: no scene lifecycle,
// no save flush. Suspend to the background instead (same as pressing
// Home); the user can swipe the app away normally.
func suspendApp() {
    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
}

@_cdecl("muguet_open_menu")
public func muguetOpenMenu() {
    DispatchQueue.main.async {
        guard let root = foregroundRootViewController() else { return }
        var presenter = root
        // A double MENU tap used to stack a second menu alert on the
        // first. Bail if one is already anywhere in the chain.
        while let child = presenter.presentedViewController {
            if let alert = child as? UIAlertController, alert.title == "GTA V Menu" { return }
            presenter = child
        }

        let alert = UIAlertController(title: "GTA V Menu", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Continue playing", style: .cancel))

        alert.addAction(UIAlertAction(title: "Adjust button position & size (HUD)", style: .default, handler: { _ in
            let host = UIHostingController(rootView: HUDEditorView(settings: Settings()))
            host.modalPresentationStyle = .fullScreen
            presenter.present(host, animated: true)
        }))

        let isMp = muguet_is_multiplayer()
        if !isMp {
            alert.addAction(UIAlertAction(title: "Cheat code list", style: .default, handler: { _ in
                let cheatHost = UIHostingController(rootView: CheatMenuView(onApply: { code in
                    code.withCString { muguet_apply_cheat($0) }
                }))
                cheatHost.modalPresentationStyle = .formSheet
                presenter.present(cheatHost, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "Spawn a vehicle", style: .default, handler: { _ in
                let host = UIHostingController(rootView: VehicleMenuView(codes: Settings().sandboxVehicles, onSpawn: { code in
                    code.withCString { muguet_spawn_vehicle($0) }
                }))
                host.modalPresentationStyle = .formSheet
                presenter.present(host, animated: true)
            }))
        }

        // Post FX is local visuals only (host-side shaders, no game
        // state), so it is offered in multiplayer too — unlike the
        // cheat and spawn entries above, which stay single-player.
        alert.addAction(UIAlertAction(title: "Post FX (visual effects)", style: .default, handler: { _ in
            let host = UIHostingController(rootView: FxMenuView())
            host.modalPresentationStyle = .formSheet
            presenter.present(host, animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Settings & Options", style: .default, handler: { _ in
            weak var sheet: UIViewController?
            let host = UIHostingController(rootView: LauncherView(isOverlay: true, play: {
                sheet?.dismiss(animated: true)
                muguet_reload_settings()
            }))
            sheet = host
            host.modalPresentationStyle = .fullScreen
            host.isModalInPresentation = true
            presenter.present(host, animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Restore graphics (Fix black screen)", style: .destructive, handler: { _ in
            resetGraphicsSettings()
        }))

        alert.addAction(UIAlertAction(title: "Quit app", style: .destructive, handler: { _ in
            suspendApp()
        }))

        presenter.present(alert, animated: true)
    }
}

// FiveM-style in-game console (F8): a dark panel over the top ~55%
// of the screen with the latest log lines and an input row. It polls
// muguet_console_tail() while open. Header has an Auto-scroll toggle
// (on by default); off FREEZES the displayed text — the 0.5 s poller
// keeps running, but logText is not replaced, so new lines arriving
// every second cannot push the top lines out of view and make the
// panel look like it is still scrolling. Turning it back on resumes
// live updates and jumps to the bottom. Typing a command also resumes
// live view, so its output is visible at once. Commands: car/spawn,
// heal, kill, fix, tp, coords, weather, cheat, fp, ram, dlc, reload,
// lowram, ultralow, dv, tpm, fx, quit, help, clear, close — see help in
// the console.
// The auto-scroll flag lives in a reference type, not a plain @State
// Bool: an .onChange(of: logText) closure captures the flag from the
// render pass that created it, so a @State Bool read there can stay
// stuck on its first value and keep scrolling after the toggle turns
// it off. Reading the live property through this object at fire time
// is always current.
final class ConsoleScrollState: ObservableObject {
    @Published var autoScroll = true
}
struct ConsoleView: View {
    @State private var logText = ""
    @State private var input = ""
    @StateObject private var scrollState = ConsoleScrollState()
    @State private var pollTick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            // ScrollViewReader wraps the whole panel so the header
            // toggle can scroll back to the bottom when auto-scroll
            // is turned on again.
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack {
                        Text("Console").font(.headline)
                        Spacer()
                        Button(scrollState.autoScroll ? "Auto-scroll: On" : "Auto-scroll: Off") {
                            scrollState.autoScroll.toggle()
                            if scrollState.autoScroll { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .font(.subheadline)
                        Button("Open log") { shareDiagnostics() }
                            .font(.subheadline)
                        Button("Close") { onClose() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    ScrollView {
                        Text(logText.isEmpty ? "Console ready — type help for commands." : logText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .id("bottom")
                            .onChange(of: logText) { _ in
                                if scrollState.autoScroll { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                    }
                    .background(Color.black.opacity(0.85))
                    HStack(spacing: 8) {
                        Text(">").font(.system(.body, design: .monospaced)).foregroundColor(.white)
                        TextField("Type a command (help for list)", text: $input)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { submit() }
                        Button("Send") { submit() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.9))
                }
                .frame(height: UIScreen.main.bounds.height * 0.55, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .onReceive(pollTick) { _ in poll() }
        .onAppear { poll() }
    }

    func poll() {
        // Auto-scroll off means frozen: the tail keeps rolling on the
        // Rust side (new lines every second from the RAM tracker), and
        // replacing logText would push the top lines out of view, so
        // the panel would look like it was still scrolling even though
        // the scroll offset never moved. Skip the update entirely;
        // turning auto-scroll back on resumes it on the next tick.
        if !scrollState.autoScroll { return }
        guard let ptr = muguet_console_tail() else { return }
        let text = String(cString: ptr)
        if text != logText { logText = text }
    }

    func submit() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        input = ""
        cmd.withCString { muguet_console_command($0) }
        if cmd == "close" { onClose(); return }
        // A typed command wants its answer: resume live view so the
        // output appears at once instead of waiting behind the freeze.
        if !scrollState.autoScroll { scrollState.autoScroll = true }
        poll()
    }
}

@_cdecl("muguet_show_console")
public func muguetShowConsole() {
    DispatchQueue.main.async {
        guard let root = foregroundRootViewController() else { return }
        var presenter = root
        // Do not stack consoles if the button is tapped twice. The
        // old check only looked at the topmost controller, so a menu
        // alert sitting on top of the console let a second one in.
        while let child = presenter.presentedViewController {
            if child is UIHostingController<ConsoleView> { return }
            presenter = child
        }
        if presenter is UIHostingController<ConsoleView> { return }
        weak var host: UIHostingController<ConsoleView>?
        let view = ConsoleView(onClose: { host?.dismiss(animated: true) })
        let hc = UIHostingController(rootView: view)
        host = hc
        hc.modalPresentationStyle = .overFullScreen
        hc.view.backgroundColor = .clear
        presenter.present(hc, animated: true)
    }
}

@_cdecl("muguet_quit_to_launcher")
public func muguetQuitToLauncher() {
    // Console "quit": same as the in-game menu's Quit button.
    // Apple treats exit(0) as a crash, so suspend instead.
    DispatchQueue.main.async {
        suspendApp()
    }
}

func resetGraphicsSettings() {
    let folder = configURL.deletingLastPathComponent().appendingPathComponent("saves")
    let fm = FileManager.default
    if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) {
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "settings.xml" {
                try? fm.removeItem(at: fileURL)
            }
        }
    }
    _ = muguet_reset_game_settings()
    muguet_reload_settings()
}

func shareDiagnostics() {
    let folder = configURL.deletingLastPathComponent()
    let logs = ["muguet-previous.log", "muguet-runtime.log", "muguet-crash.log", "muguet-debug.log"].map { folder.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard let root = foregroundRootViewController() else { return }
    var presenter = root
    while let child = presenter.presentedViewController { presenter = child }
    // Sharing used to silently do nothing when there were no logs.
    if logs.isEmpty {
        let alert = UIAlertController(title: "No logs", message: "There are no diagnostics logs to share yet.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        presenter.present(alert, animated: true)
        return
    }
    let sheet = UIActivityViewController(activityItems: logs, applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(sheet, animated: true)
}

func shareSaves() {
    let folder = configURL.deletingLastPathComponent().appendingPathComponent("saves")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let root = foregroundRootViewController() else { return }
    var presenter = root
    while let child = presenter.presentedViewController { presenter = child }
    let sheet = UIActivityViewController(activityItems: [folder], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(sheet, animated: true)
}

func localIPs() -> [String] {
    var out: [String] = []
    var ifs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifs) == 0, let first = ifs else { return ["?"] }
    defer { freeifaddrs(ifs) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") && !out.contains(ip) { out.append(ip) }
        }
    }
    return out.isEmpty ? ["?"] : out
}

@_cdecl("muguet_show_launcher")
public func muguetShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) {
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    weak var sheet: UIViewController?
    let host = UIHostingController(rootView: LauncherView(isOverlay: false, play: {
        if let sheet {
            sheet.dismiss(animated: true, completion: { done() })
        } else {
            done()
        }
    }))
    sheet = host
    host.modalPresentationStyle = .fullScreen
    host.isModalInPresentation = true
    parent.present(host, animated: false)
}
