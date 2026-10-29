import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdMobConsentManager: ObservableObject {
    static let shared = AdMobConsentManager()

    @Published private(set) var canRequestAds = false
    @Published private(set) var privacyOptionsRequired = false

    private var didStartConsentFlow = false
    private var didStartAdsSDK = false

    private init() {}

    func startIfNeeded() async {
        guard !didStartConsentFlow else { return }
        didStartConsentFlow = true

        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("AdMob consent information update failed: \(error.localizedDescription)")
                }

                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                } catch {
                    print("AdMob consent form could not be presented: \(error.localizedDescription)")
                }

                self.privacyOptionsRequired =
                    ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                self.canRequestAds = ConsentInformation.shared.canRequestAds

                guard self.canRequestAds, !self.didStartAdsSDK else { return }
                self.didStartAdsSDK = true
                MobileAds.shared.start()
            }
        }
    }

    func presentPrivacyOptions() async {
        guard privacyOptionsRequired else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            privacyOptionsRequired =
                ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            canRequestAds = ConsentInformation.shared.canRequestAds
        } catch {
            print("AdMob privacy options form failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
private final class NativeAdModel: NSObject, ObservableObject, NativeAdLoaderDelegate, NativeAdDelegate {
    @Published private(set) var nativeAd: NativeAd?
    private var adLoader: AdLoader?
    private var hasRequested = false

    func loadIfNeeded() {
        guard !hasRequested, AdMobConsentManager.shared.canRequestAds else { return }
        hasRequested = true

        #if DEBUG
        // Google's dedicated native test unit prevents accidental production-ad clicks in development.
        let unitID = "ca-app-pub-3940256099942544/3986624511"
        #else
        let unitID = "ca-app-pub-9917450718827221/5187339847"
        #endif

        let loader = AdLoader(
            adUnitID: unitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        nativeAd.delegate = self
        self.nativeAd = nativeAd
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("AdMob native ad failed to load: \(error.localizedDescription)")
        hasRequested = false
    }
}

struct NativeAdCard: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var consentManager = AdMobConsentManager.shared
    @StateObject private var model = NativeAdModel()

    var body: some View {
        Group {
            if consentManager.canRequestAds, let nativeAd = model.nativeAd {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SPONSORED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                        Spacer()
                        Text("Ad")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.secondaryAccent.opacity(0.65), lineWidth: 1))
                    }
                    .foregroundStyle(theme.secondaryAccent)

                    NativeAdViewRepresentable(nativeAd: nativeAd)
                        .frame(height: 118)
                }
                .padding(13)
                .background(theme.surface, in: theme.panelShape)
                .overlay { theme.panelShape.stroke(theme.secondaryAccent.opacity(0.22), lineWidth: 1) }
                .accessibilityElement(children: .contain)
            } else {
                EmptyView()
            }
        }
        .task {
            await Task.yield()
            model.loadIfNeeded()
        }
        .onChange(of: consentManager.canRequestAds) { _, canRequest in
            if canRequest { model.loadIfNeeded() }
        }
    }
}

private struct NativeAdViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 10
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54)
        ])

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        headline.textColor = .white
        headline.numberOfLines = 2

        let advertiser = UILabel()
        advertiser.font = .systemFont(ofSize: 11, weight: .medium)
        advertiser.textColor = UIColor.white.withAlphaComponent(0.65)
        advertiser.numberOfLines = 1

        let body = UILabel()
        body.font = .systemFont(ofSize: 12)
        body.textColor = UIColor.white.withAlphaComponent(0.78)
        body.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [headline, advertiser, body])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .fill

        let topRow = UIStackView(arrangedSubviews: [iconView, textStack])
        topRow.axis = .horizontal
        topRow.spacing = 11
        topRow.alignment = .top

        let callToAction = UIButton(type: .system)
        callToAction.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        callToAction.setTitleColor(.black, for: .normal)
        callToAction.backgroundColor = UIColor(red: 0.98, green: 0.70, blue: 0.34, alpha: 1)
        callToAction.layer.cornerRadius = 9
        callToAction.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        // The SDK's NativeAdView must handle interaction tracking.
        callToAction.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [topRow, callToAction])
        stack.axis = .vertical
        stack.spacing = 9
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -2)
        ])

        adView.iconView = iconView
        adView.headlineView = headline
        adView.advertiserView = advertiser
        adView.bodyView = body
        adView.callToActionView = callToAction
        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        (adView.advertiserView as? UILabel)?.text = nativeAd.advertiser
        (adView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)

        adView.bodyView?.isHidden = nativeAd.body == nil
        adView.advertiserView?.isHidden = nativeAd.advertiser == nil
        adView.iconView?.isHidden = nativeAd.icon == nil
        adView.callToActionView?.isHidden = nativeAd.callToAction == nil
        adView.nativeAd = nativeAd
    }
}
