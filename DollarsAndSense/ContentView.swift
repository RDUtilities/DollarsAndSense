import SwiftUI
import Charts
import SwiftData
import UniformTypeIdentifiers

@Model
final class Transaction: Identifiable {
    var id: UUID
    var date: Date
    var details: String
    var amount: Double
    var category: String

    init(date: Date, details: String, amount: Double, category: String) {
        self.id = UUID()
        self.date = date
        self.details = details
        self.amount = amount
        self.category = category
    }
}


struct SpendingByCategoryChart: View {
    var transactions: [Transaction]
    @Binding var selectedCategory: String?
    @Binding var hoveredCategory: String?

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

                let columns = Array(repeating: GridItem(.flexible(minimum: 100), spacing: 6), count: 3)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(categoryTotals.sorted(by: { $0.total > $1.total }), id: \.category) { item in
                        let isSelected = selectedCategory == item.category
                        let hash = abs(item.category.hashValue)
                        let hue = Double(hash % 360) / 360.0
                        let color = Color(hue: hue, saturation: 0.6, brightness: 0.9)

                        Text(item.category)
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundColor(isSelected ? color : .primary)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (hoveredCategory == item.category || isSelected)
                                ? color.opacity(0.2)
                                : Color.clear
                            )
                            .cornerRadius(6)
                            .onHover { hovering in
                                hoveredCategory = hovering ? item.category : nil
                            }
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                            .animation(.easeInOut, value: selectedCategory)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .padding(.trailing)
            }
        }
        .padding()
    }

    @ChartContentBuilder
    private func chartContent() -> some ChartContent {
        ForEach(categoryTotals, id: \.category) { item in
            let hash = abs(item.category.hashValue)
            let hue = Double(hash % 360) / 360.0
            let baseColor = Color(hue: hue, saturation: 0.6, brightness: 0.9)
            let style = selectedCategory == nil || selectedCategory == item.category
                ? AnyShapeStyle(baseColor)
                : AnyShapeStyle(Color.gray.opacity(0.3))

            SectorMark(
                angle: .value("Total", item.total),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(style)
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var transactions: [Transaction] = []
    @State private var selectedCategory: String? = nil
    @State private var showingImporter = false
    @State private var editingTransactionID: UUID? = nil
    // Track new category text input
    @State private var newCategoryText: String = ""
    @State private var hoveredCategory: String? = nil
    @State private var csvDocument: URLDocument? = nil
    @State private var showExporter: Bool = false

    private func colorForCategory(_ category: String) -> Color {
        let hash = abs(category.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }

    var filteredTransactions: [Transaction] {
        if let category = selectedCategory {
            return transactions.filter { $0.category == category }
        } else {
            return transactions
        }
    }

    var body: some View {
        VStack {
            if let selected = selectedCategory {
                Text("Showing: \(selected)")
                    .font(.headline)
                    .padding(.bottom, 4)
            }

            SpendingByCategoryChart(transactions: transactions, selectedCategory: $selectedCategory, hoveredCategory: $hoveredCategory)
                .frame(height: 300)

            Picker("Filter Category", selection: $selectedCategory) {
                Text("All").tag(String?.none)
                ForEach(Array(Set(transactions.map { $0.category })), id: \.self) { category in
                    Text(category).tag(String?.some(category))
                }
            }
            .pickerStyle(.menu)
            .padding()


            VStack(spacing: 0) {
                // Table Headers
                HStack {
                    Text("Date").bold().frame(width: 100, alignment: .leading)
                    Text("Details").bold().frame(maxWidth: .infinity, alignment: .leading)
                    Text("Amount").bold().frame(width: 80, alignment: .trailing)
                    Text("Category").bold().frame(width: 120, alignment: .leading)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))

                // Transactions List
                List {
                    ForEach(filteredTransactions) { tx in
                        HStack {
                            Text(tx.date, style: .date)
                                .frame(width: 100, alignment: .leading)
                            Text(tx.details)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "$%.2f", tx.amount))
                                .frame(width: 80, alignment: .trailing)
                            // Category Picker and Add New Field (refactored)
                            HStack {
                                if editingTransactionID == tx.id {
                                    TextField("New Category", text: $newCategoryText, onCommit: {
                                        if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                                            transactions[index].category = newCategoryText
                                            try? modelContext.save()
                                            transactions = Array(transactions)
                                        }
                                        editingTransactionID = nil
                                        newCategoryText = ""
                                    })
                                    .onAppear {
                                        newCategoryText = tx.category
                                    }
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 140)
                                } else {
                                    Picker("", selection: Binding(
                                        get: { tx.category },
                                        set: { newValue in
                                            if newValue == "__add_new__" {
                                                editingTransactionID = tx.id
                                            } else {
                                                if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                                                    transactions[index].category = newValue
                                                    try? modelContext.save()
                                                    transactions = Array(transactions)
                                                }
                                            }
                                        }
                                    )) {
                                        ForEach(Array(Set(transactions.map { $0.category })), id: \.self) { category in
                                            Text(category).tag(category)
                                        }
                                        Text("Add New...").tag("__add_new__")
                                    }
                                    .frame(width: 140)
                                    .pickerStyle(.menu)
                                }
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                        .background(hoveredCategory == tx.category ? colorForCategory(tx.category).opacity(0.1) : Color.clear)
                    }
                }
                .listStyle(.plain)

                // Total Row with Import, Clear, and Download Template buttons aligned trailing
                HStack {
                    Button("Import CSV") {
                        showingImporter = true
                    }
                    .padding(.trailing, 10)

                    Button("Clear All") {
                        clearAllTransactions()
                    }
                    .padding(.trailing, 10)

                    Button("Download Template") {
                        generateCSVTemplate()
                    }
                    .padding(.trailing, 10)

                    Spacer()

                    Text("Income: \(filteredTransactions.filter { $0.category.lowercased() == "income" }.map { $0.amount }.reduce(0, +), format: .currency(code: "USD"))")
                        .fontWeight(.bold)
                        .padding(.trailing, 10)

                    Text("Total: \(filteredTransactions.map { $0.amount }.reduce(0, +), format: .currency(code: "USD"))")
                        .fontWeight(.bold)
                }
                .padding()
            }
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
                let formats = ["yyyy-MM-dd", "M/d/yy"]
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
                print("Parsed columns (\(columns.count)): \(columns)")
                if columns.count >= 4 {
                    let dateString = columns[0]
                    let details = columns[1]
                    let amountString = columns[2]
                    let category = columns[3]

                    let cleanedDateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanedAmountString = amountString.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard let date = dateFormatters.compactMap({ $0.date(from: cleanedDateString) }).first else {
                        print("⚠️ Failed to parse date: \(cleanedDateString)")
                        continue
                    }
                    guard let amount = Double(cleanedAmountString) else {
                        print("⚠️ Failed to parse amount: \(cleanedAmountString)")
                        continue
                    }

                    let signedAmount = amount

                    let transaction = Transaction(
                        date: date,
                        details: details,
                        amount: signedAmount,
                        category: category
                    )
                    modelContext.insert(transaction)
                    importedCount += 1
                }
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

    private func loadTransactions() {
        let descriptor: FetchDescriptor<Transaction> = FetchDescriptor(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        if let results = try? modelContext.fetch(descriptor) {
            print("Fetched \(results.count) transactions from SwiftData")
            transactions = results
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
        let headers = "Date,Details,Amount,Category\n"
        let sample = """
2025-04-30,WITHDRAWAL DEBIT CARD STORE FRIENDSWOOD TX,-11.68,Shopping
2025-04-29,DEPOSIT DIRECT DEPOSIT EMPLOYER PAYROLL,2200.00,Income
2025-04-28,PAYMENT NETFLIX.COM TX,-15.99,Digital Services
2025-04-27,WITHDRAWAL ATM TX,-40.00,Cash
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

