import UIKit

struct BrandingFooter {
    let label: String
    let brand: String
    let url: String
    let hidePoweredBy: Bool
    let primaryColor: UIColor
    let accentColor: UIColor
}

enum BrandingHelpers {
    static func resolveFooter(_ branding: LockScreenBranding?) -> BrandingFooter {
        let hasCustom = branding != nil && (
            !(branding?.brandName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ||
            !(branding?.logoUrl?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        )
        let primary = color(from: branding?.primaryColor, fallback: "#D32F2F")
        let accent = color(from: branding?.accentColor ?? branding?.primaryColor, fallback: "#B71C1C")
        return BrandingFooter(
            label: hasCustom ? "Powered by" : "Secured by",
            brand: hasCustom ? (branding?.brandName?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "DevGuard") : "DevGuard",
            url: hasCustom && !(branding?.websiteUrl?.isEmpty ?? true) ? branding!.websiteUrl! : "https://devguard.uk",
            hidePoweredBy: branding?.hidePoweredBy == true,
            primaryColor: primary,
            accentColor: accent
        )
    }

    static func color(from hex: String?, fallback: String) -> UIColor {
        let raw = hex?.trimmingCharacters(in: .whitespaces) ?? fallback
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb), cleaned.count == 6 else {
            return color(from: nil, fallback: fallback)
        }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum ContactUrls {
    static func whatsApp(_ raw: String) -> URL? {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }

    static func mailto(_ email: String) -> URL? {
        guard !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    static func tel(_ phone: String) -> URL? {
        let cleaned = phone.filter { $0.isNumber || $0 == "+" }
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel:\(cleaned)")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
