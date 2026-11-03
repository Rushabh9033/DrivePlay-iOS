import UIKit
import AVKit

extension InCarAutomotiveController {
    // MARK: - Mirror Container
    
    func setupMirrorContainer() {
        // Full-screen mirror container: black bg + live sample layer + stop button
        mirrorContainer.backgroundColor = .black
        mirrorContainer.isHidden = true
        view.addSubview(mirrorContainer)
        
        // Live capture layer fills the whole container
        mirrorSampleLayer.videoGravity = .resizeAspect
        mirrorSampleLayer.backgroundColor = UIColor.black.cgColor
        mirrorContainer.layer.addSublayer(mirrorSampleLayer)
        
        // Waiting card (shown until capture starts)
        let mirrorCard = UIView()
        mirrorCard.backgroundColor = cardDark
        mirrorCard.layer.cornerRadius = 20
        mirrorCard.translatesAutoresizingMaskIntoConstraints = false
        mirrorCard.tag = 9901            // so we can find/hide it when capture starts
        mirrorContainer.addSubview(mirrorCard)
        
        mirrorIconView.image = UIImage(systemName: "airplayvideo")
        mirrorIconView.tintColor = carGreen
        mirrorIconView.contentMode = .scaleAspectFit
        mirrorIconView.translatesAutoresizingMaskIntoConstraints = false
        mirrorCard.addSubview(mirrorIconView)
        
        mirrorTitleLabel.text = "Screen Mirroring"
        mirrorTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        mirrorTitleLabel.textColor = .white
        mirrorTitleLabel.textAlignment = .center
        mirrorTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        mirrorCard.addSubview(mirrorTitleLabel)
        
        mirrorSubtitleLabel.text = "On your iPhone: Control Centre → Screen Mirroring → DrivePlay"
        mirrorSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        mirrorSubtitleLabel.textColor = mutedText
        mirrorSubtitleLabel.textAlignment = .center
        mirrorSubtitleLabel.numberOfLines = 2
        mirrorSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        mirrorCard.addSubview(mirrorSubtitleLabel)
        
        mirrorCloseBtn.setTitle("✕  Stop Mirroring", for: .normal)
        mirrorCloseBtn.setTitleColor(.white, for: .normal)
        mirrorCloseBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        mirrorCloseBtn.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        mirrorCloseBtn.layer.cornerRadius = 10
        mirrorCloseBtn.translatesAutoresizingMaskIntoConstraints = false
        mirrorCloseBtn.addTarget(self, action: #selector(handleMirrorClose), for: .touchUpInside)
        mirrorContainer.addSubview(mirrorCloseBtn)   // on top of sample layer
        
        NSLayoutConstraint.activate([
            mirrorCard.centerXAnchor.constraint(equalTo: mirrorContainer.centerXAnchor),
            mirrorCard.centerYAnchor.constraint(equalTo: mirrorContainer.centerYAnchor, constant: -20),
            mirrorCard.widthAnchor.constraint(equalToConstant: 340),
            mirrorCard.heightAnchor.constraint(equalToConstant: 160),
            
            mirrorIconView.topAnchor.constraint(equalTo: mirrorCard.topAnchor, constant: 18),
            mirrorIconView.centerXAnchor.constraint(equalTo: mirrorCard.centerXAnchor),
            mirrorIconView.widthAnchor.constraint(equalToConstant: 44),
            mirrorIconView.heightAnchor.constraint(equalToConstant: 36),
            
            mirrorTitleLabel.topAnchor.constraint(equalTo: mirrorIconView.bottomAnchor, constant: 8),
            mirrorTitleLabel.leadingAnchor.constraint(equalTo: mirrorCard.leadingAnchor, constant: 16),
            mirrorTitleLabel.trailingAnchor.constraint(equalTo: mirrorCard.trailingAnchor, constant: -16),
            
            mirrorSubtitleLabel.topAnchor.constraint(equalTo: mirrorTitleLabel.bottomAnchor, constant: 6),
            mirrorSubtitleLabel.leadingAnchor.constraint(equalTo: mirrorCard.leadingAnchor, constant: 16),
            mirrorSubtitleLabel.trailingAnchor.constraint(equalTo: mirrorCard.trailingAnchor, constant: -16),
            
            mirrorCloseBtn.bottomAnchor.constraint(equalTo: mirrorContainer.bottomAnchor, constant: -14),
            mirrorCloseBtn.centerXAnchor.constraint(equalTo: mirrorContainer.centerXAnchor),
            mirrorCloseBtn.widthAnchor.constraint(equalToConstant: 160),
            mirrorCloseBtn.heightAnchor.constraint(equalToConstant: 34)
        ])
    }
    
}
