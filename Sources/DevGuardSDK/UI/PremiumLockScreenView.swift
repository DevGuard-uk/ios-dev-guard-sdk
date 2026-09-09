import UIKit

/// Premium lock screen — Flutter PaymentWall / RN LockScreen parity.
final class PremiumLockScreenView: UIView {
    private let response: GuardResponse
    private let status: LicenseStatus
    private var showUnlock = false
    private var loading = false
    private var errorText: String?
    private let actionsStack = UIStackView()
    private let unlockField = UITextField()

    init(response: GuardResponse, status: LicenseStatus) {
        self.response = response
        self.status = status
        super.init(frame: .zero)
        backgroundColor = .black
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let footer = BrandingHelpers.resolveFooter(response.branding)

        addBlob(color: footer.primaryColor, alpha: 0.15, size: 0.75, x: 0.55, y: -0.15)
        addBlob(color: footer.accentColor, alpha: 0.12, size: 0.7, x: -0.2, y: 0.65)
        addBlob(color: footer.primaryColor, alpha: 0.1, size: 0.55, x: 0.6, y: 0.35)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(white: 1, alpha: 0.05)
        card.layer.cornerRadius = 32
        card.layer.borderWidth = 1.5
        card.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.alignment = .center
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = footer.primaryColor.withAlphaComponent(0.13)
        iconWrap.layer.cornerRadius = 50
        iconWrap.layer.borderWidth = 1
        iconWrap.layer.borderColor = footer.primaryColor.withAlphaComponent(0.27).cgColor
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 100),
            iconWrap.heightAnchor.constraint(equalToConstant: 100),
        ])
        let icon = UILabel()
        icon.text = "🛡️"
        icon.font = .systemFont(ofSize: 48)
        icon.textAlignment = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
        ])
        cardStack.addArrangedSubview(iconWrap)

        if let logo = response.branding?.logoUrl, !logo.isEmpty, let url = URL(string: logo) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    icon.isHidden = true
                    let iv = UIImageView(image: image)
                    iv.contentMode = .scaleAspectFit
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    iconWrap.addSubview(iv)
                    NSLayoutConstraint.activate([
                        iv.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
                        iv.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
                        iv.widthAnchor.constraint(equalToConstant: 56),
                        iv.heightAnchor.constraint(equalToConstant: 56),
                    ])
                }
            }.resume()
        }

        let defaultTitle: String = {
            switch status {
            case .expired: return "License Expired"
            case .pending: return "Connecting..."
            default: return "Access Restricted"
            }
        }()
        let title = UILabel()
        title.text = (response.title?.isEmpty == false ? response.title! : defaultTitle).uppercased()
        title.textColor = .white
        title.font = .systemFont(ofSize: 22, weight: .black)
        title.textAlignment = .center
        title.numberOfLines = 0
        cardStack.addArrangedSubview(title)

        let divider = UIView()
        divider.backgroundColor = footer.primaryColor
        divider.layer.cornerRadius = 1.5
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 40),
            divider.heightAnchor.constraint(equalToConstant: 3),
        ])
        cardStack.addArrangedSubview(divider)

        let defaultMsg: String = {
            switch status {
            case .pending: return "Verifying license with DevGuard..."
            case .expired: return "The license for this application has expired."
            default: return "This application has been remotely locked by the developer."
            }
        }()
        let message = UILabel()
        message.text = response.message.isEmpty ? defaultMsg : response.message
        message.textColor = UIColor(white: 1, alpha: 0.7)
        message.font = .systemFont(ofSize: 16)
        message.textAlignment = .center
        message.numberOfLines = 0
        cardStack.addArrangedSubview(message)

        actionsStack.axis = .vertical
        actionsStack.spacing = 12
        actionsStack.alignment = .fill
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.addArrangedSubview(actionsStack)
        rebuildActions(footer: footer)

        content.addArrangedSubview(card)

        var scrollBottomConstraint: NSLayoutConstraint = scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16)

        if !footer.hidePoweredBy {
            let footerStack = UIStackView()
            footerStack.axis = .vertical
            footerStack.alignment = .center
            footerStack.spacing = 4
            footerStack.isUserInteractionEnabled = true
            footerStack.translatesAutoresizingMaskIntoConstraints = false
            footerStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openFooter)))
            let label = UILabel()
            label.text = footer.label
            label.textColor = UIColor(white: 1, alpha: 0.3)
            label.font = .systemFont(ofSize: 12)
            let brand = UILabel()
            brand.text = footer.brand.uppercased()
            brand.textColor = UIColor(white: 1, alpha: 0.6)
            brand.font = .systemFont(ofSize: 14, weight: .heavy)
            footerStack.addArrangedSubview(label)
            footerStack.addArrangedSubview(brand)
            addSubview(footerStack)

            NSLayoutConstraint.activate([
                footerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                footerStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ])
            scrollBottomConstraint = scroll.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12)
        }

        let contentCenterY = content.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        contentCenterY.priority = .defaultLow

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollBottomConstraint,
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            contentCenterY,
            card.widthAnchor.constraint(equalTo: content.widthAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 32),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 32),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -32),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -32),
        ])
    }

    private var footerUrl = "https://devguard.uk"
    @objc private func openFooter() {
        if let url = URL(string: footerUrl) { UIApplication.shared.open(url) }
    }

    private func rebuildActions(footer: BrandingFooter) {
        footerUrl = footer.url
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if showUnlock && response.allowUnlock {
            if let errorText {
                let err = UILabel()
                err.text = errorText
                err.textColor = UIColor(red: 1, green: 0.32, blue: 0.32, alpha: 1)
                err.font = .systemFont(ofSize: 13)
                err.textAlignment = .center
                actionsStack.addArrangedSubview(err)
            }
            unlockField.placeholder = "License key"
            unlockField.isSecureTextEntry = true
            unlockField.backgroundColor = UIColor(white: 1, alpha: 0.05)
            unlockField.textColor = .white
            unlockField.layer.cornerRadius = 16
            unlockField.layer.borderWidth = 1
            unlockField.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
            unlockField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
            unlockField.leftViewMode = .always
            unlockField.heightAnchor.constraint(equalToConstant: 48).isActive = true
            actionsStack.addArrangedSubview(unlockField)

            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually

            let cancel = UIButton(type: .system)
            cancel.setTitle("Cancel", for: .normal)
            cancel.setTitleColor(UIColor(white: 1, alpha: 0.4), for: .normal)
            cancel.addAction(UIAction { [weak self] _ in
                guard let self, !self.loading else { return }
                self.showUnlock = false
                self.errorText = nil
                self.rebuildActions(footer: footer)
            }, for: .touchUpInside)

            let unlock = UIButton(type: .system)
            unlock.setTitle(loading ? "" : "Unlock", for: .normal)
            unlock.backgroundColor = .white
            unlock.setTitleColor(.black, for: .normal)
            unlock.layer.cornerRadius = 12
            if loading {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                unlock.addSubview(spinner)
                spinner.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    spinner.centerXAnchor.constraint(equalTo: unlock.centerXAnchor),
                    spinner.centerYAnchor.constraint(equalTo: unlock.centerYAnchor),
                ])
            }
            unlock.addAction(UIAction { [weak self] _ in
                guard let self, !self.loading else { return }
                let key = self.unlockField.text?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !key.isEmpty else { return }
                self.loading = true
                self.rebuildActions(footer: footer)
                Task {
                    let ok = await DevGuard.shared.unlock(key: key)
                    await MainActor.run {
                        self.loading = false
                        if !ok {
                            self.errorText = "Invalid unlock key. Please try again."
                            self.rebuildActions(footer: footer)
                        }
                    }
                }
            }, for: .touchUpInside)

            row.addArrangedSubview(cancel)
            row.addArrangedSubview(unlock)
            actionsStack.addArrangedSubview(row)
            return
        }

        if let url = ContactUrls.whatsApp(response.contactWhatsapp) {
            actionsStack.addArrangedSubview(contactButton("💬  WhatsApp Support", color: UIColor(red: 0.15, green: 0.83, blue: 0.4, alpha: 1), url: url))
        }
        if let url = ContactUrls.mailto(response.contactEmail) {
            actionsStack.addArrangedSubview(contactButton("📧  Email Support", color: footer.primaryColor, url: url))
        }
        if let url = ContactUrls.tel(response.contactPhone) {
            actionsStack.addArrangedSubview(contactButton("📞  Call Support", color: UIColor(white: 1, alpha: 0.1), url: url))
        }
        if response.allowUnlock {
            let toggle = UIButton(type: .system)
            toggle.setTitle("Enter unlock key", for: .normal)
            toggle.setTitleColor(UIColor(red: 0.99, green: 0.83, blue: 0.3, alpha: 1), for: .normal)
            toggle.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            toggle.addAction(UIAction { [weak self] _ in
                self?.showUnlock = true
                self?.rebuildActions(footer: footer)
            }, for: .touchUpInside)
            actionsStack.addArrangedSubview(toggle)
        }
    }

    private func contactButton(_ title: String, color: UIColor, url: URL) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        let btn = UIButton(configuration: config)
        btn.addAction(UIAction { _ in UIApplication.shared.open(url) }, for: .touchUpInside)
        btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return btn
    }

    private func addBlob(color: UIColor, alpha: CGFloat, size: CGFloat, x: CGFloat, y: CGFloat) {
        let blob = UIView()
        blob.backgroundColor = color.withAlphaComponent(alpha)
        blob.layer.cornerRadius = 1000
        blob.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(blob, at: 0)
        NSLayoutConstraint.activate([
            blob.widthAnchor.constraint(equalTo: widthAnchor, multiplier: size),
            blob.heightAnchor.constraint(equalTo: blob.widthAnchor),
            blob.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 0).withPriority(.defaultLow),
            blob.leadingAnchor.constraint(equalTo: leadingAnchor, constant: bounds.width * x),
            blob.topAnchor.constraint(equalTo: topAnchor, constant: bounds.height * y),
        ])
        DispatchQueue.main.async {
            blob.layer.cornerRadius = blob.bounds.width / 2
        }
    }
}

