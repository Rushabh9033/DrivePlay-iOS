import UIKit

extension InCarAutomotiveController {
    // MARK: - Top Bar Setup (Matching media_1793439755880_e1326db1.png)
    
    func setupTopBar() {
        topBarView.backgroundColor = bgDark
        view.addSubview(topBarView)
        
        capsuleTabBar.backgroundColor = pillDark
        capsuleTabBar.layer.cornerRadius = 17
        capsuleTabBar.layer.masksToBounds = true
        topBarView.addSubview(capsuleTabBar)
        
        let titles = ["Home", "Favorites", "Cast", "Browser"]
        let tabStack = UIStackView()
        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 0
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        capsuleTabBar.addSubview(tabStack)
        
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: capsuleTabBar.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: capsuleTabBar.bottomAnchor),
            tabStack.leadingAnchor.constraint(equalTo: capsuleTabBar.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: capsuleTabBar.trailingAnchor)
        ])
        
        for (idx, title) in titles.enumerated() {
            let btn = UIButton(type: .custom)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
            btn.setTitleColor(UIColor(white: 0.85, alpha: 1.0), for: .normal)
            btn.layer.cornerRadius = 15
            btn.layer.masksToBounds = true
            btn.tag = idx
            btn.addTarget(self, action: #selector(handleTabTap(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
        
        // Search circular button on right of capsule
        searchButton.backgroundColor = pillDark
        searchButton.layer.cornerRadius = 17
        searchButton.layer.masksToBounds = true
        let magConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        let magImg = UIImage(systemName: "magnifyingglass", withConfiguration: magConfig)
        searchButton.setImage(magImg, for: .normal)
        searchButton.tintColor = .white
        searchButton.addTarget(self, action: #selector(handleSearchTap), for: .touchUpInside)
        topBarView.addSubview(searchButton)
    }
    
    @objc private func handleTabTap(_ sender: UIButton) {
        guard let tab = ActiveTab(rawValue: sender.tag) else { return }
        switchTab(tab)
    }
    
    public func switchTab(_ tab: ActiveTab) {
        self.currentTab = tab
        
        for (idx, btn) in tabButtons.enumerated() {
            if idx == tab.rawValue {
                btn.backgroundColor = carGreen
                btn.setTitleColor(.white, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .bold)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor(white: 0.85, alpha: 1.0), for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
            }
        }
        
        homeContainer.isHidden = (tab != .home)
        favoritesContainer.isHidden = (tab != .favorites)
        castContainer.isHidden = (tab != .cast)
        
        if tab == .browser {
            if let wv = webView, !wv.isHidden {
                browserContainer.isHidden = false
            } else {
                openBrowser(url: URL(string: "https://m.youtube.com")!)
            }
        } else {
            browserContainer.isHidden = true
        }
        
        // When Cast tab is selected, show the mirror view directly
        if tab == .cast {
            showMirror()
        } else if tab != .cast && isMirroringActive {
            // Stop capture when leaving Cast tab
            handleMirrorClose()
        }
    }
    
}
