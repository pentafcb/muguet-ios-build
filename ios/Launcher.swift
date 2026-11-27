// muguet - Launcher.swift
// Constantin Clerc (c22dev) - 0.1

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @Published var name = "Player" + String(Int.random(in: 100...999))
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
        json["player_name"] = nm.isEmpty ? "Player" : nm
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

final class Importer: ObservableObject {
    static let shared = Importer()
    @Published var ready = muguet_game_ready()
    @Published var progress: Double?
    @Published var error: String?
    private var lastProgressTime = 0.0

    func run(_ url: URL) {
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
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.zip], asCopy: true)
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
    var isOverlay: Bool = false
    let play: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(isOverlay ? "GTA V Menu" : "GTA V").font(.largeTitle.weight(.bold))
                if !muguet_has_game_code() {
                    Text("This build has no game code: build it with ./make-ios.sh <game.zip>.")
                        .foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
                } else if !importer.ready || importer.progress != nil {
                    importView
                } else if isOverlay {
                    Button(action: resumeAndSave) {
                        Text("Continue (Resume)").font(.title3.weight(.semibold)).frame(maxWidth: 220)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: { suspendApp() }) {
                        Text("Quit the app (Exit)").font(.callout.weight(.medium)).frame(maxWidth: 220)
                    }
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
                    playButton
                    Button("Import other game data…") { picking = true }.font(.caption)
                }
                Text("proudly made by c22dev").font(.caption).foregroundStyle(.secondary)
                Text("Rebuild: iOSVN").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            Form {
                Section("Character name / Player") {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.blue)
                        TextField("Enter a character name...", text: $s.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    Text("This name will show above your character's head when you play with friends.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !s.multiplayer {
                    Picker("Mode", selection: $s.mode) {
                        Text("Story Mode").tag(1)
                        Text("Sandbox (Free Roam)").tag(2)
                    }
                }

                Section("Graphics Settings & Enable 120 FPS") {
                    HStack(spacing: 10) {
                        Button(action: {
                            s.apply120FpsBoost()
                            resetAlertMessage = "120 FPS Super Smooth setup enabled!"
                            showingResetAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                Text("120 FPS Super Smooth").bold()
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.regular)

                        Button(action: {
                            s.applyLowRamMode()
                            resetAlertMessage = "Super RAM Saver setup enabled (~800MB)!"
                            showingResetAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "leaf.fill")
                                Text("Save RAM").bold()
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .controlSize(.regular)
                    }
                    HStack(spacing: 10) {
                        Button(action: {
                            s.applyUltraLowMode()
                            resetAlertMessage = "Ultra Low setup enabled — shadows & reflections off, 25% resolution!"
                            showingResetAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line")
                                Text("Ultra Low").bold()
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 2)

                    Picker("Frame rate (Frame Limit)", selection: $s.fps) {
                        Text("30 fps (Save battery)").tag(30)
                        Text("60 fps (Default)").tag(60)
                        Text("120 fps (Unlock 120 FPS / ProMotion)").tag(120)
                    }

                    Picker("Resolution", selection: $s.scale) {
                        Text("25% (Ultra low)").tag(0.25)
                        Text("35% (Super light)").tag(0.35)
                        Text("50% (Recommended for 120 FPS)").tag(0.5)
                        Text("65% (Balanced)").tag(0.65)
                        Text("75% (Sharp)").tag(0.75)
                        Text("100% (Native resolution)").tag(1.0)
                    }

                    Picker("Texture Quality", selection: $s.textures) {
                        Text("Normal / Low (Uses less RAM)").tag(0)
                        Text("Cao").tag(1)
                        Text("Very High").tag(2)
                    }

                    Toggle("Lock ProMotion V-Sync 120Hz pacing (CADisplayLink)", isOn: $s.promotionSync)
                    Text("Syncs precisely with your iPhone/iPad screen's 60Hz/120Hz refresh rate to remove stutter and keep 120 FPS as smooth as possible.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Deep graphics optimization (Deep Optimization 60-120 FPS Boost)", isOn: $s.deepOptimization)
                    Text("Automatically limits shadows, dense grass, and anti-aliasing in GTA V settings.xml to hold max FPS when the device heats up.")
                        .font(.caption).foregroundStyle(.secondary)

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
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Section("🎮 Detailed GTA V Graphics Settings (In-Game Graphics)") {
                    Text("Set GTA V graphics options right here without changing them in-game.")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Shadow Quality", selection: $s.shadowQuality) {
                        Text("Off (No shadows)").tag(0)
                        Text("Normal (Smoothest)").tag(1)
                        Text("Cao").tag(2)
                        Text("Very High").tag(3)
                    }

                    Picker("Shadow Distance", selection: $s.shadowDistance) {
                        Text("Short (0.5× - Save RAM)").tag(0.5)
                        Text("Standard (1.0×)").tag(1.0)
                        Text("Xa (1.5×)").tag(1.5)
                    }

                    Picker("Reflection Quality", selection: $s.reflectionQuality) {
                        Text("Off (No reflections)").tag(0)
                        Text("Normal").tag(1)
                        Text("Cao").tag(2)
                        Text("Very High").tag(3)
                    }

                    Picker("Grass & Vegetation Quality", selection: $s.grassQuality) {
                        Text("Normal (Prevents FPS drops in hills)").tag(0)
                        Text("Cao").tag(1)
                        Text("Very High").tag(2)
                    }

                    Picker("Water Quality", selection: $s.waterQuality) {
                        Text("Normal").tag(0)
                        Text("Cao").tag(1)
                        Text("Very High").tag(2)
                    }

                    Picker("Particle & Explosion Effect Quality", selection: $s.particleQuality) {
                        Text("Normal").tag(0)
                        Text("Cao").tag(1)
                        Text("Very High").tag(2)
                    }

                    Picker("Post FX & Lighting", selection: $s.postFx) {
                        Text("Normal (Best FPS)").tag(0)
                        Text("High (Bloom & Sun rays)").tag(1)
                        Text("Very High").tag(2)
                    }

                    Picker("Surface Detail Filtering (Anisotropic Filtering)", selection: $s.anisotropicFiltering) {
                        Text("Off (x0)").tag(0)
                        Text("x4").tag(4)
                        Text("x8").tag(8)
                        Text("x16 (Sharp road detail)").tag(16)
                    }

                    Toggle("Edge anti-aliasing (FXAA)", isOn: $s.fxaa)

                    Picker("Traffic Density", selection: $s.cityDensity) {
                        Text("Empty (0% - Smoothest)").tag(0.0)
                        Text("Medium (50%)").tag(0.5)
                        Text("Heavy (100% - Like PC)").tag(1.0)
                    }

                    Picker("Pedestrian Density & Variety", selection: $s.pedDensity) {
                        Text("Low (0% - Save RAM)").tag(0.0)
                        Text("Medium (50%)").tag(0.5)
                        Text("Heavy (100%)").tag(1.0)
                    }

                    Picker("Draw Distance & Object Detail (LOD Scale)", selection: $s.distanceScaling) {
                        Text("Save RAM (-0.5)").tag(-0.5)
                        Text("Standard (0.0)").tag(0.0)
                        Text("Far view (+0.5)").tag(0.5)
                    }
                }

                Section("Customize Button Layout (Touch Controls)") {
                    Button(action: { showingHUDEditor = true }) {
                        Label("Adjust button position & size visually (HUD Editor)", systemImage: "hand.draw.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button("Reset buttons to default") {
                        s.resetLayout()
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack {
                    Text("Look sensitivity")
                    Slider(value: $s.touch, in: 0.25...6.0, step: 0.25)
                    Text(String(format: "%.2f×", s.touch)).monospacedDigit().frame(width: 55, alignment: .trailing)
                }
                HStack {
                    Text("Gamepad sensitivity")
                    Slider(value: $s.padSensitivity, in: 0.25...4.0, step: 0.25)
                    Text(String(format: "%.2f×", s.padSensitivity)).monospacedDigit().frame(width: 55, alignment: .trailing)
                }
                Section("Aiming") {
                    Picker("Aim button", selection: $s.aimMode) {
                        Text("Tap to toggle").tag("toggle")
                        Text("Hold to aim").tag("hold")
                    }
                    Toggle("Aim while firing", isOn: $s.fireAim)
                    HStack {
                        Text("Aim sensitivity")
                        Slider(value: $s.aimSensitivity, in: 0.1...3.0, step: 0.1)
                        Text(String(format: "%.2f×", s.aimSensitivity)).monospacedDigit().frame(width: 55, alignment: .trailing)
                    }
                    Text("Drag on the right FIRE button to adjust aim while shooting. The left FIRE button frees your right thumb to aim.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Mute audio", isOn: $s.mute)

                Section("Play Online (Multiplayer)") {
                    Toggle("Enable Multiplayer mode", isOn: $s.multiplayer)
                    if s.multiplayer {
                        Picker("Room mode", selection: $s.roomMode) {
                            Text("Create room").tag("create")
                            Text("Join room").tag("join")
                            Text("Public").tag("public")
                            Text("LAN Host").tag("lan")
                        }
                        .pickerStyle(.segmented)

                        if s.roomMode == "create" {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Pick a room mode:").font(.subheadline.bold())
                                    Picker("Mode", selection: $s.mode) {
                                        Text("Story Mode").tag(1)
                                        Text("Sandbox (Free Roam)").tag(2)
                                    }
                                    .pickerStyle(.segmented)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("2. Damage rules (PvP):").font(.subheadline.bold())
                                    Picker("PvP", selection: $s.pvp) {
                                        Text("🛡️ Peaceful (Co-op)").tag(false)
                                        Text("⚔️ Arena (PvP)").tag(true)
                                    }
                                    .pickerStyle(.segmented)
                                    Text(s.pvp ? "PvP On: Players can shoot and kill each other." : "Peaceful: No damage to each other, no spawn killing.")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("3. Max players (Server capacity):").font(.subheadline.bold())
                                    Picker("Player limit", selection: $s.maxPlayers) {
                                        Text("32 players").tag(32)
                                        Text("64 players").tag(64)
                                    }
                                    .pickerStyle(.segmented)
                                    Text("Creating a room supports up to \(s.maxPlayers) players online at the same time.")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("4. Room code to share with friends:").font(.subheadline.bold())
                                    HStack(spacing: 8) {
                                        Text(s.formattedCreateCode)
                                            .font(.title2.monospaced().bold())
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green.opacity(0.15))
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
                                }

                                HStack(spacing: 8) {
                                    Label(s.mode == 1 ? "Story Mode" : "Sandbox", systemImage: "gamecontroller")
                                        .font(.caption.bold())
                                        .foregroundStyle(s.mode == 1 ? .orange : .cyan)
                                    Text("•")
                                    Label(s.pvp ? "PvP On" : "Peaceful Co-op", systemImage: s.pvp ? "burst.fill" : "shield.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(s.pvp ? .red : .green)
                                    Text("•")
                                    Label(s.roomPass.isEmpty ? "Open Room" : "Has Password", systemImage: s.roomPass.isEmpty ? "lock.open" : "lock")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else if s.roomMode == "join" {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enter room code:").font(.subheadline.bold())
                                    TextField("Example: SP-8621 or BX-5520", text: $s.joinCode)
                                        .font(.title3.monospaced().bold())
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .onChange(of: s.joinCode) { val in
                                            s.parseJoinCode(val)
                                        }
                                }

                                let clean = s.joinCode.trimmingCharacters(in: .whitespaces).uppercased()
                                if !clean.isEmpty {
                                    HStack(spacing: 8) {
                                        Label(s.mode == 1 ? "Story Mode" : "Sandbox", systemImage: "gamecontroller")
                                            .font(.caption.bold())
                                            .foregroundStyle(s.mode == 1 ? .orange : .cyan)
                                        Text("•")
                                        Label(s.pvp ? "PvP On" : "Peaceful Co-op", systemImage: s.pvp ? "burst.fill" : "shield.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(s.pvp ? .red : .green)
                                        Spacer()
                                        Text("Auto-synced")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Text("Game mode (Story / Sandbox) and PvP rules auto-sync to the host's room code.")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }

                                HStack {
                                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                    TextField("Room password (if the host set one)", text: $s.roomPass)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }

                                Text("Note: PvP damage rules and game mode follow the host completely, you can't change them yourself.")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        } else if s.roomMode == "public" {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Public region", selection: $s.mode) {
                                    Text("Story Mode Public").tag(1)
                                    Text("Sandbox Public").tag(2)
                                }
                                .pickerStyle(.segmented)

                                HStack {
                                    Image(systemName: "globe.americas.fill").foregroundStyle(.green)
                                    Text("Public shared lobby (Supports 32 / 64 players per room)")
                                        .fontWeight(.medium)
                                }
                                Text("Auto-connects to the shared lobby with players online on the AWS iOSVN server. Peaceful mode is on by default.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("LAN Mode", selection: $s.mode) {
                                    Text("Story Mode").tag(1)
                                    Text("Sandbox").tag(2)
                                }
                                .pickerStyle(.segmented)
                                Text("Host a room on Wi-Fi (Up to \(s.maxPlayers) players): Connect via: \(localIPs().joined(separator: " or "))")
                                    .font(.callout).textSelection(.enabled)
                            }
                        }

                        DisclosureGroup("Server (Advanced)") {
                            HStack {
                                Text("Server IP:")
                                TextField("18.143.103.253", text: $s.server)
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("AWS iOSVN Singapore server (Ping ~40ms, Supports 32 / 64 players)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !s.multiplayer {
                    Section("GTA V Cheat Codes (Offline only)") {
                        Button(action: { showingCheatSheet = true }) {
                            Label("View & Activate Cheat Codes", systemImage: "wand.and.stars")
                        }
                        Text("Quickly look up and activate cheat codes (invincibility, full weapons, helicopter, race cars...). Cheat codes are auto-locked in Online mode.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !s.multiplayer {
                    Section("Sandbox Vehicles") {
                        Toggle("Auto-spawn vehicle in Sandbox", isOn: $s.sandboxAutoSpawn)
                            .onChange(of: s.sandboxAutoSpawn) { _ in try? s.save() }
                        Text("When on, every Sandbox session starts you inside the first vehicle below. Turn it off if the spawn ever causes trouble — the CAR button and the in-game menu still work.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(s.sandboxVehicles, id: \.self) { code in
                            HStack {
                                Text(code).font(.body.monospaced())
                                Spacer()
                                if code == s.sandboxVehicles.first {
                                    Text("starter").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            s.sandboxVehicles.remove(atOffsets: idx)
                            try? s.save()
                        }
                        HStack {
                            TextField("Add a vehicle code (e.g. loweyezv)", text: $newVehicleCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") {
                                let c = newVehicleCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                guard !c.isEmpty, !s.sandboxVehicles.contains(c) else { return }
                                s.sandboxVehicles.append(c)
                                newVehicleCode = ""
                                try? s.save()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newVehicleCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                Section("Save Data") {
                    Button("Share / Backup saves") { shareSaves() }
                    Text("In game: save via Phone > Quick Save, or Pause > Game > Save Game. Saves are stored in Files app > On My iPhone > GTA V > saves.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    Button("Share startup / memory logs") { shareDiagnostics() }
                    Text("After a crash, reopen GTA V and share the previous log. Logs contain connection addresses and runtime errors, not game files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
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
        let button = Button(action: start) {
            Text("Play").font(.title3.weight(.semibold)).frame(maxWidth: 220)
        }
        .controlSize(.large)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
        #else
        button.buttonStyle(.borderedProminent)
        #endif
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
            s.name = "Player" + String(Int.random(in: 100...999))
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
        while let child = presenter.presentedViewController { presenter = child }

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
