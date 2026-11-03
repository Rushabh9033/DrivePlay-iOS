import UIKit

extension InCarAutomotiveController {
    // MARK: - Content Area Setup
    
    func setupContentArea() {
        contentArea.backgroundColor = bgDark
        view.addSubview(contentArea)
        
        contentArea.addSubview(homeContainer)
        contentArea.addSubview(favoritesContainer)
        contentArea.addSubview(castContainer)
        view.addSubview(browserContainer)
    }
    
    // MARK: - Home Tab (Shelves matching media_1793439755880_e1326db1.png)
    
    func setupHomeView() {
        homeContainer.backgroundColor = bgDark
        
        homeScrollView.alwaysBounceVertical = true
        homeScrollView.showsVerticalScrollIndicator = false
        homeContainer.addSubview(homeScrollView)
        
        homeShelvesStack.axis = .vertical
        homeShelvesStack.spacing = 16
        homeShelvesStack.translatesAutoresizingMaskIntoConstraints = false
        homeScrollView.addSubview(homeShelvesStack)
        
        NSLayoutConstraint.activate([
            homeShelvesStack.topAnchor.constraint(equalTo: homeScrollView.topAnchor, constant: 10),
            homeShelvesStack.bottomAnchor.constraint(equalTo: homeScrollView.bottomAnchor, constant: -24),
            homeShelvesStack.leadingAnchor.constraint(equalTo: homeScrollView.leadingAnchor, constant: 16),
            homeShelvesStack.trailingAnchor.constraint(equalTo: homeScrollView.trailingAnchor, constant: -16),
            homeShelvesStack.widthAnchor.constraint(equalTo: homeScrollView.widthAnchor, constant: -32)
        ])
        
        homeEmptyView = buildEmptyState(
            iconName: "tv",
            title: "Nothing to show",
            subtitle: "Add sources on your iPhone first",
            iconColor: mutedText
        )
        homeContainer.addSubview(homeEmptyView)
        centerInView(homeEmptyView, parent: homeContainer)
        
        // Floating chevrons on Home
        let upCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        homeScrollUpBtn.setImage(UIImage(systemName: "chevron.up", withConfiguration: upCfg), for: .normal)
        homeScrollUpBtn.tintColor = UIColor(white: 0.6, alpha: 1.0)
        homeScrollUpBtn.backgroundColor = UIColor(white: 0.18, alpha: 0.85)
        homeScrollUpBtn.layer.cornerRadius = 16
        homeScrollUpBtn.layer.masksToBounds = true
        homeScrollUpBtn.addTarget(self, action: #selector(handleHomeScrollUp), for: .touchUpInside)
        homeContainer.addSubview(homeScrollUpBtn)
        
        homeScrollDownBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: upCfg), for: .normal)
        homeScrollDownBtn.tintColor = UIColor(white: 0.6, alpha: 1.0)
        homeScrollDownBtn.backgroundColor = UIColor(white: 0.18, alpha: 0.85)
        homeScrollDownBtn.layer.cornerRadius = 16
        homeScrollDownBtn.layer.masksToBounds = true
        homeScrollDownBtn.addTarget(self, action: #selector(handleHomeScrollDown), for: .touchUpInside)
        homeContainer.addSubview(homeScrollDownBtn)
    }
    
    @objc private func handleHomeScrollUp() {
        let y = max(0, homeScrollView.contentOffset.y - 180)
        homeScrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }
    
    @objc private func handleHomeScrollDown() {
        let maxOff = max(0, homeScrollView.contentSize.height - homeScrollView.bounds.height)
        let y = min(maxOff, homeScrollView.contentOffset.y + 180)
        homeScrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }
    
    // MARK: - Favorites Tab
    
