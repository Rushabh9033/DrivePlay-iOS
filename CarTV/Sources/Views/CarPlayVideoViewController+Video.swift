import UIKit
import AVKit

extension InCarAutomotiveController {
    // MARK: - Video Container (Real Fullscreen Video with AVPlayerViewController & AVPlayerLayer)
    
    func setupVideoContainer() {
        videoContainer.backgroundColor = .black
        videoContainer.isHidden = true
        view.addSubview(videoContainer)
        
        addChild(playerVC)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        playerVC.showsPlaybackControls = false
        playerVC.videoGravity = .resizeAspect
        playerVC.updatesNowPlayingInfoCenter = false
        videoContainer.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor)
        ])
        
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(layer)
        self.playerLayer = layer
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleVideoHUD))
        videoContainer.addGestureRecognizer(tap)
        videoContainer.isUserInteractionEnabled = true
        
        videoOverlay.backgroundColor = UIColor(white: 0.10, alpha: 0.92)
        videoOverlay.layer.cornerRadius = 14
        videoOverlay.layer.masksToBounds = true
        videoOverlay.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(videoOverlay)
        
        videoLiveDot.backgroundColor = carGreen
        videoLiveDot.layer.cornerRadius = 4
        videoLiveDot.translatesAutoresizingMaskIntoConstraints = false
        videoOverlay.addSubview(videoLiveDot)
        
        videoLiveBadge.text = "LIVE"
        videoLiveBadge.font = .systemFont(ofSize: 11, weight: .heavy)
        videoLiveBadge.textColor = carGreen
        videoLiveBadge.translatesAutoresizingMaskIntoConstraints = false
        videoOverlay.addSubview(videoLiveBadge)
        
        videoTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        videoTitleLabel.textColor = .white
        videoTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        videoOverlay.addSubview(videoTitleLabel)
        
        videoSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        videoSubtitleLabel.textColor = mutedText
        videoSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        videoOverlay.addSubview(videoSubtitleLabel)
        
        videoCloseButton.setTitle("✕ Exit Video", for: .normal)
        videoCloseButton.setTitleColor(.white, for: .normal)
        videoCloseButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        videoCloseButton.backgroundColor = UIColor(white: 0.25, alpha: 0.8)
        videoCloseButton.layer.cornerRadius = 10
        videoCloseButton.translatesAutoresizingMaskIntoConstraints = false
        videoCloseButton.addTarget(self, action: #selector(handleVideoClose), for: .touchUpInside)
        videoOverlay.addSubview(videoCloseButton)
        
        NSLayoutConstraint.activate([
            videoOverlay.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 8),
            videoOverlay.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: 16),
            videoOverlay.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -16),
            videoOverlay.heightAnchor.constraint(equalToConstant: 44),
            
            videoLiveDot.leadingAnchor.constraint(equalTo: videoOverlay.leadingAnchor, constant: 12),
            videoLiveDot.centerYAnchor.constraint(equalTo: videoOverlay.centerYAnchor),
            videoLiveDot.widthAnchor.constraint(equalToConstant: 8),
            videoLiveDot.heightAnchor.constraint(equalToConstant: 8),
            
            videoLiveBadge.leadingAnchor.constraint(equalTo: videoLiveDot.trailingAnchor, constant: 5),
            videoLiveBadge.centerYAnchor.constraint(equalTo: videoOverlay.centerYAnchor),
            
            videoTitleLabel.leadingAnchor.constraint(equalTo: videoLiveBadge.trailingAnchor, constant: 10),
            videoTitleLabel.centerYAnchor.constraint(equalTo: videoOverlay.centerYAnchor, constant: -7),
            videoTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: videoCloseButton.leadingAnchor, constant: -10),
            
            videoSubtitleLabel.leadingAnchor.constraint(equalTo: videoTitleLabel.leadingAnchor),
            videoSubtitleLabel.centerYAnchor.constraint(equalTo: videoOverlay.centerYAnchor, constant: 8),
            videoSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: videoCloseButton.leadingAnchor, constant: -10),
            
            videoCloseButton.trailingAnchor.constraint(equalTo: videoOverlay.trailingAnchor, constant: -10),
            videoCloseButton.centerYAnchor.constraint(equalTo: videoOverlay.centerYAnchor),
            videoCloseButton.widthAnchor.constraint(equalToConstant: 96),
            videoCloseButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
}
