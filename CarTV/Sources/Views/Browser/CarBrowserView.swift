import SwiftUI
import WebKit

public struct BrowserTab: Identifiable, Equatable {
    public let id = UUID()
    public var title: String
    public var urlString: String
}

public struct CarBrowserView: View {
    @State private var tabs: [BrowserTab] = [
        BrowserTab(title: "YouTube", urlString: "https://m.youtube.com")
    ]
    @State private var currentTabIndex: Int = 0
    @State private var urlInput: String = "https://m.youtube.com"
    @State private var webView = WKWebView()
    
    let presets = [
        ("YouTube", "https://m.youtube.com"),
        ("Twitch", "https://m.twitch.tv"),
        ("Bilibili", "https://m.bilibili.com"),
        ("Vimeo", "https://vimeo.com/watch")
    ]
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top URL Bar
                HStack(spacing: 8) {
                    TextField("Search or enter website", text: $urlInput)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(8)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            loadURL(urlInput)
                        }
                    
                    Button("Go") {
                        loadURL(urlInput)
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(CarTVTheme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                
                // Fast Presets Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.0) { preset in
                            Button(preset.0) {
                                urlInput = preset.1
                                loadURL(preset.1)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(14)
                            .foregroundColor(CarTVTheme.textPrimary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                
                // Web Content
                WebViewRepresentable(webView: webView)
                    .edgesIgnoringSafeArea(.bottom)
            }
            .navigationTitle("In-Car Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if webView.canGoBack { webView.goBack() }
                    }) {
                        Image(systemName: "arrow.backward")
                    }
                }
            }
            .onAppear {
                loadURL(urlInput)
            }
        }
    }
    
    private func loadURL(_ str: String) {
        var formatted = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            formatted = "https://" + formatted
        }
        if let url = URL(string: formatted) {
            webView.load(URLRequest(url: url))
        }
    }
}

public struct WebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView
    
    public func makeUIView(context: Context) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        return webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        uiView.setNeedsLayout()
    }
}