final class PendingScreenView: UIView {
    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        spinner.startAnimating()
        let label = UILabel()
        label.text = message.isEmpty ? "Connecting to security server..." : message
        label.textColor = UIColor(white: 1, alpha: 0.8)
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class WarningBannerView: UIView {
    init(title: String?, message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 1, green: 0.76, blue: 0.03, alpha: 0.15)
        layer.cornerRadius = 20
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(red: 1, green: 0.63, blue: 0, alpha: 0.3).cgColor
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.semanticContentAttribute = .forceLeftToRight
        row.translatesAutoresizingMaskIntoConstraints = false
        let icon = UILabel()
        icon.text = "⚠️"
        icon.font = .systemFont(ofSize: 20)
        let col = UIStackView()
        col.axis = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.semanticContentAttribute = .forceLeftToRight
        let t = UILabel()
        t.text = (title?.isEmpty == false ? title! : "License Attention").uppercased()
        t.textColor = UIColor(red: 1, green: 0.84, blue: 0.31, alpha: 1)
        t.font = .systemFont(ofSize: 10, weight: .black)
        t.textAlignment = .left
        let m = UILabel()
        m.text = message
        m.textColor = UIColor(white: 1, alpha: 0.9)
        m.font = .systemFont(ofSize: 13, weight: .medium)
        m.numberOfLines = 0
        m.textAlignment = .left
        col.addArrangedSubview(t)
        col.addArrangedSubview(m)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(col)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private extension NSLayoutConstraint {
    func withPriority(_ p: UILayoutPriority) -> NSLayoutConstraint {
        priority = p
        return self
    }
}