    func setupFavoritesView() {
        favoritesContainer.backgroundColor = bgDark
        
        favScrollView.alwaysBounceVertical = true
        favScrollView.showsVerticalScrollIndicator = false
        favoritesContainer.addSubview(favScrollView)
        
        favShelvesStack.axis = .vertical
        favShelvesStack.spacing = 16
        favShelvesStack.translatesAutoresizingMaskIntoConstraints = false
        favScrollView.addSubview(favShelvesStack)
        
        NSLayoutConstraint.activate([
            favShelvesStack.topAnchor.constraint(equalTo: favScrollView.topAnchor, constant: 10),
            favShelvesStack.bottomAnchor.constraint(equalTo: favScrollView.bottomAnchor, constant: -24),
            favShelvesStack.leadingAnchor.constraint(equalTo: favScrollView.leadingAnchor, constant: 16),
            favShelvesStack.trailingAnchor.constraint(equalTo: favScrollView.trailingAnchor, constant: -16),
            favShelvesStack.widthAnchor.constraint(equalTo: favScrollView.widthAnchor, constant: -32)
        ])
        
        favEmptyView = buildEmptyState(
            iconName: "heart",
            title: "Nothing saved yet",
            subtitle: "Touch and hold any channel or poster to keep it here.",
            iconColor: mutedText
        )
        favoritesContainer.addSubview(favEmptyView)
        centerInView(favEmptyView, parent: favoritesContainer)
    }
    
    // MARK: - Cast Tab
    
    func setupCastView() {
        castContainer.backgroundColor = bgDark
        
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        castContainer.addSubview(wrapper)
        
        let tvIcon = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        tvIcon.image = UIImage(systemName: "tv", withConfiguration: config)
        tvIcon.tintColor = carGreen
        tvIcon.contentMode = .scaleAspectFit
        tvIcon.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(tvIcon)
        
        let titleLabel = UILabel()
        titleLabel.text = "Cast anything to this screen"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "On your iPhone, open DrivePlay and go to Discover → Cast to Screen to get started."
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = mutedText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(subtitleLabel)
        
        let badgeView = UIView()
        badgeView.backgroundColor = UIColor(white: 0.16, alpha: 0.8)
        badgeView.layer.cornerRadius = 14
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(badgeView)
        
        let checkIcon = UIImageView()
        let checkConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        checkIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: checkConfig)
        checkIcon.tintColor = carGreen
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(checkIcon)
        
        let badgeLabel = UILabel()
        badgeLabel.text = "DrivePlay (iPhone)"
        badgeLabel.font = .systemFont(ofSize: 13, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        
        NSLayoutConstraint.activate([
            wrapper.centerXAnchor.constraint(equalTo: castContainer.centerXAnchor),
            wrapper.centerYAnchor.constraint(equalTo: castContainer.centerYAnchor, constant: -10),
            wrapper.widthAnchor.constraint(lessThanOrEqualTo: castContainer.widthAnchor, constant: -40),
            
            tvIcon.topAnchor.constraint(equalTo: wrapper.topAnchor),
            tvIcon.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            tvIcon.widthAnchor.constraint(equalToConstant: 54),
            tvIcon.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.topAnchor.constraint(equalTo: tvIcon.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            
            badgeView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            badgeView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            badgeView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            badgeView.heightAnchor.constraint(equalToConstant: 28),
            badgeView.leadingAnchor.constraint(equalTo: checkIcon.leadingAnchor, constant: -8),
            badgeView.trailingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 10),
            
            checkIcon.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 16),
            checkIcon.heightAnchor.constraint(equalToConstant: 16),
            
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: checkIcon.trailingAnchor, constant: 6)
        ])
    }
    
    
    // MARK: - Empty State Builder Helper
    
    private func buildEmptyState(iconName: String, title: String, subtitle: String, iconColor: UIColor) -> UIView {
        let empty = UIView()
        empty.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        iconView.image = UIImage(systemName: iconName, withConfiguration: config)
        iconView.tintColor = iconColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        empty.addSubview(iconView)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        empty.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = mutedText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        empty.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: empty.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: empty.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: empty.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: empty.trailingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: empty.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: empty.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: empty.bottomAnchor)
        ])
        
        return empty
    }
    
    private func centerInView(_ subview: UIView, parent: UIView) {
        NSLayoutConstraint.activate([
            subview.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            subview.centerYAnchor.constraint(equalTo: parent.centerYAnchor, constant: -16),
            subview.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor, constant: 20),
            subview.trailingAnchor.constraint(lessThanOrEqualTo: parent.trailingAnchor, constant: -20)
        ])
    }
}
