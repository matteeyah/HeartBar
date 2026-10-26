import AppKit
import SwiftUI
import HeartBarCore

// Explicitly select the property wrapper on SDKs that also declare a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            FriendsSettings(store: store).tabItem { Label("Friends", systemImage: "person.2") }.tag(0)
            ConnectionSettings(store: store).tabItem { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }.tag(1)
        }
        .padding(20).frame(width: 620, height: 580).tint(.teal)
        .onAppear { if !store.hasAPIKey && !store.preferences.friends.isEmpty { tab = 1 } }
    }
}

private struct FriendEditorItem: Identifiable {
    let id = UUID()
    var friend: Friend?
}

struct FriendsSettings: View {
    @ObservedObject var store: AppStore
    @ViewState private var editor: FriendEditorItem?
    @ViewState private var removing: Friend?
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your people").font(.title2.weight(.semibold))
                    Text("Star up to three friends for your menu bar.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { editor = FriendEditorItem() } label: { Label("Add friend", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            if store.preferences.friends.isEmpty {
                ContentUnavailableView("No friends yet", systemImage: "person.crop.circle.badge.plus", description: Text("Ask a friend for the ID shown in their HypeRate app."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(store.preferences.friends.enumerated()), id: \.element.id) { index, friend in
                        HStack(spacing: 10) {
                            Button {
                                do { try store.toggleFavorite(friend) } catch { self.error = error.localizedDescription }
                            } label: {
                                Image(systemName: friend.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(friend.isFavorite ? Color.orange : Color.secondary)
                            }.buttonStyle(.plain)
                                .disabled(!friend.isFavorite && store.preferences.friends.filter(\.isFavorite).count >= 3)
                                .help("Show up to three favorites in the menu bar")
                                .accessibilityLabel("\(friend.isFavorite ? "Unfavorite" : "Favorite") \(friend.name)")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(friend.name).fontWeight(.medium)
                                Text(friend.hypeRateID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { store.moveFriend(friend, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0).help("Move up").accessibilityLabel("Move \(friend.name) up")
                            Button { store.moveFriend(friend, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == store.preferences.friends.count - 1).help("Move down").accessibilityLabel("Move \(friend.name) down")
                            Button("Edit") { editor = FriendEditorItem(friend: friend) }
                            Button(role: .destructive) { removing = friend } label: { Image(systemName: "trash") }
                                .help("Remove friend").accessibilityLabel("Remove \(friend.name)")
                        }.padding(.vertical, 6)
                    }
                }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("Readings are live only. HeartBar does not record history.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
            .sheet(item: $editor) { item in FriendEditor(store: store, friend: item.friend) }
            .alert("Remove \(removing?.name ?? "friend")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Cancel", role: .cancel) { removing = nil }
                Button("Remove", role: .destructive) {
                    if let friend = removing { store.removeFriend(friend) }
                    removing = nil
                }
            } message: { Text("This stops their connection and removes their saved HypeRate ID.") }
            .alert("Could not update favorite", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct FriendEditor: View {
    @ObservedObject var store: AppStore
    let friend: Friend?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var hypeRateID = ""
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(friend == nil ? "Add a friend" : "Edit friend").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("HypeRate ID", text: $hypeRateID).textFieldStyle(.roundedBorder)
            Text("Use the ID from their HypeRate app, not an Events link.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save friend") {
                    do {
                        try store.saveFriend(id: friend?.id, name: name, hypeRateID: hypeRateID)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 390)
            .onAppear { name = friend?.name ?? ""; hypeRateID = friend?.hypeRateID ?? "" }
    }
}

struct ConnectionSettings: View {
    @ObservedObject var store: AppStore
    @ViewState private var apiKey = ""
    @ViewState private var result: String?
    @ViewState private var failure = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Label(store.hasAPIKey ? "API key saved in Keychain" : "No API key saved", systemImage: store.hasAPIKey ? "checkmark.shield" : "key")
                        .foregroundStyle(store.hasAPIKey ? Color.teal : Color.secondary)
                    Spacer()
                }
                SecureField(store.hasAPIKey ? "Paste a replacement API key" : "Paste your HypeRate API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save API key") {
                        do {
                            try store.setAPIKey(apiKey)
                            apiKey = ""
                            failure = false
                            result = "API key saved. Connecting your friends…"
                        } catch { failure = true; result = error.localizedDescription }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.hasAPIKey {
                        Button("Remove key", role: .destructive) {
                            do { try store.setAPIKey(nil); apiKey = ""; failure = false; result = "API key removed." }
                            catch { failure = true; result = error.localizedDescription }
                        }
                    }
                    Spacer()
                    Link("Request API access ↗", destination: URL(string: "https://www.hyperate.io/api")!)
                }
                if let result { Text(result).font(.caption).foregroundStyle(failure ? Color.red : Color.secondary) }
                Text("Your key stays in the macOS Keychain. Heart rates stay in memory and are never written to disk.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("HypeRate connection") }
            Section {
                HStack {
                    Text("\(store.liveCount) of \(store.friends.count) friends live")
                    Spacer()
                    Button("Reconnect all") { store.retryAll() }
                }
                Text("A friend must be actively streaming from HypeRate. After 15 seconds without an update, their reading is marked stale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
