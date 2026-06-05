import AppKit
import SwiftData
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Using AI-Powered Categorization")
                    .font(.title2).bold()

                Text("This app can automatically categorize transactions with OpenAI and Anthropic (Claude) models. To use this feature:")

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Go to \"File > Preferences\".")
                    Text("2. Toggle off Test Mode if you'd like to make real API calls.")
                    Text("3. Paste in your OpenAI and/or Anthropic API key in Preferences:")
                        + Text(" https://platform.openai.com/api-keys").foregroundColor(.blue)
                    Text("   and https://console.anthropic.com/settings/keys").foregroundColor(.blue)
                    Text("4. Choose your default AI model in Preferences.")
                    Text("5. Click \"Test Selected Model\" to verify the exact provider/model you plan to use.")
                    Text("6. When importing CSV, use your default model or choose a one-time override:")
                    Text("   • OpenAI Reliable: gpt-4.1-mini")
                    Text("   • OpenAI Budget: gpt-4.1-nano")
                    Text("   • OpenAI GPT-5 Fast: gpt-5-nano")
                    Text("   • OpenAI GPT-5 Higher Accuracy: gpt-5-mini")
                    Text("   • OpenAI GPT-5 Hybrid: gpt-5-nano then gpt-5-mini")
                    Text("   • Claude Sonnet: claude-sonnet-4-6")
                }

                Text("💡 TIP: In Test Mode, the app will not contact OpenAI or Anthropic. This is good for experimenting.")

                Text("💰 Estimated Cost:")
                Text("Pricing used by this app:")
                Text("• gpt-4.1-mini: $0.40 / 1M input tokens, $1.60 / 1M output tokens")
                Text("• gpt-4.1-nano: $0.10 / 1M input tokens, $0.40 / 1M output tokens")
                Text("• gpt-5-nano: $0.05 / 1M input tokens, $0.40 / 1M output tokens")
                Text("• gpt-5-mini: $0.25 / 1M input tokens, $2.00 / 1M output tokens")
                Text("• Claude Sonnet: $3.00 / 1M input tokens, $15.00 / 1M output tokens")
                Text("The app tracks token usage and estimates actual cost during imports.")
                Text("Help copy version: RC3.2 Preferences model selector (June 2026)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                        contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
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
