import AppKit
import SwiftData
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Using AI-Powered Categorization")
                    .font(.title2).bold()

                Text("This app can automatically categorize your transactions using OpenAI's GPT model. To use this feature:")

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Go to \"File > Preferences\".")
                    Text("2. Toggle off Test Mode if you'd like to make real API calls.")
                    Text("3. Paste in your OpenAI API key. You can get one at:")
                        + Text(" https://platform.openai.com/account/api-keys").foregroundColor(.blue)
                    Text("4. Click \"Test API Key\" to verify it.")
                }

                Text("💡 TIP: In Test Mode, the app will not contact OpenAI. This is good for experimenting.")

                Text("💰 Estimated Cost:")
                Text("Each classification costs about $0.0002 using GPT-3.5. For 1,000 transactions, the total cost would be around $0.20.")

                Text("🔒 Privacy:")
                Text("Your API key is stored securely in your local Keychain and is never sent anywhere else.")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}


@main
struct DollarsAndSenseApp: App {
    @StateObject private var preferencesModel = AppPreferencesModel()
    @State private var helpWindow: NSWindow?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferencesModel)
        }
        .modelContainer(for: Transaction.self)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences") {
                    let preferencesWindow = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                        styleMask: [.titled, .closable],
                        backing: .buffered,
                        defer: false)
                    preferencesWindow.center()
                    preferencesWindow.title = "Preferences"
                    preferencesWindow.isReleasedWhenClosed = false
                    preferencesWindow.contentView = NSHostingView(rootView: PreferencesView().environmentObject(preferencesModel))
                    preferencesWindow.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(after: .help) {
                Button("Using AI Categorization") {
                    if helpWindow == nil {
                        helpWindow = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
                        helpWindow?.center()
                        helpWindow?.title = "Help"
                        helpWindow?.contentView = NSHostingView(rootView: HelpView())
                        helpWindow?.isReleasedWhenClosed = false
                    }
                    helpWindow?.makeKeyAndOrderFront(nil)
                }
            }
            CommandGroup(after: .toolbar) {
                Toggle("Show Suggested Column", isOn: $preferencesModel.showSuggestedColumn)
                Toggle("Show Source Column", isOn: $preferencesModel.showSourceColumn)
            }
            CommandGroup(after: .newItem) {
                Button("Import CSV") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerImportCSV"), object: nil)
                }.keyboardShortcut("i", modifiers: .command)

                Button("Reload Transactions") {
                    NotificationCenter.default.post(name: NSNotification.Name("ReloadTransactions"), object: nil)
                }.keyboardShortcut("r", modifiers: .command)

                Button("Toggle Test Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleTestMode"), object: nil)
                }.keyboardShortcut("t", modifiers: .command)

                Button("Focus Search") {
                    NotificationCenter.default.post(name: NSNotification.Name("FocusSearchBar"), object: nil)
                }.keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
