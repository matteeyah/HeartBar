import AppKit
import SwiftUI
import HeartBarCore

struct HeartBarPopoverView: View {
    @ObservedObject var store: AppStore
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if store.preferences.demoMode { demoBanner }
            if !store.preferences.demoMode && !store.hasAPIKey && !store.friends.isEmpty { setupBanner }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button { store.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss notice")
                }
                .padding(12).background(.orange.opacity(0.12))
            }
            if store.friends.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.friends) { friend in
                            FriendCard(store: store, friend: friend)
                        }
                    }.padding(16)
                }
                .scrollIndicators(.visible)
            }
            Divider().opacity(0.5)
            footer
        }
        .background(.regularMaterial)
        .tint(.teal)
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(.pink.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "heart.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.pink)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("HeartBar").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(store.preferences.demoMode ? "A preview with three friends" : "Your people, a little closer")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }.padding(.horizontal, 18).padding(.vertical, 18)
    }

    private var demoBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
            Text("DEMO").fontWeight(.semibold).tracking(1)
            Text("Simulated heart rates").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10)).padding(.horizontal, 18).padding(.vertical, 10)
        .background(.teal.opacity(0.09))
        .accessibilityElement(children: .combine)
    }

    private var setupBanner: some View {
        Button(action: openSettings) {
            Label("Add your API key to connect", systemImage: "key.fill")
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).padding(12).background(.orange.opacity(0.12))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.wave.2").font(.system(size: 38, weight: .light)).foregroundStyle(.teal)
            Text("Keep your people close").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Add a friend's HypeRate ID to see their heartbeat here and in your menu bar.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add your first friend", action: openSettings).buttonStyle(.borderedProminent).controlSize(.large)
            Button("Try the demo") { store.setDemoMode(true) }.buttonStyle(.plain).foregroundStyle(.teal)
            Spacer()
            Text("Friends stream with their HypeRate app.")
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(store.liveCount > 0 ? Color.teal : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
            Text(store.preferences.demoMode ? "\(store.liveCount) simulated" : "\(store.liveCount) of \(store.friends.count) live")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("Settings").accessibilityLabel("Open HeartBar settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }
}

struct FriendCard: View {
    @ObservedObject var store: AppStore
    let friend: Friend

    private var status: ParticipantStatus { store.status(for: friend) }
    private var live: Bool { status.isLive(at: store.now) }
    private var demo: Bool { store.preferences.demoMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(friend.name.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.teal).frame(width: 30, height: 30)
                    .background(.teal.opacity(0.12), in: Circle()).accessibilityHidden(true)
                Text(friend.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    do { try store.toggleFavorite(friend) }
                    catch { store.notice = error.localizedDescription }
                } label: {
                    Image(systemName: friend.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(friend.isFavorite ? Color.orange : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(!friend.isFavorite && store.favorites.count >= 3)
                .help(friend.isFavorite ? "Remove from menu bar" : (store.favorites.count >= 3 ? "Unstar a favorite to make room (3 maximum)" : "Show in menu bar"))
                .accessibilityLabel("\(friend.isFavorite ? "Unfavorite" : "Favorite") \(friend.name)")
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(live ? String(status.reading!.bpm) : "—")
                    .font(.system(size: 39, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("BPM").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).tracking(1)
                Spacer()
                Image(systemName: "waveform.path.ecg").font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(live ? Color.teal.opacity(0.75) : Color.secondary.opacity(0.22))
                    .accessibilityHidden(true)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(live ? "\(friend.name), \(status.reading!.bpm) beats per minute, \(demo ? "simulated" : "live")" : "\(friend.name), no live reading")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(live ? Color.teal : Color.secondary).frame(width: 5, height: 5)
                    Text(status.label(at: store.now, demo: demo))
                    Spacer(minLength: 0)
                    if live, let reading = status.reading { Text(reading.ageDescription(at: store.now)).foregroundStyle(.tertiary) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if !live, let reading = status.reading {
                    Text("Last reading: \(reading.bpm) BPM · \(reading.ageDescription(at: store.now))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if case .failed(let issue) = status.connection {
                    Text(issue.message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if canRetry {
                    Button("Retry connection") { store.retry(friend) }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.teal)
                        .accessibilityLabel("Retry connection for \(friend.name)")
                }
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.045), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var canRetry: Bool {
        switch status.connection {
        case .failed, .reconnecting: true
        case .connected, .waitingForReading: !live
        default: false
        }
    }
}
