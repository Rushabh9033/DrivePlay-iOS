import UIKit
import WebKit

extension InCarAutomotiveController {
    // MARK: - Browser View (Exact White Browser matching media_1793439175506_5de663a5.png)
    
    func setupBrowserView() {
        browserContainer.backgroundColor = .white
        browserContainer.isHidden = true
        
        // 1. Top Toolbar (#F9F9FA)
        browserToolbar.backgroundColor = UIColor(red: 0.976, green: 0.976, blue: 0.980, alpha: 1.0)
        browserContainer.addSubview(browserToolbar)
        
        let hairline = UIView()
        hairline.backgroundColor = UIColor(white: 0.88, alpha: 1.0)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        browserToolbar.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: browserToolbar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: browserToolbar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: browserToolbar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        
        let boldCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let medCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let regCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        
        // [✕] Close button
        browserCloseBtn.setImage(UIImage(systemName: "xmark", withConfiguration: boldCfg), for: .normal)
        browserCloseBtn.tintColor = UIColor(white: 0.12, alpha: 1.0)
        browserCloseBtn.addTarget(self, action: #selector(handleBrowserClose), for: .touchUpInside)
        browserToolbar.addSubview(browserCloseBtn)
        
        // [<] Back button
        browserBackBtn.setImage(UIImage(systemName: "chevron.left", withConfiguration: medCfg), for: .normal)
        browserBackBtn.tintColor = UIColor(white: 0.65, alpha: 1.0)
        browserBackBtn.addTarget(self, action: #selector(handleBrowserBack), for: .touchUpInside)
        browserToolbar.addSubview(browserBackBtn)
        
        // [◫] Split / Sidebar button
        browserSidebarBtn.setImage(UIImage(systemName: "rectangle.split.2x1", withConfiguration: regCfg), for: .normal)
        browserSidebarBtn.tintColor = UIColor(white: 0.20, alpha: 1.0)
        browserSidebarBtn.addTarget(self, action: #selector(handleBrowserHome), for: .touchUpInside)
        browserToolbar.addSubview(browserSidebarBtn)
        
        // [🏠] Home button
        browserHomeBtn.setImage(UIImage(systemName: "house.fill", withConfiguration: medCfg), for: .normal)
        browserHomeBtn.tintColor = UIColor(white: 0.15, alpha: 1.0)
        browserHomeBtn.addTarget(self, action: #selector(handleBrowserHome), for: .touchUpInside)
        browserToolbar.addSubview(browserHomeBtn)
        
        // Center Address Capsule: [ Enter a URL or search               ⟳ ]
        browserUrlContainer.backgroundColor = UIColor(red: 0.945, green: 0.945, blue: 0.953, alpha: 1.0)
        browserUrlContainer.layer.cornerRadius = 16
        browserUrlContainer.layer.masksToBounds = true
        browserToolbar.addSubview(browserUrlContainer)
        
        browserUrlTextField.placeholder = "Enter a URL or search"
        browserUrlTextField.font = .systemFont(ofSize: 13, weight: .regular)
        browserUrlTextField.textColor = UIColor(white: 0.15, alpha: 1.0)
        browserUrlTextField.textAlignment = .center
        browserUrlTextField.returnKeyType = .go
        browserUrlTextField.keyboardType = .URL
        browserUrlTextField.autocapitalizationType = .none
        browserUrlTextField.autocorrectionType = .no
        browserUrlTextField.clearButtonMode = .whileEditing
        browserUrlTextField.delegate = self
        browserUrlContainer.addSubview(browserUrlTextField)
        
        browserUrlLabel.text = "Enter a URL or search"
        browserUrlLabel.font = .systemFont(ofSize: 13, weight: .regular)
        browserUrlLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        browserUrlLabel.textAlignment = .center
        browserUrlLabel.isHidden = true
        browserUrlContainer.addSubview(browserUrlLabel)
        
        browserReloadBtn.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .bold)), for: .normal)
        browserReloadBtn.tintColor = UIColor(white: 0.55, alpha: 1.0)
        browserReloadBtn.addTarget(self, action: #selector(handleBrowserReload), for: .touchUpInside)
        browserUrlContainer.addSubview(browserReloadBtn)
        
        let urlTap = UITapGestureRecognizer(target: self, action: #selector(handleAddressBarTap))
        browserUrlContainer.addGestureRecognizer(urlTap)
        browserUrlContainer.isUserInteractionEnabled = true
        
        // Keyboard toggle button [ ⌨ ]
        let kbCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        browserKeyboardToggleBtn.setImage(UIImage(systemName: "keyboard", withConfiguration: kbCfg), for: .normal)
        browserKeyboardToggleBtn.tintColor = UIColor(white: 0.25, alpha: 1.0)
        browserKeyboardToggleBtn.addTarget(self, action: #selector(handleKeyboardToggle), for: .touchUpInside)
        browserToolbar.addSubview(browserKeyboardToggleBtn)
        
        // Right Controls: [ 1 ]  [ ... ]
        let tabImg = makeTabBadgeImage()
        browserTabsBtn.setImage(tabImg, for: .normal)
        browserTabsBtn.addTarget(self, action: #selector(handleBrowserHome), for: .touchUpInside)
        browserToolbar.addSubview(browserTabsBtn)
        
        browserMoreBtn.setImage(UIImage(systemName: "ellipsis", withConfiguration: medCfg), for: .normal)
        browserMoreBtn.tintColor = UIColor(white: 0.20, alpha: 1.0)
        browserMoreBtn.addTarget(self, action: #selector(handleBrowserMore), for: .touchUpInside)
        browserToolbar.addSubview(browserMoreBtn)
        
        browserCastBtn.setImage(UIImage(systemName: "airplayvideo", withConfiguration: regCfg), for: .normal)
        browserCastBtn.tintColor = UIColor(white: 0.55, alpha: 1.0)
        browserCastBtn.addTarget(self, action: #selector(handleBrowserCast), for: .touchUpInside)
        browserCastBtn.isHidden = true
        browserToolbar.addSubview(browserCastBtn)

        browserFullscreenBtn.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: medCfg), for: .normal)
        browserFullscreenBtn.tintColor = UIColor(white: 0.55, alpha: 1.0)
        browserFullscreenBtn.addTarget(self, action: #selector(handleToggleFullscreen), for: .touchUpInside)
        browserFullscreenBtn.isHidden = true
        browserToolbar.addSubview(browserFullscreenBtn)

        browserAABtn.setTitle("AA", for: .normal)
        browserAABtn.setTitleColor(UIColor(white: 0.55, alpha: 1.0), for: .normal)
        browserAABtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        browserAABtn.addTarget(self, action: #selector(handleBrowserTextSize), for: .touchUpInside)
        browserAABtn.isHidden = true
        browserToolbar.addSubview(browserAABtn)
        
        // Layout Toolbar using AutoLayout
        browserCloseBtn.translatesAutoresizingMaskIntoConstraints = false
        browserBackBtn.translatesAutoresizingMaskIntoConstraints = false
        browserSidebarBtn.translatesAutoresizingMaskIntoConstraints = false
        browserHomeBtn.translatesAutoresizingMaskIntoConstraints = false
        browserUrlContainer.translatesAutoresizingMaskIntoConstraints = false
        browserUrlTextField.translatesAutoresizingMaskIntoConstraints = false
        browserUrlLabel.translatesAutoresizingMaskIntoConstraints = false
        browserReloadBtn.translatesAutoresizingMaskIntoConstraints = false
        browserKeyboardToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        browserTabsBtn.translatesAutoresizingMaskIntoConstraints = false
        browserMoreBtn.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            browserCloseBtn.leadingAnchor.constraint(equalTo: browserToolbar.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            browserCloseBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserCloseBtn.widthAnchor.constraint(equalToConstant: 28),
            browserCloseBtn.heightAnchor.constraint(equalToConstant: 28),
            
            browserBackBtn.leadingAnchor.constraint(equalTo: browserCloseBtn.trailingAnchor, constant: 6),
            browserBackBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserBackBtn.widthAnchor.constraint(equalToConstant: 28),
            browserBackBtn.heightAnchor.constraint(equalToConstant: 28),
            
            browserSidebarBtn.leadingAnchor.constraint(equalTo: browserBackBtn.trailingAnchor, constant: 6),
            browserSidebarBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserSidebarBtn.widthAnchor.constraint(equalToConstant: 28),
            browserSidebarBtn.heightAnchor.constraint(equalToConstant: 28),
            
            browserHomeBtn.leadingAnchor.constraint(equalTo: browserSidebarBtn.trailingAnchor, constant: 6),
            browserHomeBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserHomeBtn.widthAnchor.constraint(equalToConstant: 28),
            browserHomeBtn.heightAnchor.constraint(equalToConstant: 28),
            
            browserUrlContainer.leadingAnchor.constraint(equalTo: browserHomeBtn.trailingAnchor, constant: 10),
            browserUrlContainer.trailingAnchor.constraint(equalTo: browserKeyboardToggleBtn.leadingAnchor, constant: -8),
            browserUrlContainer.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserUrlContainer.heightAnchor.constraint(equalToConstant: 32),
            
            browserUrlTextField.leadingAnchor.constraint(equalTo: browserUrlContainer.leadingAnchor, constant: 12),
            browserUrlTextField.trailingAnchor.constraint(equalTo: browserReloadBtn.leadingAnchor, constant: -6),
            browserUrlTextField.centerYAnchor.constraint(equalTo: browserUrlContainer.centerYAnchor),
            browserUrlTextField.heightAnchor.constraint(equalToConstant: 28),
            
            browserUrlLabel.leadingAnchor.constraint(equalTo: browserUrlContainer.leadingAnchor, constant: 14),
            browserUrlLabel.trailingAnchor.constraint(equalTo: browserReloadBtn.leadingAnchor, constant: -6),
            browserUrlLabel.centerYAnchor.constraint(equalTo: browserUrlContainer.centerYAnchor),
            
            browserReloadBtn.trailingAnchor.constraint(equalTo: browserUrlContainer.trailingAnchor, constant: -8),
            browserReloadBtn.centerYAnchor.constraint(equalTo: browserUrlContainer.centerYAnchor),
            browserReloadBtn.widthAnchor.constraint(equalToConstant: 20),
            browserReloadBtn.heightAnchor.constraint(equalToConstant: 20),
            
            browserKeyboardToggleBtn.trailingAnchor.constraint(equalTo: browserTabsBtn.leadingAnchor, constant: -8),
            browserKeyboardToggleBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserKeyboardToggleBtn.widthAnchor.constraint(equalToConstant: 26),
            browserKeyboardToggleBtn.heightAnchor.constraint(equalToConstant: 26),
            
            browserTabsBtn.trailingAnchor.constraint(equalTo: browserMoreBtn.leadingAnchor, constant: -8),
            browserTabsBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserTabsBtn.widthAnchor.constraint(equalToConstant: 24),
            browserTabsBtn.heightAnchor.constraint(equalToConstant: 24),

            browserMoreBtn.trailingAnchor.constraint(equalTo: browserToolbar.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            browserMoreBtn.centerYAnchor.constraint(equalTo: browserToolbar.centerYAnchor),
            browserMoreBtn.widthAnchor.constraint(equalToConstant: 28),
            browserMoreBtn.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        // Progress view
        browserProgressView.progressTintColor = carGreen
        browserProgressView.trackTintColor = .clear
        browserProgressView.isHidden = true
        browserToolbar.addSubview(browserProgressView)
        
        // 2. Browser Catalog Home View (hidden in favor of direct live WebKit)
        browserHomeScrollView.backgroundColor = .white
        browserHomeScrollView.alwaysBounceVertical = true
        browserHomeScrollView.showsVerticalScrollIndicator = false
        browserHomeScrollView.isHidden = true
        browserContainer.addSubview(browserHomeScrollView)
        
        browserAppsStack.axis = .vertical
        browserAppsStack.spacing = 18
        browserAppsStack.translatesAutoresizingMaskIntoConstraints = false
        browserHomeScrollView.addSubview(browserAppsStack)
        
        NSLayoutConstraint.activate([
            browserAppsStack.topAnchor.constraint(equalTo: browserHomeScrollView.topAnchor, constant: 14),
            browserAppsStack.bottomAnchor.constraint(equalTo: browserHomeScrollView.bottomAnchor, constant: -24),
            browserAppsStack.leadingAnchor.constraint(equalTo: browserHomeScrollView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            browserAppsStack.trailingAnchor.constraint(equalTo: browserHomeScrollView.safeAreaLayoutGuide.trailingAnchor, constant: -48),
            browserAppsStack.widthAnchor.constraint(equalTo: browserHomeScrollView.safeAreaLayoutGuide.widthAnchor, constant: -64)
        ])
        
        buildBrowserHomeApps()
        
        // 3. Floating Chevrons on Right Edge of Browser
        let upCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        browserScrollUpBtn.setImage(UIImage(systemName: "chevron.up", withConfiguration: upCfg), for: .normal)
        browserScrollUpBtn.tintColor = UIColor(white: 0.25, alpha: 1.0)
        browserScrollUpBtn.backgroundColor = UIColor(white: 0.96, alpha: 0.90)
        browserScrollUpBtn.layer.cornerRadius = 16
        browserScrollUpBtn.layer.masksToBounds = true
        browserScrollUpBtn.addTarget(self, action: #selector(handleBrowserScrollUp), for: .touchUpInside)
        browserContainer.addSubview(browserScrollUpBtn)
        
        browserScrollDownBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: upCfg), for: .normal)
        browserScrollDownBtn.tintColor = UIColor(white: 0.25, alpha: 1.0)
        browserScrollDownBtn.backgroundColor = UIColor(white: 0.96, alpha: 0.90)
        browserScrollDownBtn.layer.cornerRadius = 16
        browserScrollDownBtn.layer.masksToBounds = true
        browserScrollDownBtn.addTarget(self, action: #selector(handleBrowserScrollDown), for: .touchUpInside)
        browserContainer.addSubview(browserScrollDownBtn)
        
        // 4. In-App Floating Keyboard
        floatingKeyboard.delegate = self
        floatingKeyboard.isHidden = true
        floatingKeyboard.alpha = 0.0
        browserContainer.addSubview(floatingKeyboard)

        if !isInteractive {
            browserKeyboardToggleBtn.isHidden = true
            browserUrlTextField.isUserInteractionEnabled = false
            floatingKeyboard.isHidden = true
        }
    }
    
    private struct BrowserAppDef {
        let name: String
        let url: String
        let bgColor: UIColor
        let hasBorder: Bool
        let textLogo: String?
        let iconName: String?
        let customImage: UIImage?
        let tintColor: UIColor
    }
    
    private func buildBrowserHomeApps() {
        // Section 1: Live & Sports (Famelack, Twitch, Pluto TV)
        let sports = [
            BrowserAppDef(name: "Famelack", url: "https://famelack.com", bgColor: .black, hasBorder: false, textLogo: "fL", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Twitch", url: "https://m.twitch.tv", bgColor: UIColor(red: 0.57, green: 0.27, blue: 1.0, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: nil, customImage: makeTwitchLogo(size: CGSize(width: 32, height: 32)), tintColor: .white),
            BrowserAppDef(name: "Pluto TV", url: "https://pluto.tv", bgColor: UIColor(red: 0.35, green: 0.16, blue: 0.90, alpha: 1.0), hasBorder: false, textLogo: "p▸", iconName: nil, customImage: nil, tintColor: .white)
        ]
        browserAppsStack.addArrangedSubview(buildBrowserSection(title: "Live & Sports", apps: sports))
        
        // Section 2: Games & Tools (Game, Google)
        let tools = [
            BrowserAppDef(name: "Game", url: "https://poki.com", bgColor: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "gamecontroller.fill", customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Google", url: "https://www.google.com", bgColor: .white, hasBorder: true, textLogo: nil, iconName: nil, customImage: makeGoogleLogo(size: CGSize(width: 32, height: 32)), tintColor: .clear)
        ]
        browserAppsStack.addArrangedSubview(buildBrowserSection(title: "Games & Tools", apps: tools))
        
        // Section 3: Video & Music
        let video = [
            BrowserAppDef(name: "YouTube", url: "https://m.youtube.com", bgColor: UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "play.fill", customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Hotstar", url: "https://www.hotstar.com", bgColor: UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "star.fill", customImage: nil, tintColor: UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)),
            BrowserAppDef(name: "Sony LIV", url: "https://www.sonyliv.com", bgColor: .black, hasBorder: false, textLogo: "S", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "ZEE5", url: "https://www.zee5.com", bgColor: UIColor(red: 0.51, green: 0.19, blue: 0.78, alpha: 1.0), hasBorder: false, textLogo: "Z", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Prime Video", url: "https://www.primevideo.com", bgColor: UIColor(red: 0.0, green: 0.66, blue: 0.88, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "play.tv.fill", customImage: nil, tintColor: .white),
            BrowserAppDef(name: "HBO Max", url: "https://max.com", bgColor: .black, hasBorder: false, textLogo: "max", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Peacock", url: "https://www.peacocktv.com", bgColor: .black, hasBorder: false, textLogo: nil, iconName: "sparkles", customImage: nil, tintColor: .systemTeal),
            BrowserAppDef(name: "Paramount+", url: "https://www.paramountplus.com", bgColor: UIColor(red: 0.0, green: 0.39, blue: 1.0, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "mountain.2.fill", customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Crunchyroll", url: "https://www.crunchyroll.com", bgColor: UIColor(red: 0.96, green: 0.46, blue: 0.13, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "circle.circle.fill", customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Rakuten Viki", url: "https://www.viki.com", bgColor: UIColor(red: 0.0, green: 0.70, blue: 1.0, alpha: 1.0), hasBorder: false, textLogo: "V>", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Tubi", url: "https://tubitv.com", bgColor: UIColor(red: 0.98, green: 0.20, blue: 0.0, alpha: 1.0), hasBorder: false, textLogo: "tubi", iconName: nil, customImage: nil, tintColor: .white),
            BrowserAppDef(name: "Plex", url: "https://app.plex.tv", bgColor: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0), hasBorder: false, textLogo: nil, iconName: "play.square.fill", customImage: nil, tintColor: UIColor(red: 0.90, green: 0.60, blue: 0.05, alpha: 1.0))
        ]
        browserAppsStack.addArrangedSubview(buildBrowserSection(title: "Video & Music", apps: video))
    }
    
    private func buildBrowserSection(title: String, apps: [BrowserAppDef]) -> UIView {
        let secView = UIView()
        
        let headerLabel = UILabel()
        headerLabel.text = title
        headerLabel.font = .systemFont(ofSize: 18, weight: .bold)
        headerLabel.textColor = .black
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        secView.addSubview(headerLabel)
        
        let hScrollView = UIScrollView()
        hScrollView.showsHorizontalScrollIndicator = false
        hScrollView.alwaysBounceHorizontal = false
        hScrollView.translatesAutoresizingMaskIntoConstraints = false
        secView.addSubview(hScrollView)
        
        let flowStack = UIStackView()
        flowStack.axis = .horizontal
        flowStack.spacing = 16
        flowStack.translatesAutoresizingMaskIntoConstraints = false
        hScrollView.addSubview(flowStack)
        
        for app in apps {
            let card = UIButton(type: .custom)
            card.translatesAutoresizingMaskIntoConstraints = false
            
            let squircle = UIView()
            squircle.backgroundColor = app.bgColor
            squircle.layer.cornerRadius = 16
            squircle.layer.masksToBounds = true
            squircle.isUserInteractionEnabled = false
            squircle.translatesAutoresizingMaskIntoConstraints = false
            if app.hasBorder {
                squircle.layer.borderWidth = 1
                squircle.layer.borderColor = UIColor(white: 0.88, alpha: 1.0).cgColor
            }
            card.addSubview(squircle)
            
            if let customImg = app.customImage {
                let imgView = UIImageView(image: customImg)
                imgView.contentMode = .scaleAspectFit
                imgView.translatesAutoresizingMaskIntoConstraints = false
                squircle.addSubview(imgView)
                NSLayoutConstraint.activate([
                    imgView.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
                    imgView.centerYAnchor.constraint(equalTo: squircle.centerYAnchor),
                    imgView.widthAnchor.constraint(equalToConstant: 32),
                    imgView.heightAnchor.constraint(equalToConstant: 32)
                ])
            } else if let txt = app.textLogo {
                let logoLbl = UILabel()
                logoLbl.text = txt
                logoLbl.font = .systemFont(ofSize: 22, weight: .heavy)
                logoLbl.textColor = app.tintColor
                logoLbl.textAlignment = .center
                logoLbl.translatesAutoresizingMaskIntoConstraints = false
                squircle.addSubview(logoLbl)
                NSLayoutConstraint.activate([
                    logoLbl.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
                    logoLbl.centerYAnchor.constraint(equalTo: squircle.centerYAnchor)
                ])
            } else if let icon = app.iconName {
                let iconImg = UIImageView()
                let sym = UIImage(systemName: icon) ?? UIImage(systemName: "safari")
                iconImg.image = sym
                iconImg.tintColor = app.tintColor
                iconImg.contentMode = .scaleAspectFit
                iconImg.translatesAutoresizingMaskIntoConstraints = false
                squircle.addSubview(iconImg)
                NSLayoutConstraint.activate([
                    iconImg.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
                    iconImg.centerYAnchor.constraint(equalTo: squircle.centerYAnchor),
                    iconImg.widthAnchor.constraint(equalToConstant: 28),
                    iconImg.heightAnchor.constraint(equalToConstant: 28)
                ])
            }
            
            let nameLbl = UILabel()
            nameLbl.text = app.name
            nameLbl.font = .systemFont(ofSize: 12, weight: .medium)
            nameLbl.textColor = UIColor(white: 0.12, alpha: 1.0)
            nameLbl.textAlignment = .center
            nameLbl.lineBreakMode = .byTruncatingTail
            nameLbl.isUserInteractionEnabled = false
            nameLbl.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(nameLbl)
            
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: 68),
                card.heightAnchor.constraint(equalToConstant: 86),
                
                squircle.topAnchor.constraint(equalTo: card.topAnchor),
                squircle.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                squircle.widthAnchor.constraint(equalToConstant: 60),
                squircle.heightAnchor.constraint(equalToConstant: 60),
                
                nameLbl.topAnchor.constraint(equalTo: squircle.bottomAnchor, constant: 5),
                nameLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                nameLbl.trailingAnchor.constraint(equalTo: card.trailingAnchor)
            ])
            
            card.isUserInteractionEnabled = true
            card.addTarget(self, action: #selector(handleAppCardTap(_:)), for: .touchUpInside)
            card.accessibilityIdentifier = app.url
            
            flowStack.addArrangedSubview(card)
        }
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: secView.topAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: secView.leadingAnchor),
            
            hScrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            hScrollView.leadingAnchor.constraint(equalTo: secView.leadingAnchor),
            hScrollView.trailingAnchor.constraint(equalTo: secView.trailingAnchor),
            hScrollView.heightAnchor.constraint(equalToConstant: 88),
            hScrollView.bottomAnchor.constraint(equalTo: secView.bottomAnchor),
            
            flowStack.topAnchor.constraint(equalTo: hScrollView.topAnchor),
            flowStack.bottomAnchor.constraint(equalTo: hScrollView.bottomAnchor),
            flowStack.leadingAnchor.constraint(equalTo: hScrollView.leadingAnchor),
            flowStack.trailingAnchor.constraint(equalTo: hScrollView.trailingAnchor),
            flowStack.heightAnchor.constraint(equalTo: hScrollView.heightAnchor)
        ])
        
        return secView
    }
    
    @objc private func handleAppCardTap(_ sender: UIButton) {
        guard let urlStr = sender.accessibilityIdentifier, let u = URL(string: urlStr) else { return }
        openBrowser(url: u)
    }
    
    // MARK: - Helpers for Graphics (Twitch, Google, Tab Badge)
    
    private func makeGoogleLogo(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.44
            let lineWidth = radius * 0.42
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.butt)
            
            let red = UIColor(red: 0.918, green: 0.263, blue: 0.208, alpha: 1.0)
            let yellow = UIColor(red: 0.984, green: 0.737, blue: 0.020, alpha: 1.0)
            let green = UIColor(red: 0.204, green: 0.659, blue: 0.325, alpha: 1.0)
            let blue = UIColor(red: 0.259, green: 0.522, blue: 0.957, alpha: 1.0)
            
            // Red arc
            red.setStroke()
            cg.addArc(center: center, radius: radius, startAngle: -.pi * 0.25, endAngle: -.pi * 0.75, clockwise: true)
            cg.strokePath()
            
            // Yellow arc
            yellow.setStroke()
            cg.addArc(center: center, radius: radius, startAngle: -.pi * 0.75, endAngle: -.pi * 1.25, clockwise: true)
            cg.strokePath()
            
            // Green arc
            green.setStroke()
            cg.addArc(center: center, radius: radius, startAngle: -.pi * 1.25, endAngle: -.pi * 1.75, clockwise: true)
            cg.strokePath()
            
            // Blue arc
            blue.setStroke()
            cg.addArc(center: center, radius: radius, startAngle: -.pi * 1.75, endAngle: -.pi * 2.0, clockwise: true)
            cg.strokePath()
            
            // Blue crossbar
            blue.setFill()
            let barRect = CGRect(x: center.x - 2, y: center.y - lineWidth / 2, width: radius + lineWidth / 2 + 2, height: lineWidth)
            cg.fill(barRect)
        }
    }
    
    private func makeTwitchLogo(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rect = CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6)
            let r: CGFloat = 3.5
            
            let bubblePath = UIBezierPath()
            bubblePath.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            bubblePath.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            bubblePath.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: -.pi/2, endAngle: 0, clockwise: true)
            bubblePath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 7 - r))
            bubblePath.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.maxY - 7 - r), radius: r, startAngle: 0, endAngle: .pi/2, clockwise: true)
            bubblePath.addLine(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 7))
            bubblePath.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY))
            bubblePath.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 7))
            bubblePath.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY - 7))
            bubblePath.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.maxY - 7 - r), radius: r, startAngle: .pi/2, endAngle: .pi, clockwise: true)
            bubblePath.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            bubblePath.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: -.pi/2, clockwise: true)
            bubblePath.close()
            
            UIColor.white.setFill()
            bubblePath.fill()
            
            let eyeW: CGFloat = 3
            let eyeH: CGFloat = 8
            let eyeColor = UIColor(red: 0.57, green: 0.27, blue: 1.0, alpha: 1.0)
            eyeColor.setFill()
            cg.fill(CGRect(x: center.x - 6.5, y: center.y - 7, width: eyeW, height: eyeH))
            cg.fill(CGRect(x: center.x + 3.5, y: center.y - 7, width: eyeW, height: eyeH))
        }
    }
    
    private func makeTabBadgeImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let strokeColor = UIColor(white: 0.12, alpha: 1.0)
            strokeColor.setStroke()
            
            // Back square
            let backPath = UIBezierPath(roundedRect: CGRect(x: 5, y: 1, width: 15, height: 15), cornerRadius: 3.5)
            backPath.lineWidth = 1.5
            backPath.stroke()
            
            // Front square
            UIColor(red: 0.976, green: 0.976, blue: 0.980, alpha: 1.0).setFill()
            let frontRect = CGRect(x: 2, y: 5, width: 15, height: 15)
            let frontPath = UIBezierPath(roundedRect: frontRect, cornerRadius: 3.5)
            frontPath.fill()
            frontPath.lineWidth = 1.5
            frontPath.stroke()
            
            // Number "1"
            let str = "1" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: strokeColor
            ]
            let strSize = str.size(withAttributes: attrs)
            let strPt = CGPoint(
                x: frontRect.midX - strSize.width / 2,
                y: frontRect.midY - strSize.height / 2
            )
            str.draw(at: strPt, withAttributes: attrs)
        }
    }
    
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        browserProgressView.isHidden = false
        browserProgressView.setProgress(0.3, animated: true)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasReloadedAfterCrash = false
        browserProgressView.setProgress(1.0, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.browserProgressView.isHidden = true
        }
        browserUrlLabel.text = webView.url?.host ?? webView.url?.absoluteString ?? "Enter a URL or search"
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        browserProgressView.isHidden = true
        NSLog("DRIVEPLAY webView didFail: %@", error.localizedDescription)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        browserProgressView.isHidden = true
        NSLog("DRIVEPLAY webView didFailProvisionalNavigation: %@", error.localizedDescription)
    }
    
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("DRIVEPLAY the page's web process died")
        // A reload **here** is a loop: the page that killed the process is
        // loaded again, kills it again, and the app is taken down with it
        // (the watchdog kills an app that stops answering). One reload is
        // allowed — a page that dies twice is the page's own fault, so the
        // catalogue takes the screen back.
        if hasReloadedAfterCrash {
            hasReloadedAfterCrash = false
            handleBrowserHome()
            return
        }
        hasReloadedAfterCrash = true
        webView.reload()
    }
}
