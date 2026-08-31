import MediaControlCore

enum TargetOverlayGlyph: Equatable {
    case speaker
    case speakerLow
    case speakerMedium
    case speakerHigh
    case muted
    case warning

    var systemName: String {
        switch self {
        case .speaker:
            "speaker.fill"
        case .speakerLow:
            "speaker.wave.1.fill"
        case .speakerMedium:
            "speaker.wave.2.fill"
        case .speakerHigh:
            "speaker.wave.3.fill"
        case .muted:
            "speaker.slash.fill"
        case .warning:
            "xmark.octagon.fill"
        }
    }
}

enum TargetOverlayLevelTreatment: Equatable {
    case none
    case confirmed
    case pending
    case muted
    case frozen
}

struct TargetOverlayVisualState: Equatable {
    let isVisible: Bool
    let glyph: TargetOverlayGlyph?
    let level: Double?
    let levelTreatment: TargetOverlayLevelTreatment

    private init(
        isVisible: Bool,
        glyph: TargetOverlayGlyph?,
        level: Double?,
        levelTreatment: TargetOverlayLevelTreatment
    ) {
        self.isVisible = isVisible
        self.glyph = glyph
        self.level = level
        self.levelTreatment = levelTreatment
    }

    init(presentationState: MediaTargetPresentationState) {
        switch presentationState {
        case .hidden, .suspended, .routeLost:
            self = .hidden
        case .pendingCold:
            self = Self(
                isVisible: true,
                glyph: .speaker,
                level: nil,
                levelTreatment: .none
            )
        case let .pendingBaseline(_, value):
            let level = Self.boundedLevel(for: value)
            self = Self(
                isVisible: true,
                glyph: Self.speakerGlyph(for: level),
                level: level,
                levelTreatment: .pending
            )
        case let .confirmed(value), let .rail(_, value):
            let level = Self.boundedLevel(for: value)
            self = Self(
                isVisible: true,
                glyph: Self.speakerGlyph(for: level),
                level: level,
                levelTreatment: .confirmed
            )
        case let .muted(value):
            self = Self(
                isVisible: true,
                glyph: .muted,
                level: Self.boundedLevel(for: value),
                levelTreatment: .muted
            )
        case let .failed(value):
            self = Self(
                isVisible: true,
                glyph: .warning,
                level: value.map { Self.boundedLevel(for: $0) },
                levelTreatment: value == nil ? .none : .frozen
            )
        }
    }

    private static let hidden = TargetOverlayVisualState(
        isVisible: false,
        glyph: nil,
        level: nil,
        levelTreatment: .none
    )

    private static func boundedLevel(for value: MediaTargetPresentationValue) -> Double {
        min(max(value.normalizedLevel, 0), 1)
    }

    private static func speakerGlyph(for level: Double) -> TargetOverlayGlyph {
        if level == 0 {
            return .speaker
        }
        if level < 0.34 {
            return .speakerLow
        }
        if level < 0.67 {
            return .speakerMedium
        }
        return .speakerHigh
    }
}
