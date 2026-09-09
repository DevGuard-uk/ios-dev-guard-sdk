import UIKit

final class DevGuardShieldPresenter {
    static let shared = DevGuardShieldPresenter()
    private weak var hostWindow: UIWindow?
    private var overlayRoot: UIView?
    private var fullScreenHost: UIView?
    private var bannerHost: UIView?
    private var diagnosticFab: UIButton?

    func attach(to window: UIWindow) {
        hostWindow = window
    }

    func render(response: GuardResponse?) {
        guard let window = hostWindow else { return }
        clearLayers()

        let status = response?.status ?? .pending

        switch status {
        case .locked, .expired:
            showFullScreen(on: window, view: PremiumLockScreenView(response: response ?? emptyResponse(status), status: status))
        case .pending:
            showFullScreen(on: window, view: PendingScreenView(message: response?.message ?? ""))
        case .warning:
            showBanner(on: window, view: WarningBannerView(title: response?.title, message: response?.message ?? ""))
        case .active:
            break
        }

        if response?.betaFeatures["showDiagnosticLogs"] as? Bool == true,
           status != .locked && status != .expired {
            showDiagnosticFab(on: window, response: response!)
        }
    }

    private func showFullScreen(on window: UIWindow, view: UIView) {
        ensureRoot(on: window)
        fullScreenHost?.subviews.forEach { $0.removeFromSuperview() }
        fullScreenHost?.isHidden = false
        overlayRoot?.isHidden = false
        view.translatesAutoresizingMaskIntoConstraints = false
        fullScreenHost?.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: fullScreenHost!.topAnchor),
            view.leadingAnchor.constraint(equalTo: fullScreenHost!.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: fullScreenHost!.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: fullScreenHost!.bottomAnchor),
        ])
        overlayRoot?.layer.zPosition = 1000
        if let overlayRoot { window.bringSubviewToFront(overlayRoot) }
    }

    private func showBanner(on window: UIWindow, view: UIView) {
        ensureRoot(on: window)
        bannerHost?.subviews.forEach { $0.removeFromSuperview() }
        bannerHost?.isHidden = false
        overlayRoot?.isHidden = false
        view.translatesAutoresizingMaskIntoConstraints = false
        bannerHost?.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: bannerHost!.safeAreaLayoutGuide.topAnchor, constant: 8),
            view.leadingAnchor.constraint(equalTo: bannerHost!.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: bannerHost!.trailingAnchor, constant: -16),
        ])
        overlayRoot?.layer.zPosition = 1000
        if let overlayRoot { window.bringSubviewToFront(overlayRoot) }
    }

    private func showDiagnosticFab(on window: UIWindow, response: GuardResponse) {
        ensureRoot(on: window)
        let fab = UIButton(type: .system)
        fab.setTitle("🐞", for: .normal)
        fab.titleLabel?.font = .systemFont(ofSize: 22)
        fab.backgroundColor = UIColor(red: 1, green: 0.76, blue: 0.03, alpha: 0.8)
        fab.layer.cornerRadius = 24
        fab.translatesAutoresizingMaskIntoConstraints = false
        fab.addAction(UIAction { [weak self] _ in
            let panel = UILabel()
            panel.numberOfLines = 0
            panel.text = "Diagnostic Logs\nStatus: \(response.status.rawValue)\nPing: \(response.pingInterval)m"
            panel.textColor = .white
            panel.backgroundColor = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)
            panel.textAlignment = .center
            self?.showFullScreen(on: window, view: panel)
        }, for: .touchUpInside)
        overlayRoot?.addSubview(fab)
        NSLayoutConstraint.activate([
            fab.widthAnchor.constraint(equalToConstant: 48),
            fab.heightAnchor.constraint(equalToConstant: 48),
            fab.trailingAnchor.constraint(equalTo: overlayRoot!.trailingAnchor, constant: -24),
            fab.bottomAnchor.constraint(equalTo: overlayRoot!.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
        diagnosticFab = fab
    }

    private func ensureRoot(on window: UIWindow) {
        if overlayRoot == nil {
            let root = UIView(frame: window.bounds)
            root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.isUserInteractionEnabled = true
            root.isHidden = true

            let full = UIView(frame: root.bounds)
            full.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            full.isHidden = true

            let banner = UIView(frame: root.bounds)
            banner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            banner.isHidden = true

            root.addSubview(full)
            root.addSubview(banner)
            window.addSubview(root)

            overlayRoot = root
            fullScreenHost = full
            bannerHost = banner
        }
    }

    private func clearLayers() {
        fullScreenHost?.subviews.forEach { $0.removeFromSuperview() }
        fullScreenHost?.isHidden = true
        bannerHost?.subviews.forEach { $0.removeFromSuperview() }
        bannerHost?.isHidden = true
        diagnosticFab?.removeFromSuperview()
        diagnosticFab = nil
        overlayRoot?.isHidden = true
    }

    private func emptyResponse(_ status: LicenseStatus) -> GuardResponse {
        GuardResponse(
            status: status, title: nil, message: "",
            contactEmail: "", contactPhone: "", contactWhatsapp: "",
            allowUnlock: false, betaFeatures: [:], extraData: [:], lifecycleSync: nil,
            remoteCommand: nil, deviceToken: nil, pingInterval: 5,
            syncPolicy: "immediate", blockEmulators: false, diagnosticPasscodeHash: nil, branding: nil, wipeNonce: nil
        )
    }
}

// Backward-compatible alias used by DevGuard.swift
typealias LockScreenPresenter = DevGuardShieldPresenter
