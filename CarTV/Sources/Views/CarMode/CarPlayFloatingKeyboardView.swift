import UIKit

public protocol CarPlayFloatingKeyboardDelegate: AnyObject {
    func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didEnterText text: String)
    func floatingKeyboardDidTapDelete(_ keyboard: CarPlayFloatingKeyboardView)
    func floatingKeyboardDidTapClear(_ keyboard: CarPlayFloatingKeyboardView)
    func floatingKeyboardDidTapGo(_ keyboard: CarPlayFloatingKeyboardView)
    func floatingKeyboardDidTapDismiss(_ keyboard: CarPlayFloatingKeyboardView)
    func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didSelectQuickItem text: String)
}

/// An automotive-optimised on-screen floating keyboard designed specifically for the
/// CarPlay display, styled after native Apple Maps in-car search input.
public final class CarPlayFloatingKeyboardView: UIView {
    
    public weak var delegate: CarPlayFloatingKeyboardDelegate?
    
    private enum KeyboardMode {
        case letters
        case numbers
    }
    
    private var mode: KeyboardMode = .letters
    
    // UI Elements
    private let blurBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let topBar = UIView()
    private let quickItemsScrollView = UIScrollView()
    private let quickItemsStack = UIStackView()
    private let dismissBtn = UIButton(type: .custom)
    private let clearBtn = UIButton(type: .custom)
    
    private let keysContainer = UIStackView()
    
