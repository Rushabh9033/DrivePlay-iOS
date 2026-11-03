import SwiftUI

public struct SettingsView: View {
    @ObservedObject var playlistStore = PlaylistStore.shared
    @StateObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showAddSource: Bool = false
    @State private var showCarMode: Bool = false
    @State private var showLocalImport: Bool = false

    public init() {}

    private var proStatus: String {
        storeManager.isProUnlocked ? "Unlocked" : "Upgrade"
    }

    public var body: some View {
        NavigationStack {
            List {
                // In-Car Experience Section
                Section(header: Text("In-Car Experience")) {
                    Button(action: { showCarMode = true }) {
                        Label {
                            HStack {
                                Text("Launch Car Mode")
                                Spacer()
                                Text("Hands-Free")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "car.fill")
                                .foregroundColor(CarTVTheme.accent)
                        }
                    }
                    
                    NavigationLink(destination: CastToCarView()) {
                        Label {
                            HStack {
                                Text("Screen Mirroring & AirPlay")
                                Spacer()
                                Text("Car Screen")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "airplayvideo")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Media Sources & Playlists
                Section(header: Text("Media Sources")) {
                    NavigationLink(destination: ManageSourcesView()) {
                        Label {
                            HStack {
                                Text("Manage Sources")
                                Spacer()
                                Text("\(playlistStore.sources.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "server.rack")
                                .foregroundColor(CarTVTheme.accent)
                        }
                    }
                    
                    Button(action: { showAddSource = true }) {
                        Label("Add Media Source (M3U / Xtream / Server)", systemImage: "plus.circle.fill")
                            .foregroundColor(CarTVTheme.accent)
                    }
                    
                    Button(action: { showLocalImport = true }) {
                        Label("Import Local Videos", systemImage: "folder.fill")
                            .foregroundColor(.blue)
                    }
                }

                // Pro
                Section(header: Text("Pro")) {
                    NavigationLink(destination: ProPaywallView()) {
                        Label {
                            HStack {
                                Text("DrivePlay Pro")
                                Spacer()
                                Text(proStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(CarTVTheme.accent)
                        }
                    }
                }
                
                // Privacy & Security
                Section(header: Text("Privacy & Security")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private by Design")
                            .font(.system(size: 15, weight: .semibold))
                        Text("CarTV does not have user accounts. All playlists, server addresses, and credentials stay securely in your device's sandbox. Stream connections are made directly to your providers.")
                            .font(.system(size: 13))
                            .foregroundColor(CarTVTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddSource) {
                AddSourceSheet()
            }
            .fullScreenCover(isPresented: $showCarMode) {
                CarModeDashboardView()
            }
            .sheet(isPresented: $showLocalImport) {
                LocalImportView()
            }
        }
    }
}
