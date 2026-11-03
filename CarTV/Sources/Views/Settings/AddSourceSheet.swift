import SwiftUI

public struct AddSourceSheet: View {
    @ObservedObject var playlistStore = PlaylistStore.shared
    @Environment(\.dismiss) var dismiss
    
    // 0: M3U, 1: Xtream Codes, 2: Media Server
    @State private var selectedTab: Int = 0
    
    // Form fields
    @State private var sourceName: String = ""
    @State private var urlString: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    
    // Media Server sub-type (0: Jellyfin/Emby, 1: Plex)
    @State private var serverType: Int = 0
    @State private var plexPinCode: String?
    @State private var plexPinId: Int?
    @State private var isCheckingPlex: Bool = false
    @State private var plexStatusMessage: String?
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Source Type Selector (Clean 3-Segment Picker)
                Section {
                    Picker("Source Type", selection: $selectedTab) {
                        Text("M3U Playlist").tag(0)
                        Text("Xtream Codes").tag(1)
                        Text("Media Server").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Select Provider Type")
                }
                
                // M3U Playlist Form
                if selectedTab == 0 {
                    Section {
                        TextField("Name (e.g. Sports & News)", text: $sourceName)
                        
                        HStack(spacing: 8) {
                            TextField("Playlist URL (M3U or M3U8)", text: $urlString)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                            
                            if !urlString.isEmpty {
                                Button {
                                    urlString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button {
                                if let paste = UIPasteboard.general.string {
                                    urlString = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } header: {
                        Text("M3U & M3U8 Playlist Information")
                    } footer: {
                        Text("Supports remote .m3u, .m3u8, and HLS streaming playlists provided by your IPTV service.")
                    }
                }
                
                // Xtream Codes Form
                if selectedTab == 1 {
                    Section {
                        TextField("Provider Name (optional)", text: $sourceName)
                        
                        HStack(spacing: 8) {
                            TextField("Server Address (e.g. http://server.com:8080)", text: $urlString)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                            
                            Button {
                                if let paste = UIPasteboard.general.string {
                                    urlString = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        
                        SecureField("Password", text: $password)
                    } header: {
                        Text("Xtream Codes Credentials")
                    } footer: {
                        Text("Connect securely to your Xtream Codes IPTV provider using your server address and account details.")
                    }
                }
                
                // Media Server (Jellyfin / Emby / Plex)
                if selectedTab == 2 {
                    Section {
                        Picker("Server Software", selection: $serverType) {
                            Text("Jellyfin / Emby").tag(0)
                            Text("Plex").tag(1)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Media Server Type")
                    }
                    
                    if serverType == 0 {
                        Section {
                            TextField("Server Name (optional)", text: $sourceName)
                            
                            HStack(spacing: 8) {
                                TextField("Server URL (http://192.168.1.100:8096)", text: $urlString)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .keyboardType(.URL)
                                
                                Button {
                                    if let paste = UIPasteboard.general.string {
                                        urlString = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            
                            SecureField("Password", text: $password)
                        } header: {
                            Text("Jellyfin / Emby Login")
                        } footer: {
                            Text("Connect to your home media server to stream your video library.")
                        }
                    } else {
                        // Plex Account Link Form
                        Section {
                            if let code = plexPinCode {
                                VStack(spacing: 14) {
                                    Text("Open plex.tv/link in Safari and enter this 4-digit code:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                                    // Clean 4-character code display
                                    HStack(spacing: 12) {
                                        ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                                            Text(String(char))
                                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                                .frame(width: 44, height: 52)
                                                .background(Color(UIColor.secondarySystemFill))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    
                                    Link(destination: URL(string: "https://plex.tv/link")!) {
                                        Label("Open plex.tv/link", systemImage: "safari")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button {
                                        checkPlexAuth()
                                    } label: {
                                        if isCheckingPlex {
                                            HStack(spacing: 8) {
                                                ProgressView()
                                                Text("Verifying Link...")
                                            }
                                        } else {
                                            Text("Check Authorization Status")
                                        }
                                    }
                                    .font(.headline)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isCheckingPlex)
                                    
                                    if let msg = plexStatusMessage {
                                        Text(msg)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            } else {
                                Button {
                                    startPlexAuth()
                                } label: {
                                    HStack {
                                        Image(systemName: "link.circle.fill")
                                            .foregroundColor(.yellow)
                                        Text("Generate 4-Digit Plex Link PIN")
                                            .font(.headline)
                                    }
                                }
                            }
                        } header: {
                            Text("Official Plex Account Link")
                        } footer: {
                            Text("Plex generates an official 4-digit code. Link it once on plex.tv/link to stream your Plex media.")
                        }
                    }
                }
                
                // Error Alert Banner
                if let err = playlistStore.errorMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Submit Button
                if selectedTab != 2 || serverType == 0 {
                    Section {
                        Button(action: addSource) {
                            if isSubmitting {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Verifying & Adding Source...")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Add Media Source")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .listRowBackground(isSubmitDisabled ? Color.gray.opacity(0.3) : Color.accentColor)
                        .disabled(isSubmitDisabled || isSubmitting)
                    }
                }
            }
            .navigationTitle("Add Media Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if selectedTab != 2 || serverType == 0 {
                        Button("Add") { addSource() }
                            .font(.headline)
                            .foregroundColor(isSubmitDisabled ? .secondary : Color.accentColor)
                            .disabled(isSubmitDisabled || isSubmitting)
                    }
                }
            }
        }
    }
    
    private var isSubmitDisabled: Bool {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addSource() {
        guard !isSubmitDisabled else { return }
        isSubmitting = true
        Task {
            if selectedTab == 0 {
                await playlistStore.addM3USource(name: sourceName, urlString: urlString)
            } else if selectedTab == 1 {
                await playlistStore.addXtreamSource(name: sourceName, serverUrl: urlString, username: username, pass: password)
            } else if selectedTab == 2 && serverType == 0 {
                await playlistStore.addJellyfinSource(name: sourceName, serverUrl: urlString, username: username, pass: password)
            }
            isSubmitting = false
            if playlistStore.errorMessage == nil {
                dismiss()
            }
        }
    }
    
    private func startPlexAuth() {
        Task {
            let client = PlexClient()
            if let pin = try? await client.createPin() {
                self.plexPinCode = pin.code
                self.plexPinId = pin.id
                self.plexStatusMessage = "Waiting for approval on plex.tv/link..."
            }
        }
    }
    
    private func checkPlexAuth() {
        guard let id = plexPinId else { return }
        isCheckingPlex = true
        Task {
            let client = PlexClient()
            if let token = try? await client.checkPin(pinId: id), !token.isEmpty {
                // Pin authorized! Add Plex source
                let source = PlaylistSource(
                    name: "Plex Server",
                    type: .plex,
                    urlString: "https://plex.tv",
                    serverToken: token
                )
                playlistStore.addSource(source)
                isCheckingPlex = false
                dismiss()
            } else {
                isCheckingPlex = false
                self.plexStatusMessage = "PIN not authorized yet. Enter \(plexPinCode ?? "") on plex.tv/link, then click check."
            }
        }
    }
}
