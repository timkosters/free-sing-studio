import SwiftUI
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User preferences. Backed by UserDefaults so they survive relaunches and are cheap to read.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var followPitch: Bool { didSet { defaults.set(followPitch, forKey: "followPitch") } }
    var metronome: Bool { didSet { defaults.set(metronome, forKey: "metronome") } }
    var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: "keepAwake") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "haptics") } }
    var reminderEnabled: Bool { didSet { defaults.set(reminderEnabled, forKey: "reminderEnabled") } }
    var reminderMinuteOfDay: Int { didSet { defaults.set(reminderMinuteOfDay, forKey: "reminderMinute") } }
    var dailyRoutine: String { didSet { defaults.set(dailyRoutine, forKey: "dailyRoutine") } }
    var warmupDrill: String { didSet { defaults.set(warmupDrill, forKey: "warmupDrill") } }
    var warmupRoot: Int { didSet { defaults.set(warmupRoot, forKey: "warmupRoot") } }
    var warmupSteps: Int { didSet { defaults.set(warmupSteps, forKey: "warmupSteps") } }
    var warmupBpm: Double { didSet { defaults.set(warmupBpm, forKey: "warmupBpm") } }
    var questLow: Int { didSet { defaults.set(questLow, forKey: "questLow") } }
    var questHigh: Int { didSet { defaults.set(questHigh, forKey: "questHigh") } }
    var questCount: Int { didSet { defaults.set(questCount, forKey: "questCount") } }

    init() {
        let d = UserDefaults.standard
        onboarded = d.bool(forKey: "onboarded")
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        followPitch = d.object(forKey: "followPitch") as? Bool ?? true
        metronome = d.object(forKey: "metronome") as? Bool ?? true
        keepAwake = d.object(forKey: "keepAwake") as? Bool ?? true
        hapticsEnabled = d.object(forKey: "haptics") as? Bool ?? true
        reminderEnabled = d.bool(forKey: "reminderEnabled")
        reminderMinuteOfDay = d.object(forKey: "reminderMinute") as? Int ?? 18 * 60
        dailyRoutine = d.string(forKey: "dailyRoutine") ?? "quick"
        warmupDrill = d.string(forKey: "warmupDrill") ?? "arpeggio"
        warmupRoot = d.object(forKey: "warmupRoot") as? Int ?? 48
        warmupSteps = d.object(forKey: "warmupSteps") as? Int ?? 4
        warmupBpm = d.object(forKey: "warmupBpm") as? Double ?? 60
        questLow = d.object(forKey: "questLow") as? Int ?? 55
        questHigh = d.object(forKey: "questHigh") as? Int ?? 67
        questCount = d.object(forKey: "questCount") as? Int ?? 8
    }

    var reminderTime: Date {
        get {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = reminderMinuteOfDay / 60
            c.minute = reminderMinuteOfDay % 60
            return Calendar.current.date(from: c) ?? Date()
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderMinuteOfDay = (c.hour ?? 18) * 60 + (c.minute ?? 0)
        }
    }
}