    // Color Palette matching CarTV theme
    private let keyBg = UIColor(white: 0.22, alpha: 0.95)
    private let keyHighlightedBg = UIColor(white: 0.40, alpha: 1.0)
    private let specialKeyBg = UIColor(white: 0.16, alpha: 0.95)
    private let carGreen = UIColor(red: 0.0, green: 0.816, blue: 0.400, alpha: 1.0) // #00D066
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 0.96)
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 0.28, alpha: 0.8).cgColor
        
        // Add subtle blur effect
        blurBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurBackground)
        NSLayoutConstraint.activate([
            blurBackground.topAnchor.constraint(equalTo: topAnchor),
            blurBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurBackground.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        // 1. Top Accessory Bar (Quick Domain Chips + Clear + Dismiss)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)
        
        let hairline = UIView()
        hairline.backgroundColor = UIColor(white: 0.25, alpha: 0.7)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(hairline)
        
        // Dismiss button [ ⌨ ▾ ]
        let downCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        dismissBtn.setImage(UIImage(systemName: "chevron.down", withConfiguration: downCfg), for: .normal)
        dismissBtn.tintColor = UIColor(white: 0.85, alpha: 1.0)
        dismissBtn.backgroundColor = UIColor(white: 0.20, alpha: 0.8)
        dismissBtn.layer.cornerRadius = 14
        dismissBtn.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(dismissBtn)
        
        // Clear text button [ ✕ ]
        let xCfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        clearBtn.setImage(UIImage(systemName: "xmark", withConfiguration: xCfg), for: .normal)
        clearBtn.tintColor = UIColor(white: 0.85, alpha: 1.0)
        clearBtn.backgroundColor = UIColor(white: 0.20, alpha: 0.8)
        clearBtn.layer.cornerRadius = 14
        clearBtn.addTarget(self, action: #selector(handleClear), for: .touchUpInside)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(clearBtn)
        
        // Quick suggestions scrollview
        quickItemsScrollView.showsHorizontalScrollIndicator = false
        quickItemsScrollView.alwaysBounceHorizontal = true
        quickItemsScrollView.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(quickItemsScrollView)
        
        quickItemsStack.axis = .horizontal
        quickItemsStack.spacing = 8
        quickItemsStack.alignment = .center
        quickItemsStack.translatesAutoresizingMaskIntoConstraints = false
        quickItemsScrollView.addSubview(quickItemsStack)
        
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            topBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            topBar.heightAnchor.constraint(equalToConstant: 34),
            
            clearBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 28),
            clearBtn.heightAnchor.constraint(equalToConstant: 28),
            
            quickItemsScrollView.leadingAnchor.constraint(equalTo: clearBtn.trailingAnchor, constant: 8),
            quickItemsScrollView.trailingAnchor.constraint(equalTo: dismissBtn.leadingAnchor, constant: -8),
            quickItemsScrollView.topAnchor.constraint(equalTo: topBar.topAnchor),
            quickItemsScrollView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            
            quickItemsStack.topAnchor.constraint(equalTo: quickItemsScrollView.topAnchor),
            quickItemsStack.bottomAnchor.constraint(equalTo: quickItemsScrollView.bottomAnchor),
            quickItemsStack.leadingAnchor.constraint(equalTo: quickItemsScrollView.leadingAnchor),
            quickItemsStack.trailingAnchor.constraint(equalTo: quickItemsScrollView.trailingAnchor),
            quickItemsStack.heightAnchor.constraint(equalTo: quickItemsScrollView.heightAnchor),
            
            dismissBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            dismissBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            dismissBtn.widthAnchor.constraint(equalToConstant: 28),
            dismissBtn.heightAnchor.constraint(equalToConstant: 28),
            
            hairline.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        
        setupQuickChips()
        
        // 2. Keyboard Rows
        keysContainer.axis = .vertical
        keysContainer.distribution = .fillEqually
        keysContainer.spacing = 6
        keysContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keysContainer)
        
        NSLayoutConstraint.activate([
            keysContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            keysContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
            keysContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            keysContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8)
        ])
        
        renderKeys()
    }
    
    private func setupQuickChips() {
        let chips = ["youtube.com", "google.com", "twitch.tv", ".com", ".org", "/", "https://"]
        for chip in chips {
            let btn = UIButton(type: .custom)
            btn.setTitle(chip, for: .normal)
            btn.setTitleColor(UIColor(white: 0.90, alpha: 1.0), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .medium)
            btn.backgroundColor = UIColor(white: 0.20, alpha: 0.9)
            btn.layer.cornerRadius = 13
            btn.layer.masksToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.addTarget(self, action: #selector(handleChipTap(_:)), for: .touchUpInside)
            btn.accessibilityIdentifier = chip
            quickItemsStack.addArrangedSubview(btn)
        }
    }
    
    // MARK: - Key Rendering
    
    private func renderKeys() {
        for v in keysContainer.arrangedSubviews {
            keysContainer.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        
        switch mode {
        case .letters:
            renderLetters()
        case .numbers:
            renderNumbers()
        }
    }
    
    private func renderLetters() {
        let r1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        let r2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
        let r3 = ["z", "x", "c", "v", "b", "n", "m"]
        
        keysContainer.addArrangedSubview(buildKeyRow(items: r1))
        keysContainer.addArrangedSubview(buildKeyRow(items: r2, sideInsetRatio: 0.05))
        
        // Row 3: [123] [z x c v b n m] [⌫]
        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.distribution = .fillProportionally
        row3.spacing = 6
        
        let switchBtn = makeSpecialKey(title: "123", widthRatio: 1.4) { [weak self] in
            self?.mode = .numbers
            self?.renderKeys()
        }
        row3.addArrangedSubview(switchBtn)
        
        for k in r3 {
            row3.addArrangedSubview(makeKeyButton(title: k))
        }
        
        let delBtn = makeDeleteKey(widthRatio: 1.4)
        row3.addArrangedSubview(delBtn)
        keysContainer.addArrangedSubview(row3)
        
        // Row 4: [⌨] [.com] [space] [.] [Go]
        let row4 = UIStackView()
        row4.axis = .horizontal
        row4.distribution = .fillProportionally
        row4.spacing = 6
        
        let hideBtn = makeSpecialKey(title: "⌨", widthRatio: 1.2) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboardDidTapDismiss(self)
        }
        row4.addArrangedSubview(hideBtn)
        
        let dotComBtn = makeSpecialKey(title: ".com", widthRatio: 1.4) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboard(self, didEnterText: ".com")
        }
        row4.addArrangedSubview(dotComBtn)
        
        let spaceBtn = makeSpecialKey(title: "space", widthRatio: 3.5) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboard(self, didEnterText: " ")
        }
        row4.addArrangedSubview(spaceBtn)
        
        let dotBtn = makeKeyButton(title: ".")
        row4.addArrangedSubview(dotBtn)
        
        let goBtn = makeGoKey(widthRatio: 1.8)
        row4.addArrangedSubview(goBtn)
        
        keysContainer.addArrangedSubview(row4)
    }
    
    private func renderNumbers() {
        let r1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let r2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
        let r3 = [".", ",", "?", "!", "'", "#", "%"]
        
        keysContainer.addArrangedSubview(buildKeyRow(items: r1))
        keysContainer.addArrangedSubview(buildKeyRow(items: r2))
        
        // Row 3: [ABC] [symbols] [⌫]
        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.distribution = .fillProportionally
        row3.spacing = 6
        
        let switchBtn = makeSpecialKey(title: "ABC", widthRatio: 1.4) { [weak self] in
            self?.mode = .letters
            self?.renderKeys()
        }
        row3.addArrangedSubview(switchBtn)
        
        for k in r3 {
            row3.addArrangedSubview(makeKeyButton(title: k))
        }
        
        let delBtn = makeDeleteKey(widthRatio: 1.4)
        row3.addArrangedSubview(delBtn)
        keysContainer.addArrangedSubview(row3)
        
        // Row 4: [⌨] [https://] [space] [.com] [Go]
        let row4 = UIStackView()
        row4.axis = .horizontal
        row4.distribution = .fillProportionally
        row4.spacing = 6
        
        let hideBtn = makeSpecialKey(title: "⌨", widthRatio: 1.2) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboardDidTapDismiss(self)
        }
        row4.addArrangedSubview(hideBtn)
        
        let httpBtn = makeSpecialKey(title: "https://", widthRatio: 1.6) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboard(self, didEnterText: "https://")
        }
        row4.addArrangedSubview(httpBtn)
        
        let spaceBtn = makeSpecialKey(title: "space", widthRatio: 3.2) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboard(self, didEnterText: " ")
        }
        row4.addArrangedSubview(spaceBtn)
        
        let dotComBtn = makeSpecialKey(title: ".com", widthRatio: 1.4) { [weak self] in
            guard let self = self else { return }
            self.delegate?.floatingKeyboard(self, didEnterText: ".com")
        }
        row4.addArrangedSubview(dotComBtn)
        
        let goBtn = makeGoKey(widthRatio: 1.8)
        row4.addArrangedSubview(goBtn)
        
        keysContainer.addArrangedSubview(row4)
    }
    
    private func buildKeyRow(items: [String], sideInsetRatio: CGFloat = 0.0) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        
        for k in items {
            row.addArrangedSubview(makeKeyButton(title: k))
        }
        return row
    }
    
    // MARK: - Button Factory
    
    private func makeKeyButton(title: String) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        btn.backgroundColor = keyBg
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.accessibilityIdentifier = title
        btn.addTarget(self, action: #selector(handleKeyTap(_:)), for: .touchUpInside)
        return btn
    }
    
    private func makeSpecialKey(title: String, widthRatio: CGFloat, action: @escaping () -> Void) -> UIButton {
        let btn = ActionButton(type: .custom)
        btn.action = action
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(UIColor(white: 0.92, alpha: 1.0), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.backgroundColor = specialKeyBg
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.addTarget(btn, action: #selector(ActionButton.performAction), for: .touchUpInside)
        return btn
    }
    
    private func makeDeleteKey(widthRatio: CGFloat) -> UIButton {
        let btn = UIButton(type: .custom)
        let delCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        btn.setImage(UIImage(systemName: "delete.left.fill", withConfiguration: delCfg), for: .normal)
        btn.tintColor = UIColor(white: 0.92, alpha: 1.0)
        btn.backgroundColor = specialKeyBg
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.addTarget(self, action: #selector(handleDeleteTap), for: .touchUpInside)
        return btn
    }
    
    private func makeGoKey(widthRatio: CGFloat) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle("Go", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        btn.backgroundColor = carGreen
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.addTarget(self, action: #selector(handleGoTap), for: .touchUpInside)
        return btn
    }
    
    // MARK: - Actions
    
    @objc private func handleKeyTap(_ sender: UIButton) {
        guard let title = sender.accessibilityIdentifier else { return }
        delegate?.floatingKeyboard(self, didEnterText: title)
    }
    
    @objc private func handleDeleteTap() {
        delegate?.floatingKeyboardDidTapDelete(self)
    }
    
    @objc private func handleGoTap() {
        delegate?.floatingKeyboardDidTapGo(self)
    }
    
    @objc private func handleClear() {
        delegate?.floatingKeyboardDidTapClear(self)
    }
    
    @objc private func handleDismiss() {
        delegate?.floatingKeyboardDidTapDismiss(self)
    }
    
    @objc private func handleChipTap(_ sender: UIButton) {
        guard let chip = sender.accessibilityIdentifier else { return }
        delegate?.floatingKeyboard(self, didSelectQuickItem: chip)
    }
}

// MARK: - Helper ActionButton

private final class ActionButton: UIButton {
    var action: (() -> Void)?
    @objc func performAction() {
        action?()
    }
}
