import MediaControlCore

enum TargetOverlayGlyph: Equatable {
    case speaker
    case muted
    case warning

    var systemName: String {
        switch self {
        case .speaker:
            "speaker.wave.2.fill"
        case .muted:
            "speaker.slash.fill"
        case .warning:
            "xmark.octagon.fill"
        }
    }
}

enum TargetOverlayCaption: Equatable {
    case adjusting
    case percentage(Double)
    case muted
    case unavailable
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
    let caption: TargetOverlayCaption?

    private init(
        isVisible: Bool,
        glyph: TargetOverlayGlyph?,
        level: Double?,
        levelTreatment: TargetOverlayLevelTreatment,
        caption: TargetOverlayCaption?
    ) {
        self.isVisible = isVisible
        self.glyph = glyph
        self.level = level
        self.levelTreatment = levelTreatment
        self.caption = caption
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
                levelTreatment: .none,
                caption: .adjusting
            )
        case let .pendingBaseline(_, value):
            self = Self(
                isVisible: true,
                glyph: .speaker,
                level: Self.boundedLevel(for: value),
                levelTreatment: .pending,
                caption: .adjusting
            )
        case let .confirmed(value), let .rail(_, value):
            self = Self(
                isVisible: true,
                glyph: .speaker,
                level: Self.boundedLevel(for: value),
                levelTreatment: .confirmed,
                caption: .percentage(Self.boundedLevel(for: value))
            )
        case let .muted(value):
            self = Self(
                isVisible: true,
                glyph: .muted,
                level: Self.boundedLevel(for: value),
                levelTreatment: .muted,
                caption: .muted
            )
        case let .failed(value):
            self = Self(
                isVisible: true,
                glyph: .warning,
                level: value.map { Self.boundedLevel(for: $0) },
                levelTreatment: value == nil ? .none : .frozen,
                caption: .unavailable
            )
        }
    }

    private static let hidden = TargetOverlayVisualState(
        isVisible: false,
        glyph: nil,
        level: nil,
        levelTreatment: .none,
        caption: nil
    )

    private static func boundedLevel(for value: MediaTargetPresentationValue) -> Double {
        min(max(value.normalizedLevel, 0), 1)
    }
}
