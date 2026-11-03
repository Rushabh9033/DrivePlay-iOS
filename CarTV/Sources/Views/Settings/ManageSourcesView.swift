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
                    
                    Text(source.urlString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    let source = playlistStore.sources[idx]
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
}
