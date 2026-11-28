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
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
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
                Text(title).foregroundColor(.white)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color(hex: "7EE787") : Color.white.opacity(0.18))
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
// is white with dark text, unselected is white 0.1 fill.
struct CLChipPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(String, Value)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options.indices, id: \.self) { i in
                        let option = options[i]
                        Button { selection = option.1 } label: {
                            Text(option.0)
                                .font(.system(size: 14, weight: selection == option.1 ? .bold : .regular))
                                .foregroundColor(selection == option.1 ? Color(hex: "0B0D12") : .white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Capsule().fill(selection == option.1 ? Color.white : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
struct CLPresetButtons: View {
    @ObservedObject var s: Settings
    @Binding var resetAlertMessage: String
    @Binding var showingResetAlert: Bool
    var body: some View {
        HStack(spacing: 8) {
            CLCapsuleButton(title: "120 FPS", icon: "bolt.fill") {
                s.apply120FpsBoost()
                resetAlertMessage = "120 FPS Super Smooth setup enabled!"
                showingResetAlert = true
            }
            CLCapsuleButton(title: "Save RAM", icon: "leaf.fill") {
                s.applyLowRamMode()
                resetAlertMessage = "Super RAM Saver setup enabled (~800MB)!"
                showingResetAlert = true
            }
            CLCapsuleButton(title: "Ultra Low", icon: "arrow.down.to.line", fill: Color.orange, textColor: .white) {
                s.applyUltraLowMode()
                resetAlertMessage = "Ultra Low setup enabled — shadows & reflections off, 25% resolution!"
                showingResetAlert = true
            }
        }
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
    var onCancel: () -> Void
    var onInstall: () -> Void

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
    }
}

struct CLSettingsPanel: View {
    let screenWidth: CGFloat
    @ObservedObject var s: Settings
    @Binding var showingCheatSheet: Bool
    @Binding var showingHUDEditor: Bool
    @Binding var showingResetAlert: Bool
    @Binding var resetAlertMessage: String
    @Binding var newVehicleCode: String
    var onClose: () -> Void

    // Mods manager state. The installed list is read from disk, never
    // stored: the folders under dlcPacks are the truth.
    @State private var installedMods: [ModEntry] = []
    @State private var pickingMod = false
    @State private var modNameSheetURL: URL?
    @State private var showingModNameSheet = false
    @State private var modNameText = ""
    @State private var modModelText = ""
    @State private var modToDelete: String?
    @State private var modsStatus = ""
    @State private var modsWorking = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                CLPanelHeader(title: "Settings", onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CLSection("Character") {
                            CLDarkField(label: "Character name", text: $s.name, placeholder: "Enter a character name...", autocapitalization: .words)
                            Text("This name will show above your character's head when you play with friends.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        }

                        if !s.multiplayer {
                            CLSection("Mode") {
                                CLChipPicker(label: "Mode", selection: $s.mode, options: [
                                    ("Story Mode", 1),
                                    ("Sandbox (Free Roam)", 2)
                                ])
                            }
                        }

                        CLSection("Graphics Settings & Enable 120 FPS") {
                            CLPresetButtons(s: s, resetAlertMessage: $resetAlertMessage, showingResetAlert: $showingResetAlert)
                            CLChipPicker(label: "Frame rate (Frame Limit)", selection: $s.fps, options: [
                                ("30 fps (Save battery)", 30),
                                ("60 fps (Default)", 60),
                                ("120 fps (Unlock 120 FPS / ProMotion)", 120)
                            ])
                            CLChipPicker(label: "Resolution", selection: $s.scale, options: [
                                ("25% (Ultra low)", 0.25),
                                ("35% (Super light)", 0.35),
                                ("50% (Recommended for 120 FPS)", 0.5),
                                ("65% (Balanced)", 0.65),
                                ("75% (Sharp)", 0.75),
                                ("100% (Native resolution)", 1.0)
                            ])
                            CLChipPicker(label: "Texture Quality", selection: $s.textures, options: [
                                ("Normal / Low (Uses less RAM)", 0),
                                ("Cao", 1),
                                ("Very High", 2)
                            ])
                            CLToggle(title: "Lock ProMotion V-Sync 120Hz pacing (CADisplayLink)", isOn: $s.promotionSync)
                            Text("Syncs precisely with your iPhone/iPad screen's 60Hz/120Hz refresh rate to remove stutter and keep 120 FPS as smooth as possible.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            CLToggle(title: "Deep graphics optimization (Deep Optimization 60-120 FPS Boost)", isOn: $s.deepOptimization)
                            Text("Automatically limits shadows, dense grass, and anti-aliasing in GTA V settings.xml to hold max FPS when the device heats up.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            Button(action: {
                                resetGraphicsSettings()
                                s.scale = 0.5
                                s.textures = 0
                                s.fps = 120
                                s.shadowQuality = 1
                                s.shadowDistance = 1.0
                                s.reflectionQuality = 1
                                s.grassQuality = 0
                                s.waterQuality = 0
                                s.particleQuality = 0
                                s.postFx = 0
                                s.anisotropicFiltering = 0
                                s.fxaa = true
                                s.cityDensity = 0.5
                                s.pedDensity = 0.5
                                s.distanceScaling = 0.0
                                s.deepOptimization = true
                                s.ultraLow = false
                                s.promotionSync = true
                                try? s.save()
                                muguet_reload_settings()
                                resetAlertMessage = "Restored Rockstar GTA V graphics to safe defaults (Shader High, MSAA Off, Shadows Normal, 120 FPS). The black screen caused by Max Settings is fully fixed!"
                                showingResetAlert = true
                            }) {
                                Label("Restore original graphics (Fix black screen)", systemImage: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }

                        CLSection("Detailed GTA V Graphics Settings (In-Game Graphics)") {
                            Text("Set GTA V graphics options right here without changing them in-game.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            CLChipPicker(label: "Shadow Quality", selection: $s.shadowQuality, options: [
                                ("Off (No shadows)", 0),
                                ("Normal (Smoothest)", 1),
                                ("Cao", 2),
                                ("Very High", 3)
                            ])
                            CLChipPicker(label: "Shadow Distance", selection: $s.shadowDistance, options: [
                                ("Short (0.5× - Save RAM)", 0.5),
                                ("Standard (1.0×)", 1.0),
                                ("Xa (1.5×)", 1.5)
                            ])
                            CLChipPicker(label: "Reflection Quality", selection: $s.reflectionQuality, options: [
                                ("Off (No reflections)", 0),
                                ("Normal", 1),
                                ("Cao", 2),
                                ("Very High", 3)
                            ])
                            CLChipPicker(label: "Grass & Vegetation Quality", selection: $s.grassQuality, options: [
                                ("Normal (Prevents FPS drops in hills)", 0),
                                ("Cao", 1),
                                ("Very High", 2)
                            ])
                            CLChipPicker(label: "Water Quality", selection: $s.waterQuality, options: [
                                ("Normal", 0),
                                ("Cao", 1),
                                ("Very High", 2)
                            ])
                            CLChipPicker(label: "Particle & Explosion Effect Quality", selection: $s.particleQuality, options: [
                                ("Normal", 0),
                                ("Cao", 1),
                                ("Very High", 2)
                            ])
                            CLChipPicker(label: "Post FX & Lighting", selection: $s.postFx, options: [
                                ("Normal (Best FPS)", 0),
                                ("High (Bloom & Sun rays)", 1),
                                ("Very High", 2)
                            ])
                            CLChipPicker(label: "Surface Detail Filtering (Anisotropic Filtering)", selection: $s.anisotropicFiltering, options: [
                                ("Off (x0)", 0),
                                ("x4", 4),
                                ("x8", 8),
                                ("x16 (Sharp road detail)", 16)
                            ])
                            CLToggle(title: "Edge anti-aliasing (FXAA)", isOn: $s.fxaa)
                            CLChipPicker(label: "Traffic Density", selection: $s.cityDensity, options: [
                                ("Empty (0% - Smoothest)", 0.0),
                                ("Medium (50%)", 0.5),
                                ("Heavy (100% - Like PC)", 1.0)
                            ])
                            CLChipPicker(label: "Pedestrian Density & Variety", selection: $s.pedDensity, options: [
                                ("Low (0% - Save RAM)", 0.0),
                                ("Medium (50%)", 0.5),
                                ("Heavy (100%)", 1.0)
                            ])
                            CLChipPicker(label: "Draw Distance & Object Detail (LOD Scale)", selection: $s.distanceScaling, options: [
                                ("Save RAM (-0.5)", -0.5),
                                ("Standard (0.0)", 0.0),
                                ("Far view (+0.5)", 0.5)
                            ])
                        }

                        CLSection("Controls") {
                            Button(action: { showingHUDEditor = true }) {
                                Label("Adjust button position & size visually (HUD Editor)", systemImage: "hand.draw.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(Color.white))
                                    .foregroundColor(Color(hex: "0B0D12"))
                            }
                            .buttonStyle(.plain)
                            Button("Reset buttons to default") {
                                s.resetLayout()
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                            HStack {
                                Text("Look sensitivity").foregroundColor(.white)
                                Slider(value: $s.touch, in: 0.25...6.0, step: 0.25).tint(.white)
                                Text(String(format: "%.2f×", s.touch)).monospacedDigit().frame(width: 55, alignment: .trailing).foregroundColor(.white)
                            }
                            HStack {
                                Text("Gamepad sensitivity").foregroundColor(.white)
                                Slider(value: $s.padSensitivity, in: 0.25...4.0, step: 0.25).tint(.white)
                                Text(String(format: "%.2f×", s.padSensitivity)).monospacedDigit().frame(width: 55, alignment: .trailing).foregroundColor(.white)
                            }
                            CLChipPicker(label: "Aim button", selection: $s.aimMode, options: [
                                ("Tap to toggle", "toggle"),
                                ("Hold to aim", "hold")
                            ])
                            CLToggle(title: "Aim while firing", isOn: $s.fireAim)
                            HStack {
                                Text("Aim sensitivity").foregroundColor(.white)
                                Slider(value: $s.aimSensitivity, in: 0.1...3.0, step: 0.1).tint(.white)
                                Text(String(format: "%.2f×", s.aimSensitivity)).monospacedDigit().frame(width: 55, alignment: .trailing).foregroundColor(.white)
                            }
                            Text("Drag on the right FIRE button to adjust aim while shooting. The left FIRE button frees your right thumb to aim.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            CLToggle(title: "Mute audio", isOn: $s.mute)
                        }

                        CLSection("Play Online (Multiplayer)") {
                            CLToggle(title: "Enable Multiplayer mode", isOn: $s.multiplayer)
                            if s.multiplayer {
                                CLChipPicker(label: "Room mode", selection: $s.roomMode, options: [
                                    ("Create room", "create"),
                                    ("Join room", "join"),
                                    ("Public", "public"),
                                    ("LAN Host", "lan")
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
                                        Text("AWS iOSVN Singapore server (Ping ~40ms, Supports 32 / 64 players)")
                                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                                    }
                                }
                                .foregroundColor(.white)
                            }
                        }

                        if !s.multiplayer {
                            CLSection("GTA V Cheat Codes (Offline only)") {
                                Button(action: { showingCheatSheet = true }) {
                                    Label("View & Activate Cheat Codes", systemImage: "wand.and.stars")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Capsule().fill(Color.white))
                                        .foregroundColor(Color(hex: "0B0D12"))
                                }
                                .buttonStyle(.plain)
                                Text("Quickly look up and activate cheat codes (invincibility, full weapons, helicopter, race cars...). Cheat codes are auto-locked in Online mode.")
                                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            }
                        }

                        if !s.multiplayer {
                            CLSection("Sandbox Vehicles") {
                                CLToggle(title: "Auto-spawn vehicle in Sandbox", isOn: $s.sandboxAutoSpawn)
                                    .onChange(of: s.sandboxAutoSpawn) { _ in try? s.save() }
                                Text("When on, every Sandbox session starts you inside the first vehicle below. Turn it off if the spawn ever causes trouble — the CAR button and the in-game menu still work.")
                                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                                VStack(spacing: 6) {
                                    ForEach(s.sandboxVehicles, id: \.self) { code in
                                        HStack {
                                            Text(code).font(.body.monospaced()).foregroundColor(.white)
                                            Spacer()
                                            if code == s.sandboxVehicles.first {
                                                Text("starter").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
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
                            }
                        }

                        CLSection("Mods") {
                            Text("Add-on DLC packs (dlc.rpf). Install a mod zip or a bare dlc.rpf and the game will mount it. The game reads the mod list at launch — restart the game after installing or removing a mod.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            if installedMods.isEmpty {
                                Text("No add-on mods installed. The 11 built-in packs are not listed here.")
                                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(installedMods) { mod in
                                        HStack {
                                            Text(mod.name).font(.body.monospaced()).foregroundColor(.white)
                                            Spacer()
                                            if !mod.size.isEmpty {
                                                Text(mod.size).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                                            }
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
                            if modsWorking {
                                ProgressView().tint(.white)
                            }
                            if !modsStatus.isEmpty {
                                Text(modsStatus).font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .onAppear { refreshMods() }

                        CLSection("Save Data") {
                            CLRow(title: "Share / Backup saves") { shareSaves() }
                            Text("In game: save via Phone > Quick Save, or Pause > Game > Save Game. Saves are stored in Files app > On My iPhone > GTA V > saves.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        }

                        CLSection("Diagnostics") {
                            CLRow(title: "Share startup / memory logs") { shareDiagnostics() }
                            Text("After a crash, reopen GTA V and share the previous log. Logs contain connection addresses and runtime errors, not game files.")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: min(screenWidth * 0.92, 600))
            .frame(maxHeight: .infinity)
            .background(Color(hex: "11131B").opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.6), radius: 30, x: -10)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
            .transition(.move(edge: .trailing))
        }
        .environment(\.colorScheme, .dark)
        // The name sheet must wait for the picker to finish dismissing:
        // presenting it in the same turn blacked the screen, because
        // UIKit will not present on a controller that is dismissing.
        // installModFile only stashes the picked URL; onDismiss fires
        // once the picker is gone and the hierarchy is clean again.
        .sheet(isPresented: $pickingMod, onDismiss: {
            // Present on the next runloop turn: even after onDismiss,
            // UIKit can still be settling the picker dismissal, and
            // presenting in the same turn blacked the sheet.
            DispatchQueue.main.async {
                if modNameSheetURL != nil {
                    showingModNameSheet = true
                }
            }
        }) {
            DocumentPicker(isPresented: $pickingMod, contentTypes: [UTType.zip, UTType(tag: "rpf", tagClass: .filenameExtension, conformingTo: .data) ?? UTType.data], onPick: { url in
                installModFile(url)
            }, onError: { message in
                modsStatus = "Could not pick a file: \(message)"
                message.withCString { muguet_debug_log($0) }
            })
        }
        .sheet(isPresented: $showingModNameSheet) {
            if let url = modNameSheetURL {
                ModNameSheet(name: $modNameText, modelName: $modModelText, onCancel: {
                    showingModNameSheet = false
                    modNameSheetURL = nil
                }, onInstall: {
                    let folder = modNameText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let model = modModelText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    showingModNameSheet = false
                    modNameSheetURL = nil
                    runModInstall(url: url, name: folder, modelName: model)
                })
            }
        }
        .alert("Remove mod?", isPresented: Binding(get: { modToDelete != nil }, set: { if !$0 { modToDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let name = modToDelete { removeMod(name) }
                modToDelete = nil
            }
            Button("Cancel", role: .cancel) { modToDelete = nil }
        } message: {
            if let name = modToDelete {
                Text("This deletes the \(name) folder and its line in dlcList.xml. Other mods are not touched.")
            }
        }
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
            // Only stash the URL here — the name sheet is presented
            // from the picker sheet's onDismiss, once the picker
            // has fully gone away (see the sheet above).
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
    private func runModInstall(url: URL, name: String, modelName: String = "") {
        modsWorking = true
        modsStatus = "Installing…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = url.path.withCString { path in
                name.withCString { n in muguet_install_mod(path, n) }
            }
            let installed = muguet_mod_name().map { String(cString: $0) } ?? ""
            let err = muguet_mod_error().map { String(cString: $0) } ?? "Install failed."
            DispatchQueue.main.async {
                modsWorking = false
                if ok, !installed.isEmpty {
                    let vehicleCode = modelName.isEmpty ? installed : modelName
                    if vehicleCode == installed {
                        modsStatus = "Installed \(installed). Restart the game to use it."
                    } else {
                        modsStatus = "Installed \(installed) — spawn it with \(vehicleCode). Restart the game to use it."
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if isOverlay {
                    Color.black.ignoresSafeArea()
                    // Static dark-green glow across the top, GTA V brand green.
                    // No TimelineView animation: the launcher stays still and fast.
                    Circle()
                        .fill(Color(hex: "1F7A33").opacity(0.30))
                        .frame(width: 560, height: 400)
                        .blur(radius: 110)
                        .offset(x: geo.size.width * 0.5 - 280, y: -190)
                } else {
                    // GTA V logo wallpaper, dead-center: the logo is
                    // centered in the 600x400 image (its bright core was
                    // at 42% height, shifted to 50%), so plain fill
                    // centers the logo itself. The explicit geo-sized
                    // frame centers it on the screen and the 1.2x zoom
                    // makes the V big without cropping its arms.
                    Image("BackgroundLosSantos")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.2)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                    // Dark gradient overlay so the white header text, PLAY
                    // button, mode rail, quick rows and credits stay readable.
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.55), location: 0.0),
                            .init(color: Color.black.opacity(0.25), location: 0.5),
                            .init(color: Color.black.opacity(0.75), location: 1.0)
                        ],
                        startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            hero
                            modeRail
                            presetChips
                            quickRows
                            footer
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
                if showingSettings {
                    CLSettingsPanel(screenWidth: geo.size.width, s: s, showingCheatSheet: $showingCheatSheet, showingHUDEditor: $showingHUDEditor, showingResetAlert: $showingResetAlert, resetAlertMessage: $resetAlertMessage, newVehicleCode: $newVehicleCode, onClose: {
                        // Panel edits only reached disk via Play/Continue
                        // before, so closing the panel silently lost
                        // them. Save here; Play still saves again.
                        try? s.save()
                        showingSettings = false
                    })
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: showingSettings)
        // checkStartupError used to run only from importView, so a
        // startup-error file was never shown (or cleared) once the
        // game data was already ready. Check on every appearance.
        .onAppear(perform: checkStartupError)
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
        .alert("Graphics Notice", isPresented: $showingResetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resetAlertMessage)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("GTA V")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .light))
                    .frame(width: 42, height: 42)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hex: "1F7A33"), Color(hex: "0B1E12")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Large light "V" behind the image, so the tile still looks
                // right if the hero icon asset does not resolve.
                Text("V")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.white.opacity(0.85))
                Image("HeroIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
            Text(isOverlay ? "GTA V Menu" : "GTA V")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white)
                .padding(.top, 12)
            Text(statusLine)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.62))
                .padding(.top, 2)
            actionArea
                .padding(.top, 14)
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
                .padding(.horizontal, 34).padding(.vertical, 13)
                .background(Capsule().fill(Color.white))
                .foregroundColor(Color(hex: "0B0D12"))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            Button(action: { suspendApp() }) {
                Text("Quit the app")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        } else {
            if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
            playButton
            Button("Import other game data…") { picking = true }
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // Centered, no scroll: three tiles fit, and the rail sits in the
    // middle of the screen instead of hugging the left edge.
    private var modeRail: some View {
        HStack(alignment: .bottom, spacing: 16) {
            modeTile(title: "Story", subtitle: "Story Mode", icon: "gamecontroller", image: "TileStory", index: 0)
            modeTile(title: "Sandbox", subtitle: "Sandbox · Free Roam", icon: "map", image: "TileSandbox", index: 1)
            modeTile(title: "Online", subtitle: "Online · Multiplayer", icon: "globe", image: "TileOnline", index: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func modeTile(title: String, subtitle: String, icon: String, image: String, index: Int) -> some View {
        let focused = selectedMode == index
        let size: CGFloat = focused ? 172 : 140
        return Button { selectMode(index) } label: {
            ZStack {
                // GTA artwork photo, full-bleed in the tile.
                Image(image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                // Bottom dark gradient so the icon, name and subtitle
                // stay readable over the photo.
                LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .light))
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                // Subtitle strip, only on the focused tile.
                if focused {
                    VStack {
                        Spacer()
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.bottom, 6)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focused ? Color.white : .clear, lineWidth: 3)
                    .padding(2)
            )
            .shadow(color: .black.opacity(focused ? 0.6 : 0.42), radius: focused ? 16 : 7, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: focused)
    }

    private var presetChips: some View {
        CLPresetButtons(s: s, resetAlertMessage: $resetAlertMessage, showingResetAlert: $showingResetAlert)
    }

    private var quickRows: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("Game data").font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                Spacer()
                if importer.ready {
                    Text("Ready").font(.system(size: 14)).foregroundColor(Color(hex: "7EE787"))
                } else {
                    Button("Import") { picking = true }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "0B0D12"))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            CLRow(title: "Player", value: s.name) { showingSettings = true }
            CLRow(title: "Diagnostics", value: "Share logs") { shareDiagnostics() }
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("proudly made by c22dev").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            Text("Rebuild: Pentacampeon").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var importView: some View {
        VStack(spacing: 12) {
            if let p = importer.progress {
                ProgressView(value: p)
                Text("Importing… \(Int(p * 100)) %").font(.callout).monospacedDigit()
            } else {
                Button("Import game data .zip") { picking = true }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 5) {
                    Text("💡 Quick install guide using the Files app:")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text("1. Unzip the zip file with the data on your computer or in the Files app.\n2. Open the Files app > On My iPhone/iPad > GTA V.\n3. Create a folder named 'game' (lowercase).\n4. Paste the 2 folders 'data' and 'b' inside the 'game' folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Divider().padding(.vertical, 2)
                    Text("📦 Storage note: The full game takes ~21 GB. If you unzip directly on iPhone/iPad you need at least 42 GB free (21 GB zip + 21 GB unzipped; after finishing, delete the zip and it goes back to 21 GB). Unzipping on your computer first and copying it over only uses 21 GB on the device.")
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

    // The Rust engine writes Documents/muguet-startup-error.txt when
    // config fails before the game window exists (main.rs); the app
    // then exits, so surface it here on the next launch instead of
    // leaving the user with a silent quit. Deleted after one show.
    private func checkStartupError() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("muguet-startup-error.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return }
        error = text
        try? FileManager.default.removeItem(at: url)
    }

    @ViewBuilder var playButton: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 13))
                Text("Play").font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 34).padding(.vertical, 13)
            .background(Capsule().fill(Color.white))
            .foregroundColor(Color(hex: "0B0D12"))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    func resumeAndSave() {
        do { try s.save() } catch {}
        s.applyCustomLayout()
        play()
        muguet_reload_settings()
    }

    func start() {
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
// lowram, ultralow, dv, tpm, quit, help, clear, close — see help in
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
