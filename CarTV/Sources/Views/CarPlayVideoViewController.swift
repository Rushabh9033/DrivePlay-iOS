import UIKit
import AVKit
import WebKit
import Combine
import ReplayKit

// MARK: - In-Car Automotive Root Controller
public final class InCarAutomotiveController: UIViewController, WKNavigationDelegate, UITextFieldDelegate, CarBrowserScreen {
    
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
    public internal(set) var currentTab: ActiveTab = .home
    var cancellables = Set<AnyCancellable>()
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
    let browserReloadBtn = UIButton(type: .custom)
    let browserTabsBtn = UIButton(type: .custom)
    let browserCastBtn = UIButton(type: .custom)
    let browserFullscreenBtn = UIButton(type: .custom)
    let browserAABtn = UIButton(type: .custom)
    let browserHomeScrollView = UIScrollView()
    let browserAppsStack = UIStackView()
    let browserScrollUpBtn = UIButton(type: .custom)
    let browserScrollDownBtn = UIButton(type: .custom)
    let browserProgressView = UIProgressView(progressViewStyle: .bar)
    
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

        switchTab(.home)
        observeState()
        refreshChannels()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
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
        
        if let win = view.window {
            win.bringSubviewToFront(view)
        }
    }
    
}
