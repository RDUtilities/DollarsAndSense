

import SwiftUI
import Charts
import SwiftData
import UniformTypeIdentifiers
import Foundation
import SwiftCSV

// MARK: - KeychainHelper for Secure API Key Storage
import Security
class KeychainHelper {
    static let shared = KeychainHelper()

    func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary

        SecItemDelete(query)

        let attributes = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ] as CFDictionary

        SecItemAdd(attributes, nil)
    }

    func retrieve(service: String, account: String) -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(decoding: data, as: UTF8.self)
        }

        return nil
    }
}




enum CategorySource: String, Codable {
    case ai, user, unknown
}

@Model
final class Transaction: Identifiable {
    var id: UUID
    var date: Date
    var details: String
    var amount: Double
    var category: String
    var source: CategorySource
    var categorizedByModel: String?

    init(date: Date, details: String, amount: Double, category: String, source: CategorySource = .unknown, categorizedByModel: String? = nil) {
        self.id = UUID()
        self.date = date
        self.details = details
        self.amount = amount
        self.category = category
        self.source = source
        self.categorizedByModel = categorizedByModel
    }
}


struct SpendingByCategoryChart: View {
    var transactions: [Transaction]
    @Binding var selectedCategory: String?
    @Binding var hoveredCategory: String?
    @Environment(\.colorScheme) private var colorScheme

    private var spendingTransactions: [Transaction] {
        transactions.filter { $0.amount < 0 }
    }

