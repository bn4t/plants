import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showCleared = false

    private var hasKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isInitialSetup: Bool {
        Secrets.openRouterAPIKey == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if isInitialSetup {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(Color.green)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("One-time setup")
                                    .font(.headline)
                                Text("Plants uses OpenRouter to identify plants from photos. Paste a key below to get started — the free tier is plenty.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    SecureField("sk-or-v1-…", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("OpenRouter API key")
                } footer: {
                    Text("Used to identify plants from photos. Get a free key at openrouter.ai — the key is stored locally on this device only.")
                }

                Section {
                    Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                        Label("Get an API key", systemImage: "arrow.up.right.square")
                    }

                    if hasKey {
                        Button(role: .destructive) {
                            apiKey = ""
                            Secrets.setOpenRouterAPIKey("")
                            showCleared = true
                        } label: {
                            Label("Clear key", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Secrets.setOpenRouterAPIKey(apiKey)
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = Secrets.openRouterAPIKey ?? ""
            }
            .alert("Key cleared", isPresented: $showCleared) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
