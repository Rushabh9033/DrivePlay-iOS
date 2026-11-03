import SwiftUI

public struct ManageSourcesView: View {
    @ObservedObject var playlistStore = PlaylistStore.shared
    @State private var showAddSource: Bool = false
    
    public var body: some View {
        List {
            ForEach(playlistStore.sources) { source in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: source.type.iconName)
                            .foregroundColor(CarTVTheme.accent)
                        Text(source.name)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text(source.type.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(displayURL(for: source))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                // The sources are read **before** anything is removed: every
                // removal shortens the array, so the second index would point
                // at the wrong source — or past its end.
                let doomed = indexSet.map { playlistStore.sources[$0] }
                for source in doomed {
                    playlistStore.removeSource(source)
                }
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSource = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceSheet()
        }
    }

    /// The address of a source as it may be shown on the screen.
    ///
    /// The address often carries the password (`http://user:pass@host/…`) and
    /// the list of sources is read over someone's shoulder — so the secrets
    /// are taken out of it.
    private func displayURL(for source: PlaylistSource) -> String {
        guard let url = URL(string: source.urlString) else { return source.urlString }
        let redacted = CredentialRedactor.redact(
            url,
            credentials: SourceCredentials(username: source.username,
                                          password: source.password,
                                          serverToken: source.serverToken)
        )
        return redacted.absoluteString
    }
}
