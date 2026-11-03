import UIKit
import Combine

extension InCarAutomotiveController {
    // MARK: - State & Channel Updates (Shelves matching media_1793439755880_e1326db1.png)
    
    func observeState() {
        PlaylistStore.shared.$channels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshChannels()
            }
            .store(in: &cancellables)
        
        PlaybackManager.shared.$player
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in
                self?.playerLayer?.player = p
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest(PlaybackManager.shared.$isPlaying, PlaybackManager.shared.$currentChannel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (playing, ch) in
                if let channel = ch {
                    self?.videoTitleLabel.text = channel.name
                    self?.videoSubtitleLabel.text = channel.groupTitle.isEmpty ? "Live Stream" : channel.groupTitle
                    if playing {
                        self?.showVideo(channel: channel)
                    }
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("MirroringStarted"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showMirror()
            }
            .store(in: &cancellables)
    }
    
    public func refreshChannels() {
        let allChannels = PlaylistStore.shared.channels
        let favs = allChannels.filter { $0.isFavorite }
        
        // The store republishes the same channel list on every save, and the
        // publisher fires once on subscription. Rebuilding the shelves for
        // identical data built every card three times over at launch.
        let signature = ShelfSignature(channels: allChannels, favorites: favs)
        guard renderedShelfSignature != signature else { return }
        renderedShelfSignature = signature
        
        homeEmptyView.isHidden = !allChannels.isEmpty
        homeScrollView.isHidden = allChannels.isEmpty
        
        for v in homeShelvesStack.arrangedSubviews {
            homeShelvesStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        // The favourites are cleared **before** the empty check: a playlist that
        // lost every channel must not leave the old favourites on the screen.
        for v in favShelvesStack.arrangedSubviews {
            favShelvesStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        favEmptyView.isHidden = !favs.isEmpty
        favScrollView.isHidden = favs.isEmpty

        if allChannels.isEmpty { return }
        
        var categoryMap: [String: [Channel]] = [:]
        for ch in allChannels {
            let cat = ch.groupTitle.isEmpty ? "General" : ch.groupTitle
            categoryMap[cat, default: []].append(ch)
        }
        
        // 1. Shelf: "All 10179 items >"
        let allShelf = buildChannelShelf(title: "All", count: allChannels.count, channels: allChannels)
        homeShelvesStack.addArrangedSubview(allShelf)
        
        // 2. Shelves for top categories
        let sortedCategories = categoryMap.keys.sorted { categoryMap[$0]?.count ?? 0 > categoryMap[$1]?.count ?? 0 }
        for cat in sortedCategories.prefix(12) {
            if let catChannels = categoryMap[cat], !catChannels.isEmpty {
                let shelf = buildChannelShelf(title: cat, count: catChannels.count, channels: catChannels)
                homeShelvesStack.addArrangedSubview(shelf)
            }
        }
        
        // Favorites
        if !favs.isEmpty {
            let favShelf = buildChannelShelf(title: "Favorites", count: favs.count, channels: favs)
            favShelvesStack.addArrangedSubview(favShelf)
        }
    }

    /// Opens the channels of a category — the way into the entries the shelf
    /// does not show.
    ///
    /// The shelf carries the first cards of a category; the rest of it has to
    /// be reachable somewhere, and the header says so ("Movies 248 items ›").
    func showCategory(_ title: String, channels: [Channel]) {
        let list = ChannelListViewController(title: title, channels: channels) { [weak self] channel in
            PlaybackManager.shared.play(channel: channel, presentation: .carMode)
            self?.showVideo(channel: channel)
        }
        present(list, animated: true)
    }
    
    private func buildChannelShelf(title: String, count: Int, channels: [Channel]) -> UIView {
        let secView = UIView()
        
        // Header button: "Category [N] items >"
        let headerBtn = UIButton(type: .system)
        headerBtn.contentHorizontalAlignment = .leading
        let titleAttr = NSMutableAttributedString(
            string: "\(title) ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
        let countAttr = NSAttributedString(
            string: "\(count) items ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: mutedText
            ]
        )
        let chevronAttr = NSAttributedString(
            string: "›",
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: UIColor(white: 0.65, alpha: 1.0)
            ]
        )
        titleAttr.append(countAttr)
        titleAttr.append(chevronAttr)
        headerBtn.setAttributedTitle(titleAttr, for: .normal)
        headerBtn.translatesAutoresizingMaskIntoConstraints = false
        headerBtn.addAction(UIAction { [weak self] _ in
            self?.onSelectCategoryGrid?(title, channels)
        }, for: .touchUpInside)
        headerBtn.accessibilityIdentifier = "category:\(title)"
        secView.addSubview(headerBtn)
        
        let hScrollView = UIScrollView()
        hScrollView.showsHorizontalScrollIndicator = false
        hScrollView.alwaysBounceHorizontal = false
        hScrollView.translatesAutoresizingMaskIntoConstraints = false
        secView.addSubview(hScrollView)
        
        let shelfStack = UIStackView()
        shelfStack.axis = .horizontal
        shelfStack.spacing = 14
        shelfStack.translatesAutoresizingMaskIntoConstraints = false
        hScrollView.addSubview(shelfStack)
        
        for channel in channels.prefix(15) {
            let card = buildShelfCard(channel: channel)
            shelfStack.addArrangedSubview(card)
        }
        
        NSLayoutConstraint.activate([
            headerBtn.topAnchor.constraint(equalTo: secView.topAnchor),
            headerBtn.leadingAnchor.constraint(equalTo: secView.leadingAnchor),
            headerBtn.trailingAnchor.constraint(lessThanOrEqualTo: secView.trailingAnchor),
            headerBtn.heightAnchor.constraint(equalToConstant: 26),
            
            hScrollView.topAnchor.constraint(equalTo: headerBtn.bottomAnchor, constant: 8),
            hScrollView.leadingAnchor.constraint(equalTo: secView.leadingAnchor),
            hScrollView.trailingAnchor.constraint(equalTo: secView.trailingAnchor),
            hScrollView.heightAnchor.constraint(equalToConstant: 108),
            hScrollView.bottomAnchor.constraint(equalTo: secView.bottomAnchor),
            
            shelfStack.topAnchor.constraint(equalTo: hScrollView.topAnchor),
            shelfStack.bottomAnchor.constraint(equalTo: hScrollView.bottomAnchor),
            shelfStack.leadingAnchor.constraint(equalTo: hScrollView.leadingAnchor),
            shelfStack.trailingAnchor.constraint(equalTo: hScrollView.trailingAnchor),
            shelfStack.heightAnchor.constraint(equalTo: hScrollView.heightAnchor)
        ])
        
        return secView
    }
    
    private func buildShelfCard(channel: Channel) -> UIView {
        let card = UIButton(type: .custom)
        card.translatesAutoresizingMaskIntoConstraints = false
        
        // Large rounded squircle (#26282E) matching media_1793439755880_e1326db1.png
        let squircle = UIView()
        squircle.backgroundColor = cardDark
        squircle.layer.cornerRadius = 16
        squircle.layer.masksToBounds = true
        squircle.isUserInteractionEnabled = false
        squircle.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(squircle)
        
        let logoImageView = UIImageView()
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.isUserInteractionEnabled = false
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        squircle.addSubview(logoImageView)
        
        // Fallback stylized label inside squircle
        let fallbackLbl = UILabel()
        fallbackLbl.text = String(channel.name.prefix(4))
        fallbackLbl.font = .systemFont(ofSize: 20, weight: .black)
        fallbackLbl.textColor = categoryColor(for: channel.groupTitle)
        fallbackLbl.textAlignment = .center
        fallbackLbl.isUserInteractionEnabled = false
        fallbackLbl.translatesAutoresizingMaskIntoConstraints = false
        squircle.addSubview(fallbackLbl)
        
        NSLayoutConstraint.activate([
            logoImageView.topAnchor.constraint(equalTo: squircle.topAnchor, constant: 10),
            logoImageView.bottomAnchor.constraint(equalTo: squircle.bottomAnchor, constant: -10),
            logoImageView.leadingAnchor.constraint(equalTo: squircle.leadingAnchor, constant: 10),
            logoImageView.trailingAnchor.constraint(equalTo: squircle.trailingAnchor, constant: -10),
            
            fallbackLbl.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
            fallbackLbl.centerYAnchor.constraint(equalTo: squircle.centerYAnchor)
        ])
        
        // Subtitle row below squircle: mini logo + channel name
        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 4
        bottomRow.alignment = .center
        bottomRow.isUserInteractionEnabled = false
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bottomRow)
        
        let miniImageView = UIImageView()
        miniImageView.contentMode = .scaleAspectFit
        miniImageView.layer.cornerRadius = 2
        miniImageView.clipsToBounds = true
        miniImageView.isHidden = true
        miniImageView.translatesAutoresizingMaskIntoConstraints = false
        miniImageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        miniImageView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        bottomRow.addArrangedSubview(miniImageView)
        
        let miniDot = UIView()
        miniDot.backgroundColor = categoryColor(for: channel.groupTitle)
        miniDot.layer.cornerRadius = 3
        miniDot.translatesAutoresizingMaskIntoConstraints = false
        miniDot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        miniDot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        bottomRow.addArrangedSubview(miniDot)
        
        let nameLbl = UILabel()
        nameLbl.text = channel.name
        nameLbl.font = .systemFont(ofSize: 11.5, weight: .medium)
        nameLbl.textColor = UIColor(white: 0.90, alpha: 1.0)
        nameLbl.textAlignment = .left
        nameLbl.lineBreakMode = .byTruncatingTail
        bottomRow.addArrangedSubview(nameLbl)
        
        // Load channel logo if available
        if let logoURL = channel.logoURL {
            let cacheKey = logoURL.absoluteString as NSString
            if let cached = Self.imageCache.object(forKey: cacheKey) {
                logoImageView.image = cached
                fallbackLbl.isHidden = true
                miniImageView.image = cached
                miniImageView.isHidden = false
                miniDot.isHidden = true
            } else {
                URLSession.shared.dataTask(with: logoURL) { data, _, _ in
                    if let d = data, let img = UIImage(data: d) {
                        Self.imageCache.setObject(img, forKey: cacheKey,
                                                 cost: Int(img.size.width * img.size.height * 4))
                        DispatchQueue.main.async {
                            logoImageView.image = img
                            fallbackLbl.isHidden = true
                            miniImageView.image = img
                            miniImageView.isHidden = false
                            miniDot.isHidden = true
                        }
                    }
                }.resume()
            }
        }
        
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 84),
            card.heightAnchor.constraint(equalToConstant: 106),
            
            squircle.topAnchor.constraint(equalTo: card.topAnchor),
            squircle.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            squircle.widthAnchor.constraint(equalToConstant: 80),
            squircle.heightAnchor.constraint(equalToConstant: 80),
            
            bottomRow.topAnchor.constraint(equalTo: squircle.bottomAnchor, constant: 6),
            bottomRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 2),
            bottomRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2)
        ])
        
        card.addAction(UIAction { [weak self] _ in
            PlaybackManager.shared.play(channel: channel, presentation: .carMode)
            self?.showVideo(channel: channel)
        }, for: .touchUpInside)
        
        return card
    }
    
    private func categoryIconName(for group: String) -> String {
        let lower = group.lowercased()
        if lower.contains("movie") || lower.contains("cinema") || lower.contains("film") {
            return "film.fill"
        } else if lower.contains("sport") || lower.contains("football") || lower.contains("cricket") {
            return "sportscourt.fill"
        } else if lower.contains("news") || lower.contains("world") {
            return "newspaper.fill"
        } else if lower.contains("music") || lower.contains("radio") {
            return "music.note"
        } else if lower.contains("kid") || lower.contains("cartoon") || lower.contains("child") {
            return "face.smiling.fill"
        } else if lower.contains("shop") {
            return "cart.fill"
        } else {
            return "play.tv.fill"
        }
    }
    
    private func categoryColor(for group: String) -> UIColor {
        let lower = group.lowercased()
        if lower.contains("movie") || lower.contains("cinema") {
            return UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
        } else if lower.contains("sport") {
            return UIColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1.0)
        } else if lower.contains("news") {
            return UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1.0)
        } else if lower.contains("music") {
            return UIColor(red: 0.95, green: 0.60, blue: 0.10, alpha: 1.0)
        } else if lower.contains("kid") {
            return UIColor(red: 0.85, green: 0.45, blue: 0.95, alpha: 1.0)
        } else if lower.contains("shop") {
            return UIColor(red: 0.20, green: 0.85, blue: 0.75, alpha: 1.0)
        } else {
            return carGreen
        }
    }
    
}
