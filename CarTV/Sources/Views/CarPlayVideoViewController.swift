import UIKit
import AVKit
import WebKit
import Combine
import ReplayKit

// MARK: - In-Car Automotive Root Controller
public final class InCarAutomotiveController: UIViewController, WKNavigationDelegate, UITextFieldDelegate, CarPlayFloatingKeyboardDelegate {
    
    // MARK: - Enums
    public enum ActiveTab: Int {
        case home = 0
        case favorites = 1
        case cast = 2
        case browser = 3
    }

    /// What the shelves currently show. Building a shelf is expensive, so it is
    /// only rebuilt when this actually changes.
    struct ShelfSignature: Equatable {
        let channelIDs: [UUID]
        let favoriteIDs: [UUID]

        init(channels: [Channel], favorites: [Channel]) {
            channelIDs = channels.map(\.id)
            favoriteIDs = favorites.map(\.id)
        }
    }
    
    // MARK: - Properties
    public let isInteractive: Bool
    public internal(set) var currentTab: ActiveTab = .home
    var cancellables = Set<AnyCancellable>()

    public init(isInteractive: Bool = true) {
        self.isInteractive = isInteractive
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.isInteractive = true
        super.init(coder: coder)
    }
    /// Channel logos are cached by URL. Without a cost limit the cache grows with
    /// every logo ever seen and is never evicted.
    static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024 // 32 MB
        return cache
    }()
    
    // Theme Colors
    let bgDark = UIColor(red: 0.086, green: 0.090, blue: 0.106, alpha: 1.0) // #16171B
    let cardDark = UIColor(red: 0.149, green: 0.157, blue: 0.180, alpha: 1.0) // #26282E
    let pillDark = UIColor(red: 0.133, green: 0.141, blue: 0.165, alpha: 0.95) // #22242A
    let carGreen = UIColor(red: 0.0, green: 0.816, blue: 0.400, alpha: 1.0) // #00D066
    let mutedText = UIColor(red: 0.58, green: 0.60, blue: 0.65, alpha: 1.0)
    
    // UI - Top Bar (Matching media_1793439755880_e1326db1.png)
    let topBarView = UIView()
    let capsuleTabBar = UIView()
    var tabButtons: [UIButton] = []
    let searchButton = UIButton(type: .custom)
    
    // UI - Main Content Containers
    let contentArea = UIView()
    let homeContainer = UIView()
    let favoritesContainer = UIView()
    let castContainer = UIView()
    public let browserContainer = UIView()
    
    // Home Shelves (Horizontal Sections)
    let homeScrollView = UIScrollView()
    let homeShelvesStack = UIStackView()
    var homeEmptyView = UIView()
    let homeScrollUpBtn = UIButton(type: .custom)
    let homeScrollDownBtn = UIButton(type: .custom)
    
    // Favorites
    let favScrollView = UIScrollView()
    let favShelvesStack = UIStackView()
    var favEmptyView = UIView()
    
    // Callbacks
    public var onCloseBrowser: (() -> Void)?
    public var onSelectCategoryGrid: ((String, [Channel]) -> Void)?
    
    // Fullscreen Live Video Player Layer & Overlay
    let videoContainer = UIView()
    let playerVC = AVPlayerViewController()
    var playerLayer: AVPlayerLayer?
    let videoOverlay = UIView()
    let videoTitleLabel = UILabel()
    let videoSubtitleLabel = UILabel()
    let videoLiveDot = UIView()
    let videoLiveBadge = UILabel()
    let videoCloseButton = UIButton(type: .system)
    
    // Browser Components (Exact White Native Browser matching media_1793439175506_5de663a5.png)
    var webView: WKWebView?
    let browserToolbar = UIView()
    let browserCloseBtn = UIButton(type: .custom)
    let browserBackBtn = UIButton(type: .custom)
    let browserSidebarBtn = UIButton(type: .custom)
    let browserHomeBtn = UIButton(type: .custom)
    let browserUrlContainer = UIView()
    let browserUrlLabel = UILabel()
    public let browserUrlTextField = UITextField()
    let browserReloadBtn = UIButton(type: .custom)
    let browserTabsBtn = UIButton(type: .custom)
    let browserMoreBtn = UIButton(type: .custom)
    let browserCastBtn = UIButton(type: .custom)
    let browserFullscreenBtn = UIButton(type: .custom)
    let browserAABtn = UIButton(type: .custom)
    let browserHomeScrollView = UIScrollView()
    let browserAppsStack = UIStackView()
    let browserScrollUpBtn = UIButton(type: .custom)
    let browserScrollDownBtn = UIButton(type: .custom)
    let browserProgressView = UIProgressView(progressViewStyle: .bar)
    let browserKeyboardToggleBtn = UIButton(type: .custom)
    
    // In-App Floating Keyboard for Car Display (Apple Maps style)
    public let floatingKeyboard = CarPlayFloatingKeyboardView()
    public var isFloatingKeyboardVisible = false
    
    // Screen Mirroring Overlay
    let mirrorContainer = UIView()
    let mirrorIconView = UIImageView()
    let mirrorTitleLabel = UILabel()
    let mirrorSubtitleLabel = UILabel()
    let mirrorCloseBtn = UIButton(type: .system)
    // Live screen capture layer for mirroring
    let mirrorSampleLayer = AVSampleBufferDisplayLayer()
    /// Whether a screen capture is running. Internal so the scene teardown path
    /// and the tests can see it.
    var isMirroringActive = false
    /// The content the shelves were last built from.
    var renderedShelfSignature: ShelfSignature?
    
    // Search Overlay
    let searchOverlay = UIView()
    let searchBarField = UITextField()
    let searchCancelBtn = UIButton(type: .system)
    let searchResultsScrollView = UIScrollView()
    let searchResultsStack = UIStackView()

    /// True while the browser has reloaded the page once after its web process
    /// died — a second death is the page's own fault and is not reloaded again.
    var hasReloadedAfterCrash = false
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgDark
        view.isHidden = false
        
        setupTopBar()
        setupContentArea()
        setupHomeView()
        setupFavoritesView()
        setupCastView()
        setupBrowserView()
        setupVideoContainer()
        setupMirrorContainer()
        setupSearchOverlay()

        // The header of a shelf opens the channels of that category. A host may
        // take that over; by default the list opens here.
        onSelectCategoryGrid = { [weak self] title, channels in
            self?.showCategory(title, channels: channels)
        }

        if PlaylistStore.shared.channels.isEmpty {
            PlaylistStore.shared.addSampleM3USource()
        }

        switchTab(.home)
        observeState()
        refreshChannels()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var b = view.bounds
        if (b.width <= 0 || b.height <= 0), let win = view.window, win.bounds.width > 0 {
            b = win.bounds
            view.frame = b
        }
        guard b.width > 0 && b.height > 0 else { return }
        
        let safeLeft = view.safeAreaInsets.left
        let safeRight = view.safeAreaInsets.right
        let availW = max(200, b.width - safeLeft - safeRight)
        
        // 1. Top bar layout (centered within safe automotive viewport)
        topBarView.frame = CGRect(x: 0, y: 0, width: b.width, height: 48)
        
        let capsuleW: CGFloat = min(320, availW - 50)
        let capsuleH: CGFloat = 34
        let capsuleX = safeLeft + (availW - capsuleW) / 2
        capsuleTabBar.frame = CGRect(x: capsuleX, y: 7, width: capsuleW, height: capsuleH)
        searchButton.frame = CGRect(x: capsuleTabBar.frame.maxX + 10, y: 7, width: 34, height: 34)
        
        // 2. Content area below top bar
        contentArea.frame = CGRect(x: 0, y: 48, width: b.width, height: b.height - 48)
        homeContainer.frame = contentArea.bounds
        favoritesContainer.frame = contentArea.bounds
        castContainer.frame = contentArea.bounds
        
        homeScrollView.frame = homeContainer.bounds
        favScrollView.frame = favoritesContainer.bounds
        
        // Home floating chevrons. homeContainer is inset by the 48pt top bar, so its
        // coordinate space starts below the bar — offsetting by 48 here would push the
        // up-chevron down and hang the down-chevron off the bottom of the screen.
        let homeUpY: CGFloat = 16
        let homeDownY: CGFloat = homeContainer.bounds.height - 48
        let safeTrailingX = max(b.width - 44, b.width - safeRight - 40)
        homeScrollUpBtn.frame = CGRect(x: safeTrailingX, y: homeUpY, width: 32, height: 32)
        homeScrollDownBtn.frame = CGRect(x: safeTrailingX, y: homeDownY, width: 32, height: 32)
        
        // 3. Browser layout (covers entire screen)
        browserContainer.frame = b
        let barH: CGFloat = browserToolbar.isHidden ? 0 : 44
        browserToolbar.frame = CGRect(x: 0, y: 0, width: b.width, height: barH)
        browserProgressView.frame = CGRect(x: 0, y: barH - 2, width: b.width, height: 2)
        browserHomeScrollView.frame = CGRect(x: 0, y: barH, width: b.width, height: b.height - barH)
        webView?.frame = CGRect(x: 0, y: barH, width: b.width, height: b.height - barH)
        
        // Browser floating chevrons
        let bUpY: CGFloat = barH + 18
        let bDownY: CGFloat = b.height - 54
        browserScrollUpBtn.frame = CGRect(x: safeTrailingX, y: bUpY, width: 32, height: 32)
        browserScrollDownBtn.frame = CGRect(x: safeTrailingX, y: bDownY, width: 32, height: 32)
        
        // 4. Fullscreen Video Container, playerVC & AVPlayerLayer
        videoContainer.frame = b
        playerVC.view.frame = videoContainer.bounds
        playerLayer?.frame = videoContainer.bounds
        
        mirrorContainer.frame = b
        mirrorSampleLayer.frame = mirrorContainer.bounds
        searchOverlay.frame = b
        
        // 5. In-App Floating Keyboard Layout (Apple Maps in-car style)
        let kbW: CGFloat = min(b.width - safeLeft - safeRight - 16, 680)
        let kbH: CGFloat = min(215, max(160, b.height * 0.58))
        let kbX: CGFloat = safeLeft + ((b.width - safeLeft - safeRight) - kbW) / 2
        let kbY: CGFloat = isFloatingKeyboardVisible ? (b.height - kbH) : b.height
        floatingKeyboard.frame = CGRect(x: kbX, y: kbY, width: kbW, height: kbH)
        if isFloatingKeyboardVisible {
            browserContainer.bringSubviewToFront(floatingKeyboard)
            view.bringSubviewToFront(floatingKeyboard)
        }
        
        if let win = view.window {
            win.bringSubviewToFront(view)
        }
    }
    
    // MARK: - In-App Floating Keyboard Controls
    
    public func showFloatingKeyboard() {
        isFloatingKeyboardVisible = true
        floatingKeyboard.isHidden = false
        floatingKeyboard.layer.zPosition = 1000
        browserContainer.bringSubviewToFront(floatingKeyboard)
        view.bringSubviewToFront(floatingKeyboard)
        
        var b = self.view.bounds
        if (b.width <= 0 || b.height <= 0), let win = view.window ?? view.superview?.window {
            b = win.bounds
        }
        if b.width <= 0 || b.height <= 0 {
            b = CGRect(x: 0, y: 0, width: 800, height: 480)
        }
        
        let safeLeft = max(self.view.safeAreaInsets.left, 0)
        let safeRight = max(self.view.safeAreaInsets.right, 0)
        let kbW: CGFloat = min(b.width - safeLeft - safeRight - 16, 680)
        let kbH: CGFloat = min(215, max(160, b.height * 0.58))
        let kbX: CGFloat = safeLeft + ((b.width - safeLeft - safeRight) - kbW) / 2
        
        if self.floatingKeyboard.frame.origin.y >= b.height || self.floatingKeyboard.frame.width <= 0 {
            self.floatingKeyboard.frame = CGRect(x: kbX, y: b.height, width: kbW, height: kbH)
        }
        
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.floatingKeyboard.frame = CGRect(x: kbX, y: b.height - kbH, width: kbW, height: kbH)
            self.floatingKeyboard.alpha = 1.0
        }
    }

    public func hideFloatingKeyboard() {
        guard isFloatingKeyboardVisible else { return }
        isFloatingKeyboardVisible = false
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            let b = self.view.bounds
            self.floatingKeyboard.frame.origin.y = b.height
            self.floatingKeyboard.alpha = 0.0
        }, completion: { _ in
            self.floatingKeyboard.isHidden = true
        })
    }

    public func toggleFloatingKeyboard() {
        if isFloatingKeyboardVisible {
            hideFloatingKeyboard()
        } else {
            showFloatingKeyboard()
        }
    }
    
    // MARK: - CarPlayFloatingKeyboardDelegate
    
    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didEnterText text: String) {
        let current = browserUrlTextField.text ?? ""
        let updated = current + text
        browserUrlTextField.text = updated
        browserUrlLabel.text = updated
    }
    
    public func floatingKeyboardDidTapDelete(_ keyboard: CarPlayFloatingKeyboardView) {
        var current = browserUrlTextField.text ?? ""
        if !current.isEmpty {
            current.removeLast()
            browserUrlTextField.text = current
            browserUrlLabel.text = current.isEmpty ? "Enter a URL or search" : current
        }
    }
    
    public func floatingKeyboardDidTapClear(_ keyboard: CarPlayFloatingKeyboardView) {
        browserUrlTextField.text = ""
        browserUrlLabel.text = "Enter a URL or search"
    }
    
    public func floatingKeyboardDidTapGo(_ keyboard: CarPlayFloatingKeyboardView) {
        hideFloatingKeyboard()
        submitCurrentBrowserUrl()
    }
    
    public func floatingKeyboardDidTapDismiss(_ keyboard: CarPlayFloatingKeyboardView) {
        hideFloatingKeyboard()
    }
    
    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didSelectQuickItem text: String) {
        if text.contains(".") && !text.hasPrefix(".") {
            let target = text.hasPrefix("http") ? text : "https://\(text)"
            browserUrlTextField.text = text
            browserUrlLabel.text = text
            hideFloatingKeyboard()
            if let u = URL(string: target) {
                openBrowser(url: u)
            }
        } else {
            let current = browserUrlTextField.text ?? ""
            let updated: String
            if text == "https://" && current.isEmpty {
                updated = text
            } else {
                updated = current + text
            }
            browserUrlTextField.text = updated
            browserUrlLabel.text = updated
        }
    }
    
    public func submitCurrentBrowserUrl() {
        let query = browserUrlTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return }
        
        let targetURL: URL
        if query.hasPrefix("http://") || query.hasPrefix("https://") {
            targetURL = URL(string: query) ?? URL(string: "https://www.google.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        } else if query.contains(".") && !query.contains(" ") {
            targetURL = URL(string: "https://\(query)") ?? URL(string: "https://www.google.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        } else {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")!
        }
        
        openBrowser(url: targetURL)
    }
}
