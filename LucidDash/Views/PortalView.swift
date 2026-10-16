import SwiftUI
import WebKit

/// Shows Lucid's own web dashboard. Login cookies persist in the app's default
/// website data store, so you normally only sign in once.
struct PortalView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = WebViewModel()

    var body: some View {
        NavigationStack {
            WebView(model: model, url: settings.resolvedPortalURL)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading {
                        ProgressView(value: model.progress)
                            .progressViewStyle(.linear)
                    }
                }
                .navigationTitle(model.title.isEmpty ? "Lucid Portal" : model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { model.webView?.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                        Button { model.webView?.goForward() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!model.canGoForward)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            model.webView?.load(URLRequest(url: settings.resolvedPortalURL))
                        } label: { Image(systemName: "house") }
                        Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
    }
}

@MainActor
final class WebViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?
    var loadedURL: URL?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        self.webView = webView
        observations = [
            webView.observe(\.isLoading) { [weak self] wv, _ in Task { @MainActor in self?.isLoading = wv.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in Task { @MainActor in self?.progress = wv.estimatedProgress } },
            webView.observe(\.title) { [weak self] wv, _ in Task { @MainActor in self?.title = wv.title ?? "" } },
            webView.observe(\.canGoBack) { [weak self] wv, _ in Task { @MainActor in self?.canGoBack = wv.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] wv, _ in Task { @MainActor in self?.canGoForward = wv.canGoForward } },
        ]
    }
}

private struct WebView: UIViewRepresentable {
    let model: WebViewModel
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        model.attach(webView)
        model.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the portal address is changed in Settings.
        if model.loadedURL != url {
            model.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func refresh(_ sender: UIRefreshControl) {
            (sender.superview?.superview as? WKWebView)?.reload()
            sender.endRefreshing()
        }
    }
}
