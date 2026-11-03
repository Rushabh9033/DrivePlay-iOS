import UIKit

extension InCarAutomotiveController {
    // MARK: - Search Overlay
    
    func setupSearchOverlay() {
        searchOverlay.backgroundColor = UIColor(white: 0.08, alpha: 0.96)
        searchOverlay.isHidden = true
        view.addSubview(searchOverlay)
        
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        searchOverlay.addSubview(header)
        
        searchBarField.placeholder = "Search channels or categories..."
        searchBarField.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        searchBarField.textColor = .white
        searchBarField.font = .systemFont(ofSize: 14, weight: .medium)
        searchBarField.layer.cornerRadius = 10
        searchBarField.layer.masksToBounds = true
        searchBarField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        searchBarField.leftViewMode = .always
        searchBarField.delegate = self
        searchBarField.addTarget(self, action: #selector(handleSearchTextChange), for: .editingChanged)
        searchBarField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchBarField)
        
        searchCancelBtn.setTitle("Cancel", for: .normal)
        searchCancelBtn.setTitleColor(carGreen, for: .normal)
        searchCancelBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        searchCancelBtn.addTarget(self, action: #selector(handleSearchCancel), for: .touchUpInside)
        searchCancelBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchCancelBtn)
        
        searchResultsScrollView.alwaysBounceVertical = true
        searchResultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        searchOverlay.addSubview(searchResultsScrollView)
        
        searchResultsStack.axis = .vertical
        searchResultsStack.spacing = 8
        searchResultsStack.translatesAutoresizingMaskIntoConstraints = false
        searchResultsScrollView.addSubview(searchResultsStack)
        
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: searchOverlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: searchOverlay.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: searchOverlay.trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 38),
            
            searchBarField.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            searchBarField.trailingAnchor.constraint(equalTo: searchCancelBtn.leadingAnchor, constant: -10),
            searchBarField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchBarField.heightAnchor.constraint(equalToConstant: 34),
            
            searchCancelBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            searchCancelBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            searchResultsScrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            searchResultsScrollView.bottomAnchor.constraint(equalTo: searchOverlay.bottomAnchor),
            searchResultsScrollView.leadingAnchor.constraint(equalTo: searchOverlay.leadingAnchor, constant: 16),
            searchResultsScrollView.trailingAnchor.constraint(equalTo: searchOverlay.trailingAnchor, constant: -16),
            
            searchResultsStack.topAnchor.constraint(equalTo: searchResultsScrollView.topAnchor),
            searchResultsStack.bottomAnchor.constraint(equalTo: searchResultsScrollView.bottomAnchor, constant: -16),
            searchResultsStack.leadingAnchor.constraint(equalTo: searchResultsScrollView.leadingAnchor),
            searchResultsStack.trailingAnchor.constraint(equalTo: searchResultsScrollView.trailingAnchor),
            searchResultsStack.widthAnchor.constraint(equalTo: searchResultsScrollView.widthAnchor)
        ])
    }
    
    // MARK: - Search
    
    @objc func handleSearchTap() {
        searchOverlay.isHidden = false
        view.bringSubviewToFront(searchOverlay)
        searchBarField.becomeFirstResponder()
        filterSearchResults(query: "")
    }
    
    @objc private func handleSearchCancel() {
        searchBarField.resignFirstResponder()
        searchOverlay.isHidden = true
    }
    
    @objc private func handleSearchTextChange() {
        let q = searchBarField.text ?? ""
        filterSearchResults(query: q)
    }
    
    private func filterSearchResults(query: String) {
        for v in searchResultsStack.arrangedSubviews {
            searchResultsStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let channels = PlaylistStore.shared.channels
        let matches = trimmed.isEmpty ? channels : channels.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.groupTitle.localizedCaseInsensitiveContains(trimmed)
        }
        
        for channel in matches.prefix(20) {
            let rowBtn = UIButton(type: .system)
            rowBtn.backgroundColor = cardDark
            rowBtn.layer.cornerRadius = 10
            rowBtn.contentHorizontalAlignment = .leading
            rowBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            rowBtn.setTitle("▶  \(channel.name) (\(channel.groupTitle))", for: .normal)
            rowBtn.setTitleColor(.white, for: .normal)
            rowBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            rowBtn.addAction(UIAction { [weak self] _ in
                self?.searchOverlay.isHidden = true
                self?.searchBarField.resignFirstResponder()
                PlaybackManager.shared.play(channel: channel, presentation: .carMode)
                self?.showVideo(channel: channel)
            }, for: .touchUpInside)
            searchResultsStack.addArrangedSubview(rowBtn)
        }
    }
}
