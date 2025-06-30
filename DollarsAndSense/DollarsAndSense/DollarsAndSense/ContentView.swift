

import SwiftUI
import Charts
import SwiftData
import UniformTypeIdentifiers
import Foundation

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

    init(date: Date, details: String, amount: Double, category: String, source: CategorySource = .unknown) {
        self.id = UUID()
        self.date = date
        self.details = details
        self.amount = amount
        self.category = category
        self.source = source
    }
}


struct SpendingByCategoryChart: View {
    var transactions: [Transaction]
    @Binding var selectedCategory: String?
    @Environment(\.colorScheme) private var colorScheme

    var categoryTotals: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: transactions, by: { $0.category })
        return grouped.map { (category, txs) in
            (category, txs.map { abs($0.amount) }.reduce(0, +))
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top) {
                Chart(content: chartContent)
                    .chartLegend(.hidden)
                    .frame(width: 300, height: 300)
                    .padding(.top, 40)
                    .padding(.leading)
            }
        }
        .padding()
    }

    @ChartContentBuilder
    private func chartContent() -> some ChartContent {
        ForEach(categoryTotals, id: \.category) { item in
            let hash = abs(item.category.hashValue)
            let hue = Double(hash % 360) / 360.0
            let baseColor = Color(hue: hue, saturation: 0.7, brightness: colorScheme == .dark ? 0.7 : 0.9)
            let isSelected = selectedCategory == item.category
            let style = (selectedCategory == nil || isSelected)
                ? AnyShapeStyle(baseColor)
                : AnyShapeStyle(Color.gray.opacity(0.3))

            SectorMark(
                angle: .value("Total", item.total),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .offset(
                x: isSelected ? 12 : 0,
                y: isSelected ? -12 : 0
            )
            .shadow(color: isSelected ? baseColor.opacity(0.4) : .clear, radius: 6)
            .foregroundStyle(style)
        }
    }
}


struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var preferencesModel: AppPreferencesModel
    @State private var transactions: [Transaction] = []
    @State private var selectedCategory: String? = nil
    @State private var showingImporter = false
    @State private var editingTransactionID: UUID? = nil
    // Track new category text input
    @State private var newCategoryText: String = ""
    @State private var csvDocument: URLDocument? = nil
    @State private var showExporter: Bool = false
    @State private var apiKeyStatus: String = ""
    @State private var storedApiKey: String = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "OpenAIKey") ?? ""
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
                Text(tx.source == .ai ? "AI" : tx.source == .user ? "User" : "")
                    .font(.caption2)
                    .foregroundColor(tx.source == .ai ? .blue : .gray)
                    .frame(width: 80, alignment: .leading)
            }
        }
        .background(Color.clear)
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

    var filteredTransactions: [Transaction] {
        let base = selectedCategory == nil
            ? transactions
            : transactions.filter { $0.category == selectedCategory }

        let searched = searchText.isEmpty ? base : base.filter {
            let dateString = $0.date.formatted(date: .abbreviated, time: .omitted)
            return $0.details.localizedCaseInsensitiveContains(searchText) ||
                   $0.category.localizedCaseInsensitiveContains(searchText) ||
                   String(format: "%.2f", $0.amount).contains(searchText) ||
                   dateString.localizedCaseInsensitiveContains(searchText)
        }

        return searched.sorted(using: sortOrder)
    }

    // MARK: - Category Total Map
    private var categoryTotalMap: [String: Double] {
        Dictionary(grouping: transactions, by: { $0.category })
            .mapValues { txs in txs.map { abs($0.amount) }.reduce(0, +) }
    }

    @State private var sortOrder: [KeyPathComparator<Transaction>] = [ .init(\.date, order: .reverse) ]

    var body: some View {
        VStack {
            if let selected = selectedCategory {
                Text("Showing: \(selected)")
                    .font(.headline)
                    .padding(.bottom, 4)
            }

            chartSection
            Spacer().frame(height: 8)
            if let selected = selectedCategory,
               let total = categoryTotalMap[selected] {
                categorySummaryView(for: selected, total: total)
            }
            transactionSection
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile = try result.get().first else { return }
                importCSV(from: selectedFile)
            } catch {
                print("Failed to read file: \(error.localizedDescription)")
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
    }

    // MARK: - Category Summary View
    @ViewBuilder
    private func categorySummaryView(for category: String, total: Double) -> some View {
        let overall = transactions.map { abs($0.amount) }.reduce(0, +)
        let percentage = (overall > 0) ? (total / overall) * 100 : 0

        HStack {
            Text("Category Summary:")
                .font(.headline)
            Text("\(category): \(total, format: .currency(code: "USD"))")
                .font(.body)
                .bold()
            Text("(\(percentage, specifier: "%.1f")%)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .transition(.opacity)
    }

    // MARK: - Chart Section (Pie/Weekly)
    private var chartSection: some View {
        PieChartWithCategoriesView
    }

    // MARK: - Pie Chart with Logo and Category Label Grid
    private var PieChartWithCategoriesView: some View {
        HStack(alignment: .top, spacing: 40) {
            SpendingByCategoryChart(
                transactions: transactions,
                selectedCategory: $selectedCategory
            )
            .frame(width: 300, height: 300)

            categoryLabelGrid
                .frame(minWidth: 400)

            Spacer()

            if colorScheme == .dark {
                Image("LogoWhiteBackground")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 400, height: 400)
                    .padding(.trailing)
            } else {
                Image("LogoTransparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 400, height: 400)
                    .padding(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal)
        .padding(.top, 50)
        .padding(.bottom, 30)
    }
   

    // MARK: - Category Label Grid (for Pie chart)
    @Environment(\.colorScheme) private var colorScheme
    private var categoryLabelGrid: some View {
        let grouped = Dictionary(grouping: transactions, by: { $0.category })
        let categoryTotals = grouped.map { (category, txs) in
            (category, txs.map { abs($0.amount) }.reduce(0, +))
        }
        let sortedCategories = categoryTotals.sorted {
            $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
        let columns = [
            GridItem(.flexible(minimum: 80), spacing: 2),
            GridItem(.flexible(minimum: 80), spacing: 2),
            GridItem(.flexible(minimum: 80), spacing: 2)
        ]
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(sortedCategories, id: \.0) { item in
                let isSelected = selectedCategory == item.0
                let hash = abs(item.0.hashValue)
                let hue = Double(hash % 360) / 360.0
                let color = Color(hue: hue, saturation: 0.6, brightness: colorScheme == .dark ? 0.7 : 0.9)
                Text(item.0)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? color : .primary)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        isSelected
                        ? color.opacity(0.2)
                        : Color(NSColor.textBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
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
            colorScheme == .dark ? Color.black : Color.white
        )
    }
    // MARK: - Transaction Section
    private var transactionSection: some View {
        VStack(spacing: 0) {
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

    private var incomeText: some View {
        Text("Income: \(filteredTransactions.filter { $0.category.lowercased() == "income" }.map { $0.amount }.reduce(0, +), format: .currency(code: "USD"))")
            .fontWeight(.bold)
            .padding(.trailing, 10)
    }

    private var totalText: some View {
        Text("Total: \(filteredTransactions.map { $0.amount }.reduce(0, +), format: .currency(code: "USD"))")
            .fontWeight(.bold)
    }

    // MARK: - Refactored transaction controls bar
    private var transactionControlsBar: some View {
        HStack {
            importButton
            clearButton
            reCategorizeButton
            downloadTemplateButton
            Spacer()
            incomeText
            totalText
        }
        .padding()
    }


    // MARK: - Refactored transaction list view
    private var transactionListView: some View {
        Table(filteredTransactions, sortOrder: $sortOrder) {
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
                    Text(tx.source == .ai ? "AI" : tx.source == .user ? "User" : "")
                        .font(.caption2)
                        .foregroundColor(tx.source == .ai ? .blue : .gray)
                        .frame(minWidth: 80, alignment: .leading)
                }
            }
        }
        .onChange(of: sortOrder) { newOrder in
            // Optional: Handle custom sorting side-effects here
        }
    }

    private func importCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Couldn't access file due to sandboxing.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url)
            let rows = content.components(separatedBy: "\n")
            guard rows.count > 1 else { return }

            let dateFormatters: [DateFormatter] = {
                let formats = ["yyyy-MM-dd", "M/d/yy", "M/d/yyyy", "MM/dd/yyyy"]
                return formats.map {
                    let df = DateFormatter()
                    df.dateFormat = $0
                    df.locale = Locale(identifier: "en_US_POSIX")
                    return df
                }
            }()

            var importedCount = 0

            for row in rows.dropFirst() where !row.trimmingCharacters(in: .whitespaces).isEmpty {
                let columns = row.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                }

                guard columns.count >= 6 else {
                    print("⚠️ Skipping malformed row (expected 6+ columns): \(columns)")
                    continue
                }

                // Bank export format:
                // columns[0] = Account (skip)
                // columns[1] = Processed Date
                // columns[2] = Description
                // columns[3] = Check Number (skip)
                // columns[4] = Credit or Debit
                // columns[5] = Amount

                let dateString = columns[1] // Processed Date
                let details = columns[2]    // Description
                let creditOrDebit = columns[4].lowercased() // Credit or Debit
                let amountString = columns[5] // Amount
                let category = "" // Leave blank to allow classification or set to Uncategorized

                guard let date = dateFormatters.compactMap({ $0.date(from: dateString) }).first else {
                    print("⚠️ Failed to parse date: \(dateString)")
                    continue
                }

                guard let amount = Double(amountString) else {
                    print("⚠️ Failed to parse amount: \(amountString)")
                    continue
                }

                // Treat anything that isn't explicitly "debit" as income (credit)
                let isDebit = creditOrDebit == "debit"
                let signedAmount = isDebit ? -abs(amount) : abs(amount)

                if category.isEmpty {
                    if preferencesModel.testMode {
                        let transaction = Transaction(
                            date: date,
                            details: details,
                            amount: signedAmount,
                            category: "Uncategorized",
                            source: .unknown
                        )
                        modelContext.insert(transaction)
                        transactions.append(transaction)
                    } else {
                        classifyCategory(for: details) { predictedCategory in
                            DispatchQueue.main.async {
                                let finalCategory = predictedCategory ?? "Uncategorized"
                                categorySuggestions[details] = finalCategory
                                let transaction = Transaction(
                                    date: date,
                                    details: details,
                                    amount: signedAmount,
                                    category: finalCategory,
                                    source: .ai
                                )
                                modelContext.insert(transaction)
                                transactions.append(transaction)
                                preferencesModel.estimatedCost += 0.0002
                            }
                        }
                    }
                } else {
                    let transaction = Transaction(
                        date: date,
                        details: details,
                        amount: signedAmount,
                        category: category,
                        source: .user
                    )
                    modelContext.insert(transaction)
                    transactions.append(transaction)
                }

                importedCount += 1
            }

            do {
                try modelContext.save()
            } catch {
                print("💥 Failed to save transactions: \(error.localizedDescription)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadTransactions()
                print("📊 Reloaded transactions after import")
            }
        } catch {
            print("Failed to parse CSV: \(error.localizedDescription)")
        }
    }

    // MARK: - OpenAI Category Classification
    private func classifyCategory(for description: String, completion: @escaping (String?) -> Void) {
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
            ["role": "system", "content": "You are a financial assistant. Respond with only the spending category (e.g., Groceries, Restaurants, Gas, Digital Services, Shopping, etc.) based on the transaction description. Do not explain your answer."],
            ["role": "user", "content": "Transaction: \(description)"]
        ]
        let json: [String: Any] = [
            "model": "gpt-3.5-turbo",
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

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("🧠 OpenAI Raw Response: \(content)")
                    let cleaned = content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "Category:", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                print("❌ Failed to parse API response: \(error)")
                completion(nil)
            }
        }.resume()
    }
    // MARK: - Refresh stored API key from Keychain
    private func refreshStoredApiKey() {
        storedApiKey = KeychainHelper.shared.retrieve(service: "DollarsAndSense", account: "OpenAIKey") ?? ""
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
        }
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
        print("🔐 API Key from storage: \(resolvedKey)")
        request.addValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "user", "content": "Say OK."]
        ]
        let json: [String: Any] = [
            "model": "gpt-3.5-turbo",
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
    @State private var apiKeyStatus: String = ""
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
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshAPIKey"), object: nil)
                }

            Button("Test API Key") {
                verifyAPIKey()
            }
            .buttonStyle(.bordered)

            if !apiKeyStatus.isEmpty {
                Text(apiKeyStatus)
                    .foregroundColor(apiKeyStatus.contains("✅") ? .green : .red)
                    .font(.caption)
            }

            Text(String(format: "Estimated OpenAI cost: $%.4f", preferencesModel.estimatedCost))
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }

    private func verifyAPIKey() {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let resolvedKey = storedApiKey
        request.addValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [["role": "user", "content": "Say OK."]]
        let json: [String: Any] = [
            "model": "gpt-3.5-turbo",
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
            guard let _ = data, error == nil else {
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
