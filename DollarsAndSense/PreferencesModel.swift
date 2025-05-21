import Foundation
import Combine

class AppPreferencesModel: ObservableObject {
    @Published var estimatedCost: Double = 0.0
    @Published var testMode: Bool = false
    @Published var showSuggestedColumn: Bool = true
    @Published var showSourceColumn: Bool = true
}
