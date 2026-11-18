import Foundation

public struct CarBrowserConfiguration {
    /// STRICTLY FALSE: Live video streaming for browsers is permanently prohibited.
    /// CarPlay and in-car automotive displays must use the real, native, interactive WKWebView.
    public static var useLiveRemoteStreamingBrowser: Bool = false
}
