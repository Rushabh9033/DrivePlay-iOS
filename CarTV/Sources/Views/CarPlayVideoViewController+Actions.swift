import UIKit
import WebKit
import ReplayKit

extension InCarAutomotiveController {
    // MARK: - Actions & Presentation
    
    public func openCockpitHome() {
        self.view.isHidden = false
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        } else if let sup = self.view.superview {
            sup.bringSubviewToFront(self.view)
        }
        self.browserContainer.isHidden = true
        self.videoContainer.isHidden = true
        self.mirrorContainer.isHidden = true
        self.searchOverlay.isHidden = true
        switchTab(.home)
    }
    
    public func showVideo(channel: Channel) {
        self.view.isHidden = false
        self.videoContainer.isHidden = false
        self.browserContainer.isHidden = true
        
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        } else if let sup = self.view.superview {
            sup.bringSubviewToFront(self.view)
        }
        self.view.bringSubviewToFront(videoContainer)
        self.videoContainer.bringSubviewToFront(playerVC.view)
        self.videoContainer.bringSubviewToFront(videoOverlay)
        self.videoOverlay.alpha = 1.0
        
        videoTitleLabel.text = channel.name
        videoSubtitleLabel.text = channel.groupTitle.isEmpty ? "Live Stream" : channel.groupTitle
        
        if let p = PlaybackManager.shared.player {
            self.playerVC.player = p
            self.playerLayer?.player = p
            p.play()
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.videoContainer.frame = self.view.bounds
        self.playerVC.view.frame = self.videoContainer.bounds
        self.playerLayer?.frame = self.videoContainer.bounds
        CATransaction.commit()
        
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.view.window?.bringSubviewToFront(self.view)
            self.view.bringSubviewToFront(self.videoContainer)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            self.view.window?.bringSubviewToFront(self.view)
            self.view.bringSubviewToFront(self.videoContainer)
        }
    }
    
    @objc func handleVideoClose() {
        videoContainer.isHidden = true
        playerVC.player = nil
        PlaybackManager.shared.closePlayer()
        if currentTab == .browser {
            browserContainer.isHidden = false
        }
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        }
    }
    
    @objc func toggleVideoHUD() {
        UIView.animate(withDuration: 0.25) {
            self.videoOverlay.alpha = (self.videoOverlay.alpha > 0.1) ? 0.0 : 1.0
        }
    }
    
    public func showMirror() {
        self.view.isHidden = false
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        } else if let sup = self.view.superview {
            sup.bringSubviewToFront(self.view)
        }
        mirrorContainer.isHidden = false
        view.bringSubviewToFront(mirrorContainer)
        
        guard !isMirroringActive else { return }
        
        // Layout sample layer to fill container
        mirrorSampleLayer.frame = mirrorContainer.bounds
        if mirrorSampleLayer.superlayer == nil {
            mirrorContainer.layer.insertSublayer(mirrorSampleLayer, at: 0)
        }
        
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            NSLog("DRIVEPLAY RPScreenRecorder not available")
            // Latching isMirroringActive here would wedge the tab: every later attempt
            // would return early and the waiting card would spin forever.
            isMirroringActive = false
            mirrorTitleLabel.text = "Screen Mirroring Unavailable"
            mirrorSubtitleLabel.text = "Screen recording is not supported in the iOS Simulator. Run on a device to mirror."
            return
        }
        isMirroringActive = true
        
        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self = self, error == nil else { return }
            guard bufferType == .video else { return }
            // The display layer belongs to the main thread: `AVSampleBufferDisplayLayer`
            // is not thread-safe, and the capture handler runs on ReplayKit's own queue.
            DispatchQueue.main.async {
                // Show live frames in sample layer; hide waiting card once we get first frame
                if let card = self.mirrorContainer.viewWithTag(9901), !card.isHidden {
                    card.isHidden = true
                }
                if #available(iOS 18.0, *) {
                    let renderer = self.mirrorSampleLayer.sampleBufferRenderer
                    if renderer.status == .failed { renderer.flush() }
                    if renderer.isReadyForMoreMediaData { renderer.enqueue(sampleBuffer) }
                } else {
                    if self.mirrorSampleLayer.status == .failed { self.mirrorSampleLayer.flush() }
                    if self.mirrorSampleLayer.isReadyForMoreMediaData { self.mirrorSampleLayer.enqueue(sampleBuffer) }
                }
            }
        }, completionHandler: { [weak self] error in
            if let error = error {
                NSLog("DRIVEPLAY startCapture error: %@", error.localizedDescription)
                DispatchQueue.main.async { self?.isMirroringActive = false }
            }
        })
    }
    
    @objc func handleMirrorClose() {
        stopMirroring()
    }
    
    /// Stops the screen capture and resets the mirroring surface.
    ///
    /// This has to run when the scene goes away as well: a capture that outlives
    /// the external display keeps the system recording indicator on and drains
    /// the battery.
    public func stopMirroring() {
        isMirroringActive = false
        let recorder = RPScreenRecorder.shared()
        // Nothing was ever recording when the recorder is unavailable (the
        // Simulator), so there is no capture to stop.
        guard recorder.isAvailable else {
            resetMirrorSurface()
            return
        }
        recorder.stopCapture { [weak self] error in
            if let error = error { NSLog("DRIVEPLAY stopCapture error: %@", error.localizedDescription) }
            DispatchQueue.main.async { self?.resetMirrorSurface() }
        }
    }
    
    /// Hides the mirroring surface and restores its copy.
    private func resetMirrorSurface() {
        mirrorContainer.isHidden = true
        if #available(iOS 18.0, *) {
            mirrorSampleLayer.sampleBufferRenderer.flush()
        } else {
            mirrorSampleLayer.flush()
        }
        // Restore waiting card visibility
        mirrorContainer.viewWithTag(9901)?.isHidden = false
        // Restore the default copy so a later attempt doesn't show a stale
        // "unavailable" message from a previous failed start.
        mirrorTitleLabel.text = "Screen Mirroring"
        mirrorSubtitleLabel.text = "On your iPhone: Control Centre → Screen Mirroring → DrivePlay"
    }
    
    public func openBrowserHome() {
        self.view.isHidden = false
        self.browserContainer.isHidden = false
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        } else if let sup = self.view.superview {
            sup.bringSubviewToFront(self.view)
        }
        self.view.bringSubviewToFront(browserContainer)
        // The page stops with the catalogue — see `handleBrowserHome`.
        self.webView?.stopLoading()
        self.browserHomeScrollView.isHidden = false
        self.webView?.isHidden = true
        self.browserUrlLabel.text = "Enter a URL or search"
        self.browserUrlLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        self.browserBackBtn.tintColor = UIColor(white: 0.70, alpha: 1.0)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.browserContainer.frame = self.view.bounds
        let barH: CGFloat = browserToolbar.isHidden ? 0 : 44
        self.browserToolbar.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: barH)
        self.browserHomeScrollView.frame = CGRect(x: 0, y: barH, width: self.view.bounds.width, height: self.view.bounds.height - barH)
        CATransaction.commit()
        
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    public func openBrowser(url: URL) {
        self.view.isHidden = false
        self.browserContainer.isHidden = false
        if let win = self.view.window {
            win.bringSubviewToFront(self.view)
        } else if let sup = self.view.superview {
            sup.bringSubviewToFront(self.view)
        }
        self.view.bringSubviewToFront(browserContainer)
        self.browserHomeScrollView.isHidden = true
        self.browserUrlLabel.text = url.host ?? url.absoluteString
        self.browserUrlLabel.textColor = UIColor(white: 0.15, alpha: 1.0)
        self.browserBackBtn.tintColor = UIColor(white: 0.15, alpha: 1.0)
        
        let barH: CGFloat = browserToolbar.isHidden ? 0 : 44
        let b = view.bounds
        let webFrame = CGRect(x: 0, y: barH, width: b.width, height: b.height - barH)
        
        if self.webView == nil {
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            let wv = WKWebView(frame: webFrame, configuration: config)
            wv.navigationDelegate = self
            wv.backgroundColor = .white
            wv.scrollView.backgroundColor = .white
            browserContainer.addSubview(wv)
            self.webView = wv
        } else {
            self.webView?.frame = webFrame
        }
        
        if let wv = self.webView {
            browserContainer.bringSubviewToFront(wv)
            wv.isHidden = false
            wv.load(URLRequest(url: url))
        }
    }
    
    @objc public func handleBrowserHome() {
        // The house button means "back to the catalogue" — the page has to
        // stop, not just be hidden: a page that keeps loading (or playing)
        // behind the catalogue burns the battery and the mobile data.
        self.webView?.stopLoading()
        self.browserHomeScrollView.isHidden = false
        self.webView?.isHidden = true
        self.browserUrlLabel.text = "Enter a URL or search"
        self.browserUrlLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        self.browserBackBtn.tintColor = UIColor(white: 0.70, alpha: 1.0)
    }
    
    @objc public func handleBrowserClose() {
        self.browserContainer.isHidden = true
        switchTab(.home)
        self.onCloseBrowser?()
    }
    
    @objc func handleBrowserBack() {
        if self.webView?.canGoBack == true {
            self.webView?.goBack()
        } else {
            handleBrowserHome()
        }
    }
    
    @objc func handleBrowserReload() {
        if self.webView?.isHidden == false {
            self.webView?.reload()
        }
    }
    
    @objc func handleAddressBarTap() {
        let alert = UIAlertController(title: "Browse Web", message: "Enter a website URL or search query", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https:// or search term"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            // The alert is captured weakly: a strong capture would keep the
            // alert alive through its own action — the alert holds the action,
            // the action holds the alert.
            guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let finalUrl: URL
            if text.hasPrefix("http://") || text.hasPrefix("https://") {
                finalUrl = URL(string: text) ?? URL(string: "https://www.google.com")!
            } else if text.contains(".") && !text.contains(" ") {
                finalUrl = URL(string: "https://\(text)") ?? URL(string: "https://www.google.com")!
            } else {
                let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                finalUrl = URL(string: "https://www.google.com/search?q=\(q)")!
            }
            self?.openBrowser(url: finalUrl)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    /// Puts the page on the car's display.
    ///
    /// The car cannot show a page of its own, so the phone's screen share
    /// carries it — the same share the car's Cast tab starts.
    @objc func handleBrowserCast() {
        ScreenShareService.shared.startForTheCar()
    }

    /// Makes the page's text bigger or smaller.
    ///
    /// The sizes cycle — a car screen is read from a distance, and the page
    /// rarely knows how big it is going to be shown.
    @objc func handleBrowserTextSize() {
        guard let webView else { return }
        let steps: [CGFloat] = [1.0, 1.25, 1.5, 0.75]
        let current = steps.firstIndex(where: { abs($0 - webView.pageZoom) < 0.01 }) ?? 0
        webView.pageZoom = steps[(current + 1) % steps.count]
    }
    
    @objc func handleBrowserScrollUp() {
        let y = max(0, browserHomeScrollView.contentOffset.y - 180)
        browserHomeScrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }
    
    @objc func handleBrowserScrollDown() {
        let maxOff = max(0, browserHomeScrollView.contentSize.height - browserHomeScrollView.bounds.height)
        let y = min(maxOff, browserHomeScrollView.contentOffset.y + 180)
        browserHomeScrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }
    
    @objc func handleToggleFullscreen() {
        let isFull = browserToolbar.isHidden
        browserToolbar.isHidden = !isFull
        view.setNeedsLayout()
    }
    
}