    var categoryTotals: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: spendingTransactions, by: { $0.category })
        return grouped.map { (category, txs) in
            (category, txs.map { abs($0.amount) }.reduce(0, +))
        }
        .sorted { $0.total > $1.total }
    }

    private var overallTotal: Double {
        categoryTotals.map(\.total).reduce(0, +)
    }

    private var activeCategory: String? {
        selectedCategory ?? hoveredCategory
    }

    private var activeItem: (category: String, total: Double)? {
        guard let activeCategory else { return nil }
        return categoryTotals.first(where: { $0.category == activeCategory })
    }

    var body: some View {
        ZStack {
            Chart(content: chartContent)
                .chartLegend(.hidden)
                .frame(width: 300, height: 300)
                .padding(.top, 40)
                .padding(.leading)
                .animation(.easeInOut(duration: 0.22), value: selectedCategory)
                .animation(.easeInOut(duration: 0.12), value: hoveredCategory)

            centerSummaryCard
        }
        .padding()
    }

    private var centerSummaryCard: some View {
        VStack(spacing: 4) {
            if let activeItem {
                let percent = overallTotal > 0 ? (activeItem.total / overallTotal) * 100 : 0
                Text(activeItem.category)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(activeItem.total, format: .currency(code: "USD"))
                    .font(.headline)
                    .fontWeight(.bold)
                Text("\(percent, specifier: "%.1f")% of total")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Total Spend")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(overallTotal, format: .currency(code: "USD"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .frame(width: 145)
        .offset(x: 10, y: 18)
    }

    private func colorForCategory(_ category: String) -> Color {
        let hash = abs(category.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.68, brightness: colorScheme == .dark ? 0.74 : 0.9)
    }

    private func styleForCategory(_ category: String) -> AnyShapeStyle {
        let baseColor = colorForCategory(category)
        let isSelected = selectedCategory == category
        let isHovered = hoveredCategory == category
        let isFocused = isSelected || isHovered

        if selectedCategory != nil && !isSelected {
            return AnyShapeStyle(Color.gray.opacity(0.24))
        }

        if isFocused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [baseColor.opacity(0.98), baseColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(baseColor)
    }

    @ChartContentBuilder
    private func chartContent() -> some ChartContent {
        ForEach(categoryTotals, id: \.category) { item in
            let isSelected = selectedCategory == item.category
            let isHovered = hoveredCategory == item.category
            let isFocused = isSelected || isHovered

            SectorMark(
                angle: .value("Total", item.total),
                innerRadius: .ratio(0.56),
                outerRadius: .ratio(isFocused ? 1.0 : 0.96),
                angularInset: isFocused ? 2.0 : 1.1
            )
            .foregroundStyle(styleForCategory(item.category))
            .opacity(selectedCategory == nil || isSelected ? 1.0 : 0.42)
            .cornerRadius(isFocused ? 3 : 0)
        }
    }
}


struct ContentView: View {
    private enum ImportCategorizationMode {
        case openAIFast
        case openAIHighAccuracy
        case openAIHybrid
        case claudeFast
        case claudeHighAccuracy
        case claudeHybrid
    }
    
    private enum SmartBulkScope: String {
        case visibleRows
        case similarToSelectedRow
    }
    
    private enum SmartBulkSimilarMatchMode: String {
        case exact
        case startsWith
        case contains
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var preferencesModel: AppPreferencesModel
    @State private var transactions: [Transaction] = []
    @State private var selectedCategory: String? = nil
    @State private var showingImporter = false
    @State private var editingTransactionID: UUID? = nil
    // Track new category text input
    @State private var newCategoryText: String = ""
    @State private var hoveredCategory: String? = nil
    @State private var csvDocument: URLDocument? = nil
    @State private var showExporter: Bool = false
    @State private var apiKeyStatus: String = ""
    @State private var storedApiKey: String = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "OpenAIKey") ?? ""
    @State private var storedAnthropicApiKey: String = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "AnthropicKey") ?? ""
    // Removed testMode state; use preferencesModel.testMode instead
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var categorySuggestions: [String: String] = [:]
    @State private var showReCategorizeConfirmation = false
    @FocusState private var isAddingNewCategory: Bool
    // State for add category sheet
    @State private var showingAddCategorySheet = false
    @State private var newCategoryInput = ""
    @State private var transactionPendingNewCategory: Transaction?
    // Import error reporting
    @State private var importErrors: [String] = []
    @State private var showingImportErrorSheet = false
    @State private var pendingImportURL: URL?
    @State private var showingImportModelDialog = false
    @State private var selectedTransactionIDs: Set<UUID> = []
    @State private var showingBulkAddCategorySheet = false
    @State private var bulkNewCategoryInput = ""
    @State private var showingSmartBulkSheet = false
    @State private var smartBulkScope: SmartBulkScope = .visibleRows
    @State private var smartBulkSimilarMatchMode: SmartBulkSimilarMatchMode = .exact
    @State private var smartBulkSimilarMatchText = ""
    @State private var smartBulkSourceCategoryFilter = "__any__"
    @State private var smartBulkTargetCategorySelection = ""
    @State private var smartBulkNewTargetCategoryInput = ""

    private func colorForCategory(_ category: String) -> Color {
        let hash = abs(category.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }

    var transactionRows: some View {
        ForEach(filteredTransactions, id: \.id) { tx in
            transactionRowView(for: tx)
        }
    }

    var transactionList: some View {
        ForEach(filteredTransactions, id: \.id) { tx in
            transactionRowView(for: tx)
        }
    }

    @ViewBuilder
    private func transactionRowView(for tx: Transaction) -> some View {
        HStack {
            Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 100, alignment: .leading)

            detailsTextField(for: tx)
            amountTextField(for: tx)
            categoryPickerOrField(for: tx)

            if preferencesModel.showSuggestedColumn {
                if tx.category == "Uncategorized", let suggestion = categorySuggestions[tx.details] {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 140, alignment: .leading)
                } else {
                    Text("").frame(width: 140, alignment: .leading)
                }
            }

            if preferencesModel.showSourceColumn {
                Text(sourceLabel(for: tx))
                    .font(.caption2)
                    .foregroundColor(tx.source == .ai ? .blue : .gray)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .background(hoveredCategory == tx.category ? colorForCategory(tx.category).opacity(0.1) : Color.clear)
        .transition(.opacity)
    }

    // MARK: - Subviews for transactionRowView
    private func detailsTextField(for tx: Transaction) -> some View {
        TextField("", text: Binding(
            get: { tx.details },
            set: { newValue in
                if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                    transactions[index].details = newValue
                    try? modelContext.save()
                    transactions = Array(transactions)
                }
            }
        ))
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountTextField(for tx: Transaction) -> some View {
        let getAmount: () -> Double = {
            tx.amount
        }
        let setAmount: (Double) -> Void = { newValue in
            if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                transactions[index].amount = newValue
                try? modelContext.save()
                transactions = Array(transactions)
            }
        }
        return TextField("", value: Binding(get: getAmount, set: setAmount), formatter: NumberFormatter.currencyFormatter)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 120, alignment: .trailing)
    }

    private func categoryPickerOrField(for tx: Transaction) -> some View {
        Group {
            if editingTransactionID == tx.id {
                TextField("Enter new category…", text: $newCategoryText, onCommit: {
                    if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                        transactions[index].category = newCategoryText
                        categorySuggestions[transactions[index].details] = newCategoryText
                        try? modelContext.save()
                        transactions = Array(transactions)
                    }
                    editingTransactionID = nil
                    newCategoryText = ""
                })
                .onAppear {
                    newCategoryText = tx.category
                    isAddingNewCategory = true
                }
                .focused($isAddingNewCategory)
                .submitLabel(.done)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 140)
            } else {
                Picker("", selection: Binding(
                    get: { tx.category },
                    set: { newValue in
                        if newValue == "__add_new__" {
                            transactionPendingNewCategory = tx
                            showingAddCategorySheet = true
                        } else {
                            if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                                transactions[index].category = newValue
                                transactions[index].source = .user
                                transactions[index].categorizedByModel = nil
                                categorySuggestions[transactions[index].details] = newValue
                                try? modelContext.save()
                                transactions = Array(transactions)
                            }
                        }
                    }
                )) {
                    ForEach(Array(Set(transactions.map { $0.category })).sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }), id: \.self) { category in
                        Text(category).tag(category)
                    }
                    Text("Add New...").tag("__add_new__")
                }
                .frame(width: 140)
                .pickerStyle(.menu)
            }
        }
    }

    private var searchFilteredTransactions: [Transaction] {
        let searched = searchText.isEmpty ? transactions : transactions.filter {
            let dateString = $0.date.formatted(date: .abbreviated, time: .omitted)
            return $0.details.localizedCaseInsensitiveContains(searchText) ||
                   $0.category.localizedCaseInsensitiveContains(searchText) ||
                   String(format: "%.2f", $0.amount).contains(searchText) ||
                   dateString.localizedCaseInsensitiveContains(searchText)
        }

        return searched.sorted(using: sortOrder)
    }

    var filteredTransactions: [Transaction] {
        let base = searchFilteredTransactions
        let categoryFiltered = selectedCategory == nil
            ? base
            : base.filter { $0.category == selectedCategory }
        return categoryFiltered.sorted(using: sortOrder)
    }

    // Category totals map for use in UI
    private var categoryTotalMap: [String: Double] {
        Dictionary(grouping: transactions.filter { $0.amount < 0 }, by: { $0.category })
            .mapValues { txs in txs.map { abs($0.amount) }.reduce(0, +) }
    }

    @State private var sortOrder: [KeyPathComparator<Transaction>] = [ .init(\.date, order: .reverse) ]

    var body: some View {
        VStack {
            chartSection
            Spacer().frame(height: 8)
            VStack(spacing: 0) {
                // Moved selected category block here
                if let selected = selectedCategory,
                   let total = categoryTotalMap[selected] {
                    HStack(spacing: 10) {
                        Text("Showing: \(selected)")
                            .font(.headline)

                        Text("Total: \(total, format: .currency(code: "USD"))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        let overall = transactions.filter { $0.amount < 0 }.map { abs($0.amount) }.reduce(0, +)
                        let percentage = (overall > 0) ? (total / overall) * 100 : 0
                        Text("(\(percentage, specifier: "%.1f")%)")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Button {
                            selectedCategory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear category selection")
                    }
                    .padding(.bottom, 4)
                }

                // Search Field
                TextField("Search transactions...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isSearchFieldFocused)
                    .overlay(searchFieldOverlay)
                    .padding(.horizontal)

                // Transactions List
                transactionListView

                // Button bar
                transactionControlsBar
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile = try result.get().first else { return }
                pendingImportURL = selectedFile
                showingImportModelDialog = true
            } catch {
                print("Failed to read file: \(error.localizedDescription)")
            }
        }
        .confirmationDialog("Choose AI Model For This Import", isPresented: $showingImportModelDialog, titleVisibility: .visible) {
            Button("OpenAI Fast & Cheap (gpt-5.4-nano)") {
                startImport(using: .openAIFast)
            }
            Button("OpenAI Higher Accuracy (gpt-5.4-mini)") {
                startImport(using: .openAIHighAccuracy)
            }
            Button("OpenAI Hybrid (gpt-5.4-nano then gpt-5.4-mini)") {
                startImport(using: .openAIHybrid)
            }
            Button("Claude Fast (Haiku 3.5)") {
                startImport(using: .claudeFast)
            }
            Button("Claude Higher Accuracy (Sonnet 4)") {
                startImport(using: .claudeHighAccuracy)
            }
            Button("Claude Hybrid (Haiku 3.5 then Sonnet 4)") {
                startImport(using: .claudeHybrid)
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "DollarsAndSense_Template"
        ) { result in
            switch result {
            case .success:
                print("✅ Template exported successfully")
            case .failure(let error):
                print("❌ Failed to export template: \(error)")
            }
        }
        .onAppear { loadTransactions() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerImportCSV"))) { _ in
            showingImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadTransactions"))) { _ in
            loadTransactions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleTestMode"))) { _ in
            preferencesModel.testMode.toggle()
            KeychainHelper.shared.save(preferencesModel.testMode ? "true" : "false", service: "DollarsAndSense", account: "TestMode")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusSearchBar"))) { _ in
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshAPIKey"))) { _ in
            refreshStoredApiKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshProviderKeys"))) { _ in
            refreshStoredApiKey()
        }
        .sheet(isPresented: $showingAddCategorySheet) {
            VStack(spacing: 20) {
                Text("Add New Category")
                    .font(.headline)
                TextField("Enter category name", text: $newCategoryInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                HStack {
                    Button("Cancel") {
                        showingAddCategorySheet = false
                        newCategoryInput = ""
                        transactionPendingNewCategory = nil
                    }
                    Button("Add") {
                        if let tx = transactionPendingNewCategory,
                           let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                            transactions[index].category = newCategoryInput
                            transactions[index].source = .user
                            transactions[index].categorizedByModel = nil
                            categorySuggestions[transactions[index].details] = newCategoryInput
                            try? modelContext.save()
                            transactions = Array(transactions)
                        }
                        showingAddCategorySheet = false
                        newCategoryInput = ""
                        transactionPendingNewCategory = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showingImportErrorSheet) {
            VStack(alignment: .leading) {
                Text("Import Issues")
                    .font(.headline)
                    .padding(.bottom, 10)

                ScrollView {
                    ForEach(importErrors, id: \.self) { error in
                        Text("• \(error)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }

                Button("Close") {
                    showingImportErrorSheet = false
                    importErrors.removeAll()
                }
                .padding(.top)
            }
            .padding()
            .frame(width: 500, height: 300)
        }
        .sheet(isPresented: $showingBulkAddCategorySheet) {
            VStack(spacing: 20) {
                Text("Add New Category for Selected Rows")
                    .font(.headline)

                Text("\(selectedTransactionIDs.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Enter category name", text: $bulkNewCategoryInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                HStack {
                    Button("Cancel") {
                        showingBulkAddCategorySheet = false
                        bulkNewCategoryInput = ""
                    }

                    Button("Apply") {
                        applyCategoryToSelectedRows(bulkNewCategoryInput)
                        showingBulkAddCategorySheet = false
                        bulkNewCategoryInput = ""
                    }
                    .disabled(selectedTransactionIDs.isEmpty || bulkNewCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 340)
        }
        .sheet(isPresented: $showingSmartBulkSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Smart Bulk Categorize")
                    .font(.headline)

                Picker("Scope", selection: $smartBulkScope) {
                    Text("Visible Rows").tag(SmartBulkScope.visibleRows)
                    Text("Similar Rows as Selected Row").tag(SmartBulkScope.similarToSelectedRow)
                }

                Text("Visible rows in table: \(filteredTransactions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if smartBulkScope == .similarToSelectedRow {
                    if selectedTransactionIDs.count != 1 {
                        Text("Select exactly 1 row to use Similar Rows mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if smartBulkReferenceMerchantKey.isEmpty {
                        Text("Could not derive a merchant key from the selected row.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Matching merchant key: \(smartBulkReferenceMerchantKey)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Match logic", selection: $smartBulkSimilarMatchMode) {
                        Text("Exact").tag(SmartBulkSimilarMatchMode.exact)
                        Text("Starts With").tag(SmartBulkSimilarMatchMode.startsWith)
                        Text("Contains").tag(SmartBulkSimilarMatchMode.contains)
                    }

                    TextField("Match text (ex: AMAZON)", text: $smartBulkSimilarMatchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    if !smartBulkNormalizedSimilarMatchText.isEmpty {
                        Text("Normalized match text: \(smartBulkNormalizedSimilarMatchText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Picker("Only rows currently in", selection: $smartBulkSourceCategoryFilter) {
                    Text("Any Category").tag("__any__")
                    ForEach(smartBulkSourceCategoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                Picker("Set category to", selection: $smartBulkTargetCategorySelection) {
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                    Text("Add New...").tag("__add_new__")
                }

                if smartBulkTargetCategorySelection == "__add_new__" {
                    TextField("New category name", text: $smartBulkNewTargetCategoryInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Text("Candidate rows: \(smartBulkCandidateTransactions.count) • Will update \(smartBulkRowsToChangeCount) row(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if smartBulkRowsToChangeCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Preview (rows that will change)")
                            .font(.caption)
                            .fontWeight(.semibold)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(smartBulkPreviewRows) { tx in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .frame(width: 68, alignment: .leading)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tx.details)
                                                .font(.caption)
                                                .lineLimit(1)

                                            HStack(spacing: 6) {
                                                Text(tx.category)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Image(systemName: "arrow.right")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(smartBulkResolvedTargetCategory)
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(maxHeight: 180)

                        if smartBulkRowsToChangeCount > smartBulkPreviewRows.count {
                            Text("...and \(smartBulkRowsToChangeCount - smartBulkPreviewRows.count) more row(s)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Cancel") {
                        showingSmartBulkSheet = false
                    }

                    Button("Apply") {
                        let ids = Set(smartBulkCandidateTransactions.map(\.id))
                        applyCategoryToTransactionIDs(ids, category: smartBulkResolvedTargetCategory)
                        showingSmartBulkSheet = false
                    }
                    .disabled(smartBulkRowsToChangeCount == 0)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 420)
        }
    }

    // MARK: - Chart Section (Pie/Weekly)
    private var chartSection: some View {
        PieChartWithCategoriesView
    }

    // MARK: - Pie Chart with Logo and Category Label Grid
    private var PieChartWithCategoriesView: some View {
        HStack(alignment: .top, spacing: 24) {
            SpendingByCategoryChart(
                transactions: transactions,
                selectedCategory: $selectedCategory,
                hoveredCategory: $hoveredCategory
            )
            .frame(width: 300, height: 300)

            categoryLabelGrid
                .frame(minWidth: 560, maxWidth: 700)

            if colorScheme == .dark {
                Image("LogoWhiteBackground")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320, height: 320)
            } else {
                Image("LogoTransparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320, height: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .padding(.bottom, 30)
    }
   

    // MARK: - Category Label Grid (for Pie chart)
    @Environment(\.colorScheme) private var colorScheme
    private var categoryLabelGrid: some View {
        let grouped = Dictionary(grouping: transactions.filter { $0.amount < 0 }, by: { $0.category })
        let categoryTotals = grouped.map { (category, txs) in
            (category, txs.map { abs($0.amount) }.reduce(0, +))
        }
        let overallTotal = categoryTotals.map(\.1).reduce(0, +)
        let sortedCategories = categoryTotals.sorted { $0.1 > $1.1 }
        let columns = [
            GridItem(.flexible(minimum: 130), spacing: 6),
            GridItem(.flexible(minimum: 130), spacing: 6),
            GridItem(.flexible(minimum: 130), spacing: 6),
            GridItem(.flexible(minimum: 130), spacing: 6)
        ]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(sortedCategories, id: \.0) { item in
                let isSelected = selectedCategory == item.0
                let hash = abs(item.0.hashValue)
                let hue = Double(hash % 360) / 360.0
                let color = Color(hue: hue, saturation: 0.66, brightness: colorScheme == .dark ? 0.72 : 0.9)
                let percent = overallTotal > 0 ? (item.1 / overallTotal) * 100 : 0
                VStack(spacing: 2) {
                    Text(item.0)
                        .font(.caption)
                        .fontWeight(isSelected ? .bold : .semibold)
                        .lineLimit(1)
                    Text("\(percent, specifier: "%.1f")%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                    .foregroundColor(isSelected ? color : .primary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        (hoveredCategory == item.0 || isSelected)
                        ? color.opacity(0.18)
                        : Color(NSColor.textBackgroundColor).opacity(0.75)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color.opacity(0.9) : Color.gray.opacity(0.22), lineWidth: isSelected ? 1.4 : 0.7)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onHover { hovering in
                        hoveredCategory = hovering ? item.0 : nil
                    }
                    .onTapGesture {
                        guard !transactions.isEmpty else { return }
                        if selectedCategory == item.0 {
                            selectedCategory = nil
                        } else {
                            selectedCategory = item.0
                        }
                    }
            }
        }
        .background(
            colorScheme == .dark ? Color.black.opacity(0.6) : Color.white
        )
    }
    // MARK: - Transaction Section
    // transactionSection is now inlined in body to allow for selected category block placement


    // MARK: - Buttons and Controls Bar (previously in body)
    private var importButton: some View {
        Button("Import CSV") {
            showingImporter = true
        }
        .padding(.trailing, 10)
    }

    private var clearButton: some View {
        Button("Clear All") {
            clearAllTransactions()
        }
        .padding(.trailing, 10)
    }

    private var reCategorizeButton: some View {
        Button("Re-Categorize") {
            showReCategorizeConfirmation = true
        }
        .padding(.trailing, 10)
        .alert("Apply Suggested Categories?", isPresented: $showReCategorizeConfirmation) {
            Button("Apply", role: .destructive) {
                withAnimation {
                    for (index, tx) in transactions.enumerated() {
                        if tx.category == "Uncategorized" {
                            if let suggestion = categorySuggestions[tx.details] {
                                transactions[index].category = suggestion
                            }
                        }
                    }
                    try? modelContext.save()
                    transactions = Array(transactions)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will assign suggested categories to all 'Uncategorized' transactions. Continue?")
        }
    }

    private var downloadTemplateButton: some View {
        Button("Download Template") {
            generateCSVTemplate()
        }
        .padding(.trailing, 10)
    }

    private var bulkCategoryButton: some View {
        Menu("Bulk Category (\(selectedTransactionIDs.count))") {
            ForEach(availableCategories, id: \.self) { category in
                Button(category) {
                    applyCategoryToSelectedRows(category)
                }
            }

            Divider()

            Button("Add New Category...") {
                bulkNewCategoryInput = ""
                showingBulkAddCategorySheet = true
            }
        }
        .disabled(selectedTransactionIDs.isEmpty)
        .padding(.trailing, 10)
    }

    private var smartBulkButton: some View {
        Button("Smart Bulk...") {
            openSmartBulkSheet()
        }
        .disabled(filteredTransactions.isEmpty)
        .padding(.trailing, 10)
    }

    private var selectedRowsCountText: some View {
        Text("\(selectedTransactionIDs.count) selected")
            .foregroundColor(.secondary)
            .padding(.trailing, 10)
    }

    private var totalIncomeAmount: Double {
        searchFilteredTransactions
            .filter { $0.amount > 0 }
            .map(\.amount)
            .reduce(0, +)
    }

    private var totalSpendAmount: Double {
        searchFilteredTransactions
            .filter { $0.amount < 0 }
            .map { abs($0.amount) }
            .reduce(0, +)
    }

    private var selectedCategoryTotalAmount: Double {
        guard selectedCategory != nil else { return 0 }
        return filteredTransactions
            .filter { $0.amount < 0 }
            .map { abs($0.amount) }
            .reduce(0, +)
    }

    private var totalIncomeText: some View {
        Text("Total Income: \(totalIncomeAmount, format: .currency(code: "USD"))")
            .fontWeight(.bold)
            .padding(.trailing, 10)
    }

    private var totalSpendText: some View {
        Text("Total Spend: \(totalSpendAmount, format: .currency(code: "USD"))")
            .fontWeight(.bold)
            .padding(.trailing, 10)
    }

    private var selectedCategoryTotalText: some View {
        Text("Selected Category Total: \(selectedCategoryTotalAmount, format: .currency(code: "USD"))")
            .fontWeight(.bold)
    }

    private var visibleCategoryOptions: [String] {
        Array(Set(filteredTransactions.map { $0.category }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var smartBulkSourceCategoryOptions: [String] {
        Array(Set(smartBulkScopeTransactions.map { $0.category }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var singleSelectedTransaction: Transaction? {
        guard selectedTransactionIDs.count == 1, let id = selectedTransactionIDs.first else { return nil }
        return transactions.first(where: { $0.id == id })
    }

    private func normalizedMerchantKey(from details: String) -> String {
        let upper = details.uppercased()
        let cleaned = upper
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)

        let stopWords: Set<String> = [
            "WITHDRAWAL", "DEBIT", "CARD", "CREDIT", "ACH", "TYPE", "PAYMENT", "PAYMENTS",
            "DEPOSIT", "DIRECT", "ENTRY", "CLASS", "CODE", "TRACE", "NUMBER", "NAME",
            "FROM", "TO", "WEB", "POS", "TX", "CA", "WA", "CO", "COM", "WWW", "INC"
        ]

        let tokens = cleaned
            .split(separator: " ")
            .map(String.init)
            .map { token -> String in
                token
                    .replacingOccurrences(of: "AMAZONCOM", with: "AMAZON")
                    .replacingOccurrences(of: "APPLECOM", with: "APPLE")
            }
            .map { token in
                token.replacingOccurrences(of: #"^\d+|\d+$"#, with: "", options: .regularExpression)
            }
            .filter { token in
                let lettersOnly = token.filter(\.isLetter)
                guard !lettersOnly.isEmpty else { return false }
                guard lettersOnly.count >= 3 else { return false }
                return !stopWords.contains(lettersOnly)
            }

        if tokens.isEmpty { return "" }
        return Array(tokens.prefix(2)).joined(separator: " ")
    }

    private func normalizedMerchantMatchText(from raw: String) -> String {
        normalizedMerchantKey(from: raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var smartBulkReferenceMerchantKey: String {
        guard let tx = singleSelectedTransaction else { return "" }
        return normalizedMerchantKey(from: tx.details)
    }

    private var smartBulkNormalizedSimilarMatchText: String {
        normalizedMerchantMatchText(from: smartBulkSimilarMatchText)
    }

    private var smartBulkResolvedTargetCategory: String {
        if smartBulkTargetCategorySelection == "__add_new__" {
            return smartBulkNewTargetCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return smartBulkTargetCategorySelection
    }

    private var smartBulkScopeTransactions: [Transaction] {
        switch smartBulkScope {
        case .visibleRows:
            return filteredTransactions
        case .similarToSelectedRow:
            let matchText = smartBulkNormalizedSimilarMatchText
            guard !matchText.isEmpty else { return [] }
            return searchFilteredTransactions.filter { tx in
                let candidateKey = normalizedMerchantKey(from: tx.details)
                guard !candidateKey.isEmpty else { return false }
                switch smartBulkSimilarMatchMode {
                case .exact:
                    return candidateKey == matchText
                case .startsWith:
                    return candidateKey.hasPrefix(matchText)
                case .contains:
                    return candidateKey.contains(matchText)
                }
            }
        }
    }

    private var smartBulkCandidateTransactions: [Transaction] {
        let scoped = smartBulkScopeTransactions
        guard smartBulkSourceCategoryFilter != "__any__" else { return scoped }
        return scoped.filter { $0.category == smartBulkSourceCategoryFilter }
    }

    private var smartBulkRowsToChangeCount: Int {
        let target = smartBulkResolvedTargetCategory
        guard !target.isEmpty else { return 0 }
        return smartBulkCandidateTransactions.filter { $0.category != target }.count
    }

    private var smartBulkChangedCandidateTransactions: [Transaction] {
        let target = smartBulkResolvedTargetCategory
        guard !target.isEmpty else { return [] }
        return smartBulkCandidateTransactions.filter { $0.category != target }
    }

    private var smartBulkPreviewRows: [Transaction] {
        Array(smartBulkChangedCandidateTransactions.prefix(12))
    }

    // MARK: - Refactored transaction controls bar
    private var transactionControlsBar: some View {
        HStack {
            importButton
            downloadTemplateButton
            clearButton
            reCategorizeButton
            bulkCategoryButton
            smartBulkButton
            selectedRowsCountText
            Spacer()
            totalIncomeText
            totalSpendText
            selectedCategoryTotalText
        }
        .padding()
    }


    // MARK: - Refactored transaction list view
    private var transactionListView: some View {
        Table(of: Transaction.self, selection: $selectedTransactionIDs, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { tx in
                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                    .frame(minWidth: 100, alignment: .leading)
            }

            TableColumn("Details", value: \.details) { tx in
                detailsTextField(for: tx)
                    .frame(minWidth: 200, alignment: .leading)
            }

            TableColumn("Amount", value: \.amount) { tx in
                amountTextField(for: tx)
                    .frame(minWidth: 150, alignment: .trailing)
            }

            TableColumn("Category", value: \.category) { tx in
                categoryPickerOrField(for: tx)
                    .frame(minWidth: 200)
            }

            if preferencesModel.showSuggestedColumn {
                TableColumn("Suggested") { tx in
                    Group {
                        if tx.category == "Uncategorized", let suggestion = categorySuggestions[tx.details] {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("")
                        }
                    }
                    .frame(minWidth: 140, alignment: .leading)
                }
            }

            if preferencesModel.showSourceColumn {
                TableColumn("Source") { tx in
                    Text(sourceLabel(for: tx))
                        .font(.caption2)
                        .foregroundColor(tx.source == .ai ? .blue : .gray)
                        .frame(minWidth: 140, alignment: .leading)
                }
            }
        } rows: {
            ForEach(filteredTransactions) { tx in
                TableRow(tx)
            }
        }
        .onChange(of: sortOrder) { newOrder in
            // Optional: Handle custom sorting side-effects here
        }
    }

    private func startImport(using mode: ImportCategorizationMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        importCSV(from: url, using: mode)
    }

    private func importCSV(from url: URL, using mode: ImportCategorizationMode) {
        do {
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                print("❌ Failed to read CSV data from URL")
                return
            }

            // Detect delimiter: prefer tab if more common, else fallback to comma
            let tabCount = content.components(separatedBy: "\n").first?.components(separatedBy: "\t").count ?? 0
            let commaCount = content.components(separatedBy: "\n").first?.components(separatedBy: ",").count ?? 0
            let delimiter = tabCount > commaCount ? "\t" : ","
            print("📄 Detected delimiter: '\(delimiter == "\t" ? "\\t" : ",")'")

            let delimiterChar = delimiter.first ?? ","
            let csv = try CSV<Named>(string: content, delimiter: CSVDelimiter(unicodeScalarLiteral: delimiterChar))
            // var importedItems: [Transaction] = []
            var errors: [String] = []

            for (index, row) in csv.rows.enumerated() {
                print("🔍 Processing row \(index): \(row)")
                let dateString = row["Processed Date"] ?? ""
                let details = row["Description"] ?? ""
                let type = (row["Credit or Debit"] ?? "").lowercased()
                let amountString = row["Amount"] ?? ""

                if dateString.isEmpty || amountString.isEmpty {
                    errors.append("❗️ Missing required fields in row \(index): \(row)")
                    continue
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                guard let date = dateFormatter.date(from: dateString) else {
                    errors.append("❗️ Invalid date format in row \(index): \(dateString)")
                    continue
                }

                guard let amount = Double(amountString) else {
                    errors.append("❗️ Invalid amount format in row \(index): \(amountString)")
                    continue
                }

                let signedAmount = type.contains("debit") ? -amount : amount
                let newTransaction = Transaction(date: date, details: details, amount: signedAmount, category: "Uncategorized")
                classifyCategory(for: details, mode: mode) { category, modelUsed in
                    DispatchQueue.main.async {
                        if let category = category, !category.isEmpty {
                            newTransaction.category = category
                            newTransaction.source = .ai
                            newTransaction.categorizedByModel = modelUsed
                            categorySuggestions[details] = category
                        }
                        modelContext.insert(newTransaction)
                        self.transactions.append(newTransaction)
                        do {
                            try modelContext.save()
                        } catch {
                            errors.append("❗️ Failed to save transaction: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // The following lines are now redundant and removed/commented out:
            /*
            for tx in importedItems {
                modelContext.insert(tx)
            }
            do {
                try modelContext.save()
            } catch {
                errors.append("❗️ Failed to save transactions: \(error.localizedDescription)")
            }
            self.transactions.append(contentsOf: importedItems)
            */

            if !errors.isEmpty {
                self.importErrors = errors
                self.showingImportErrorSheet = true
            } else {
                print("✅ Successfully imported transactions.")
            }

        } catch {
            print("❌ CSV parsing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - AI Category Classification
    private let categorySystemPrompt = "You are a financial assistant. Respond with only the spending category (e.g., Groceries, Restaurants, Gas, Digital Services, Shopping, etc.) based on the transaction description. Do not explain your answer."
    
    private enum AIProvider {
        case openAI
        case anthropic
    }

    private func modelPlan(for mode: ImportCategorizationMode) -> (provider: AIProvider, primary: String, fallback: String?) {
        switch mode {
        case .openAIFast:
            return (.openAI, "gpt-5.4-nano", "gpt-4.1-mini")
        case .openAIHighAccuracy:
            return (.openAI, "gpt-5.4-mini", "gpt-4.1-mini")
        case .openAIHybrid:
            return (.openAI, "gpt-5.4-nano", "gpt-5.4-mini")
        case .claudeFast:
            return (.anthropic, "claude-3-5-haiku-20241022", nil)
        case .claudeHighAccuracy:
            return (.anthropic, "claude-sonnet-4-20250514", nil)
        case .claudeHybrid:
            return (.anthropic, "claude-3-5-haiku-20241022", "claude-sonnet-4-20250514")
        }
    }

    private func classifyCategory(for description: String, mode: ImportCategorizationMode, completion: @escaping (String?, String?) -> Void) {
        if preferencesModel.testMode {
            completion(nil, nil)
            return
        }

        let plan = modelPlan(for: mode)
        classifyCategoryWithModel(description: description, provider: plan.provider, model: plan.primary) { primaryCategory in
            if primaryCategory == nil, let fallbackModel = plan.fallback {
                print("⚖️ Primary model failed, trying fallback \(fallbackModel) for: \(description)")
                self.classifyCategoryWithModel(description: description, provider: plan.provider, model: fallbackModel) { fallbackCategory in
                    completion(fallbackCategory, fallbackCategory == nil ? plan.primary : fallbackModel)
                }
                return
            }

            guard
                let fallbackModel = plan.fallback,
                self.shouldEscalateToFallback(primaryCategory)
            else {
                completion(primaryCategory, plan.primary)
                return
            }

            print("⚖️ Escalating to \(fallbackModel) for: \(description)")
            self.classifyCategoryWithModel(description: description, provider: plan.provider, model: fallbackModel) { fallbackCategory in
                if let fallbackCategory, !fallbackCategory.isEmpty {
                    completion(fallbackCategory, fallbackModel)
                } else {
                    completion(primaryCategory, plan.primary)
                }
            }
        }
    }

    private func classifyCategoryWithModel(description: String, provider: AIProvider, model: String, completion: @escaping (String?) -> Void) {
        switch provider {
        case .openAI:
            classifyCategoryWithOpenAI(description: description, model: model, completion: completion)
        case .anthropic:
            classifyCategoryWithAnthropic(description: description, model: model, completion: completion)
        }
    }
    
    private func classifyCategoryWithOpenAI(description: String, model: String, completion: @escaping (String?) -> Void) {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedApiKey
        guard !resolvedKey.isEmpty else {
            print("❌ Missing API key, skipping classification.")
            completion(nil)
            return
        }
        request.addValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "system", "content": categorySystemPrompt],
            ["role": "user", "content": "Transaction: \(description)"]
        ]
        let json: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch {
            print("❌ Failed to encode JSON: \(error)")
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ API call failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if
                    let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let errorObj = errorJSON["error"] as? [String: Any],
                    let message = errorObj["message"] as? String
                {
                    print("❌ OpenAI \(model) status \(httpResponse.statusCode): \(message)")
                } else if let body = String(data: data, encoding: .utf8) {
                    print("❌ OpenAI \(model) status \(httpResponse.statusCode): \(body)")
                } else {
                    print("❌ OpenAI \(model) status \(httpResponse.statusCode)")
                }
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("🧠 \(model) Raw Response: \(content)")
                    let cleaned = cleanCategoryOutput(content)
                    if let usage = json["usage"] as? [String: Any],
                       let promptTokens = tokenCount(from: usage, keys: ["prompt_tokens", "input_tokens"]),
                       let completionTokens = tokenCount(from: usage, keys: ["completion_tokens", "output_tokens"]) {
                        updateEstimatedCost(promptTokens: promptTokens, completionTokens: completionTokens, model: model)
                    } else {
                        // Fallback in case usage metadata is missing from response.
                        updateEstimatedCost(
                            promptTokens: estimatedPromptTokens(for: description),
                            completionTokens: estimatedCompletionTokens(for: cleaned),
                            model: model
                        )
                    }
                    completion(cleaned)
                } else {
                    if let body = String(data: data, encoding: .utf8) {
                        print("❌ OpenAI \(model) unexpected response shape: \(body)")
                    }
                    completion(nil)
                }
            } catch {
                print("❌ Failed to parse API response: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    private func classifyCategoryWithAnthropic(description: String, model: String, completion: @escaping (String?) -> Void) {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedAnthropicApiKey
        guard !resolvedKey.isEmpty else {
            print("❌ Missing Anthropic API key, skipping classification.")
            completion(nil)
            return
        }
        
        request.addValue(resolvedKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let json: [String: Any] = [
            "model": model,
            "system": categorySystemPrompt,
            "max_tokens": 64,
            "temperature": 0.3,
            "messages": [
                ["role": "user", "content": "Transaction: \(description)"]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch {
            print("❌ Failed to encode Anthropic JSON: \(error)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ Anthropic API call failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if
                    let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let errorObj = errorJSON["error"] as? [String: Any],
                    let message = errorObj["message"] as? String
                {
                    print("❌ Anthropic \(model) status \(httpResponse.statusCode): \(message)")
                } else if let body = String(data: data, encoding: .utf8) {
                    print("❌ Anthropic \(model) status \(httpResponse.statusCode): \(body)")
                } else {
                    print("❌ Anthropic \(model) status \(httpResponse.statusCode)")
                }
                completion(nil)
                return
            }
            
            do {
                if
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let contentItems = json["content"] as? [[String: Any]]
                {
                    let text = contentItems
                        .compactMap { item -> String? in
                            guard let type = item["type"] as? String, type == "text" else { return nil }
                            return item["text"] as? String
                        }
                        .joined(separator: "\n")
                    
                    let cleaned = cleanCategoryOutput(text)
                    if let usage = json["usage"] as? [String: Any],
                       let promptTokens = tokenCount(from: usage, keys: ["input_tokens", "prompt_tokens"]),
                       let completionTokens = tokenCount(from: usage, keys: ["output_tokens", "completion_tokens"]) {
                        updateEstimatedCost(promptTokens: promptTokens, completionTokens: completionTokens, model: model)
                    } else {
                        updateEstimatedCost(
                            promptTokens: estimatedPromptTokens(for: description),
                            completionTokens: estimatedCompletionTokens(for: cleaned),
                            model: model
                        )
                    }
                    completion(cleaned.isEmpty ? nil : cleaned)
                } else {
                    if let body = String(data: data, encoding: .utf8) {
                        print("❌ Anthropic \(model) unexpected response shape: \(body)")
                    }
                    completion(nil)
                }
            } catch {
                print("❌ Failed to parse Anthropic response: \(error)")
                completion(nil)
            }
        }.resume()
    }

    private func updateEstimatedCost(promptTokens: Int, completionTokens: Int, model: String) {
        let pricing = modelPricing(for: model)
        let inputCost = (Double(promptTokens) / 1_000_000.0) * pricing.inputPerMillion
        let outputCost = (Double(completionTokens) / 1_000_000.0) * pricing.outputPerMillion
        let callCost = inputCost + outputCost
        DispatchQueue.main.async {
            self.preferencesModel.estimatedCost += callCost
        }
    }

    private func tokenCount(from usage: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let raw = usage[key] else { continue }
            if let value = raw as? Int { return value }
            if let value = raw as? Double { return Int(value) }
            if let value = raw as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    private func modelPricing(for model: String) -> (inputPerMillion: Double, outputPerMillion: Double) {
        switch model {
        case "gpt-5.4-mini":
            return (0.25, 2.00)
        case "gpt-5.4-nano":
            return (0.05, 0.40)
        case "claude-sonnet-4-20250514":
            return (3.00, 15.00)
        case "claude-3-5-haiku-20241022":
            return (0.80, 4.00)
        default:
            return (0.25, 2.00)
        }
    }

    private func estimatedPromptTokens(for description: String) -> Int {
        let userPrompt = "Transaction: \(description)"
        let contentChars = categorySystemPrompt.count + userPrompt.count
        return Int(ceil(Double(contentChars) / 4.0)) + 16
    }

    private func estimatedCompletionTokens(for category: String) -> Int {
        max(2, Int(ceil(Double(category.count) / 4.0)) + 1)
    }

    private func cleanCategoryOutput(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Category:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldEscalateToFallback(_ category: String?) -> Bool {
        guard let raw = category else { return true }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return true }

        let lowered = cleaned.lowercased()
        let ambiguousTerms = [
            "uncategorized", "unknown", "other", "misc", "miscellaneous",
            "n/a", "cannot determine", "can't determine", "not sure"
        ]
        if ambiguousTerms.contains(where: { lowered.contains($0) }) {
            return true
        }

        if cleaned.contains("\n") || cleaned.contains(":") || cleaned.contains(".") {
            return true
        }

        let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
        if wordCount > 3 {
            return true
        }

        return false
    }

    private func sourceLabel(for tx: Transaction) -> String {
        switch tx.source {
        case .ai:
            return tx.categorizedByModel ?? "AI"
        case .user:
            return "User"
        case .unknown:
            return ""
        }
    }
    // MARK: - Refresh stored API key from Keychain
    private func refreshStoredApiKey() {
        storedApiKey = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "OpenAIKey") ?? ""
        storedAnthropicApiKey = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "AnthropicKey") ?? ""
    }

    private func loadTransactions() {
        // No longer using sortDescriptor, so just fetch all and let Table handle sorting.
        let descriptor: FetchDescriptor<Transaction> = FetchDescriptor()
        if let results = try? modelContext.fetch(descriptor) {
            print("Fetched \(results.count) transactions from SwiftData")
            transactions = Array(results)
            for tx in transactions {
                print("🧾 \(tx.details) - \(tx.amount) - \(tx.category)")
            }
        }
    }

    private func clearAllTransactions() {
        withAnimation {
            for tx in transactions {
                modelContext.delete(tx)
            }
            try? modelContext.save()
            transactions.removeAll()
            selectedTransactionIDs.removeAll()
        }
    }

    private var availableCategories: [String] {
        Array(Set(transactions.map { $0.category }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func applyCategoryToTransactionIDs(_ ids: Set<UUID>, category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ids.isEmpty else { return }

        var changed = false
        for index in transactions.indices where ids.contains(transactions[index].id) {
            transactions[index].category = trimmed
            transactions[index].source = .user
            transactions[index].categorizedByModel = nil
            categorySuggestions[transactions[index].details] = trimmed
            changed = true
        }

        guard changed else { return }

        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to save bulk category update: \(error.localizedDescription)")
        }
        transactions = Array(transactions)
    }

    private func applyCategoryToSelectedRows(_ category: String) {
        applyCategoryToTransactionIDs(selectedTransactionIDs, category: category)
    }

    private func openSmartBulkSheet() {
        smartBulkScope = .visibleRows
        smartBulkSimilarMatchMode = .exact
        smartBulkSimilarMatchText = smartBulkReferenceMerchantKey
        smartBulkSourceCategoryFilter = "__any__"
        smartBulkTargetCategorySelection = availableCategories.first ?? "__add_new__"
        smartBulkNewTargetCategoryInput = ""
        showingSmartBulkSheet = true
    }

    private func generateCSVTemplate() {
        let headers = "Account,Processed Date,Description,Check Number,Credit or Debit,Amount\n"
        let sample = """
DemoAccount,2025-04-30,WITHDRAWAL DEBIT CARD STORE AnyTown TX,,Debit,11.68
DemoAccount,2025-04-29,DEPOSIT DIRECT DEPOSIT EMPLOYER PAYROLL,,Credit,2200.00
DemoAccount,2025-04-28,PAYMENT NETFLIX.COM TX,,Debit,15.99
DemoAccount,2025-04-27,WITHDRAWAL ATM TX,,Debit,40.00
"""
        let content = headers + sample

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("DollarsAndSense_Template.csv")

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            csvDocument = URLDocument(url: fileURL)
            showExporter = true
        } catch {
            print("❌ Failed to create template CSV: \(error)")
        }
    }

    // MARK: - API Key Verification
    private func verifyAPIKey() {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedApiKey
        request.addValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "user", "content": "Say OK."]
        ]
        let json: [String: Any] = [
            "model": "gpt-5.4-mini",
            "messages": messages,
            "temperature": 0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch {
            apiKeyStatus = "❌ Failed to encode request"
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    apiKeyStatus = "❌ Network error: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 429 {
                        apiKeyStatus = "❌ Rate limit hit (429). Try again later."
                    } else if httpResponse.statusCode == 401 {
                        apiKeyStatus = "❌ Invalid API Key (Status 401)"
                    } else {
                        apiKeyStatus = "❌ API Error (Status \(httpResponse.statusCode))"
                    }
                }
                return
            }

            DispatchQueue.main.async {
                apiKeyStatus = "✅ API Key is valid!"
            }
        }.resume()
    }
}

struct URLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        fatalError("init(configuration:) has not been implemented")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}


// MARK: - PreferencesView for Test Mode and API Key Testing
struct PreferencesView: View {
    @State private var storedApiKey: String = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "OpenAIKey") ?? ""
    @State private var storedAnthropicApiKey: String = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "AnthropicKey") ?? ""
    @State private var openAIKeyStatus: String = ""
    @State private var anthropicKeyStatus: String = ""
    @EnvironmentObject var preferencesModel: AppPreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Test Mode (no API calls)", isOn: $preferencesModel.testMode)
                .onChange(of: preferencesModel.testMode) { newValue in
                    KeychainHelper.shared.save(newValue ? "true" : "false", service: "DollarsAndSense", account: "TestMode")
                }
                .toggleStyle(SwitchToggleStyle())

            SecureField("OpenAI API Key", text: $storedApiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: storedApiKey) { newValue in
                    KeychainHelper.shared.save(newValue, service: "DollarsAndSense", account: "OpenAIKey")
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshProviderKeys"), object: nil)
                }

            HStack(spacing: 10) {
                Button("Test OpenAI Key") {
                    verifyOpenAIKey()
                }
                .buttonStyle(.bordered)
                
                if !openAIKeyStatus.isEmpty {
                    Text(openAIKeyStatus)
                        .foregroundColor(openAIKeyStatus.contains("✅") ? .green : .red)
                        .font(.caption)
                }
            }

            SecureField("Anthropic API Key (Claude)", text: $storedAnthropicApiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: storedAnthropicApiKey) { newValue in
                    KeychainHelper.shared.save(newValue, service: "DollarsAndSense", account: "AnthropicKey")
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshProviderKeys"), object: nil)
                }
            
            HStack(spacing: 10) {
                Button("Test Anthropic Key") {
                    verifyAnthropicKey()
                }
                .buttonStyle(.bordered)
                
                if !anthropicKeyStatus.isEmpty {
                    Text(anthropicKeyStatus)
                        .foregroundColor(anthropicKeyStatus.contains("✅") ? .green : .red)
                        .font(.caption)
                }
            }

            Text(String(format: "Estimated AI cost: $%.6f", preferencesModel.estimatedCost))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 320)
    }

    private func verifyOpenAIKey() {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedKey.isEmpty else {
            openAIKeyStatus = "❌ OpenAI key is empty"
            return
        }
        request.addValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [["role": "user", "content": "Say OK."]]
        let json: [String: Any] = [
            // Use a broadly available model to validate key credentials separately
            // from newer model-access checks during import.
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch {
            openAIKeyStatus = "❌ Failed to encode request"
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let _ = data, error == nil else {
                DispatchQueue.main.async {
                    openAIKeyStatus = "❌ Network error: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 429 {
                        openAIKeyStatus = "❌ Rate limit hit (429). Try again later."
                    } else if httpResponse.statusCode == 401 {
                        openAIKeyStatus = "❌ Invalid API Key (Status 401)"
                    } else if httpResponse.statusCode == 400 {
                        openAIKeyStatus = "❌ Bad request (400). Check request/model settings."
                    } else {
                        openAIKeyStatus = "❌ API Error (Status \(httpResponse.statusCode))"
                    }
                }
                return
            }

            DispatchQueue.main.async {
                openAIKeyStatus = "✅ OpenAI key is valid!"
            }
        }.resume()
    }
    
    private func verifyAnthropicKey() {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedAnthropicApiKey
        request.addValue(resolvedKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let json: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 16,
            "messages": [["role": "user", "content": "Say OK."]]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch {
            anthropicKeyStatus = "❌ Failed to encode request"
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let _ = data, error == nil else {
                DispatchQueue.main.async {
                    anthropicKeyStatus = "❌ Network error: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 429 {
                        anthropicKeyStatus = "❌ Rate limit hit (429). Try again later."
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        anthropicKeyStatus = "❌ Invalid API Key (Status \(httpResponse.statusCode))"
                    } else {
                        anthropicKeyStatus = "❌ API Error (Status \(httpResponse.statusCode))"
                    }
                }
                return
            }
            
            DispatchQueue.main.async {
                anthropicKeyStatus = "✅ Anthropic key is valid!"
            }
        }.resume()
    }
}

// MARK: - NumberFormatter currency helper
extension NumberFormatter {
    static var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}





// MARK: - Search Field Overlay Extraction
private extension ContentView {
    var searchField: some View {
        HStack {
            Spacer()
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
    }

    var searchFieldOverlay: some View {
        searchField
    }
}
