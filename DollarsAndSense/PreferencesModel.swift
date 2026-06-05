import Foundation
import Combine

enum ImportCategorizationMode: String, CaseIterable, Identifiable {
    case openAIReliable
    case openAIBudget
    case openAIFast
    case openAIHighAccuracy
    case openAIHybrid
    case claudeFast
    case claudeHighAccuracy
    case claudeHybrid
    case claudeOpus

    static var allCases: [ImportCategorizationMode] {
        [
            .openAIReliable,
            .openAIBudget,
            .openAIFast,
            .openAIHighAccuracy,
            .openAIHybrid,
            .claudeHighAccuracy
        ]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIReliable:
            return "OpenAI Reliable"
        case .openAIBudget:
            return "OpenAI Budget"
        case .openAIFast:
            return "OpenAI GPT-5 Fast"
        case .openAIHighAccuracy:
            return "OpenAI GPT-5 Higher Accuracy"
        case .openAIHybrid:
            return "OpenAI GPT-5 Hybrid"
        case .claudeFast:
            return "Claude Sonnet 4"
        case .claudeHighAccuracy:
            return "Claude Sonnet"
        case .claudeHybrid:
            return "Claude Sonnet"
        case .claudeOpus:
            return "Claude Opus"
        }
    }

    var modelSummary: String {
        switch self {
        case .openAIReliable:
            return "gpt-4.1-mini"
        case .openAIBudget:
            return "gpt-4.1-nano"
        case .openAIFast:
            return "gpt-5-nano"
        case .openAIHighAccuracy:
            return "gpt-5-mini"
        case .openAIHybrid:
            return "gpt-5-nano then gpt-5-mini"
        case .claudeFast:
            return "Sonnet 4"
        case .claudeHighAccuracy:
            return "claude-sonnet-4-6"
        case .claudeHybrid:
            return "claude-sonnet-4-6"
        case .claudeOpus:
            return "claude-opus-4-8"
        }
    }

    var pickerLabel: String {
        "\(displayName) (\(modelSummary))"
    }

    var isOpenAI: Bool {
        switch self {
        case .openAIReliable, .openAIBudget, .openAIFast, .openAIHighAccuracy, .openAIHybrid:
            return true
        case .claudeFast, .claudeHighAccuracy, .claudeHybrid, .claudeOpus:
            return false
        }
    }
}

class AppPreferencesModel: ObservableObject {
    private let selectedImportModeKey = "SelectedImportCategorizationMode"
    private let askForModelOnImportKey = "AskForModelOnImport"
    private let testModeKeychainAccount = "TestMode"

    @Published var estimatedCost: Double = 0.0
    @Published var testMode: Bool {
        didSet {
            KeychainHelper.shared.save(testMode ? "true" : "false", service: "DollarsAndSense", account: testModeKeychainAccount)
        }
    }
    @Published var showSuggestedColumn: Bool = true
    @Published var showSourceColumn: Bool = true
    @Published var selectedImportMode: ImportCategorizationMode {
        didSet {
            UserDefaults.standard.set(selectedImportMode.rawValue, forKey: selectedImportModeKey)
        }
    }
    @Published var askForModelOnImport: Bool {
        didSet {
            UserDefaults.standard.set(askForModelOnImport, forKey: askForModelOnImportKey)
        }
    }

    init() {
        let savedTestMode = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: testModeKeychainAccount) == "true"
        testMode = savedTestMode

        let savedModeRaw = UserDefaults.standard.string(forKey: selectedImportModeKey)
        let savedMode = savedModeRaw.flatMap(ImportCategorizationMode.init(rawValue:)) ?? .openAIReliable
        switch savedMode {
        case .claudeFast, .claudeHybrid, .claudeOpus:
            selectedImportMode = .claudeHighAccuracy
        default:
            selectedImportMode = savedMode
        }

        if UserDefaults.standard.object(forKey: askForModelOnImportKey) == nil {
            askForModelOnImport = true
        } else {
            askForModelOnImport = UserDefaults.standard.bool(forKey: askForModelOnImportKey)
        }
    }
}
