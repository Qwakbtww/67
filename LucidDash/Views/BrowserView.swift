import SwiftUI
import WebKit

/// Shared state for an in-app browser tab.
@MainActor
final class WebViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?
    var loadedURL: URL?
    /// Called with a local file URL whenever the page downloads a file.
    var onDownload: ((URL, String) -> Void)?
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

    /// The visible text of the current page (main frame).
    func pageText(_ completion: @escaping (String?) -> Void) {
        guard let webView else { return completion(nil) }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
            completion(result as? String)
        }
    }
}

/// A browser screen with back/forward/home/reload and optional extra toolbar items.
struct BrowserScreen<Extra: View>: View {
    let fallbackTitle: String
    let homeURL: URL
    @ObservedObject var model: WebViewModel
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        NavigationStack {
            WebView(model: model, url: homeURL)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading {
                        ProgressView(value: model.progress).progressViewStyle(.linear)
                    }
                }
                .navigationTitle(model.title.isEmpty ? fallbackTitle : model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { model.webView?.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                        Button { model.webView?.goForward() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!model.canGoForward)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        extra()
                        Button { model.webView?.load(URLRequest(url: homeURL)) } label: { Image(systemName: "house") }
                        Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
    }
}

struct WebView: UIViewRepresentable {
    let model: WebViewModel
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Default store keeps logins between launches.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        model.attach(webView)
        model.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the address is changed in Settings.
        if model.loadedURL != url {
            model.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let model: WebViewModel
        private var destinations: [ObjectIdentifier: (url: URL, name: String)] = [:]

        init(model: WebViewModel) { self.model = model }

        @objc func refresh(_ sender: UIRefreshControl) {
            model.webView?.reload()
            sender.endRefreshing()
        }

        // MARK: Navigation → downloads

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response
            let mime = response.mimeType?.lowercased() ?? ""
            let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
            let isFile = disposition.contains("attachment") || mime == "text/csv"
                || mime == "application/csv" || mime == "application/octet-stream"
            decisionHandler(isFile || !navigationResponse.canShowMIMEType ? .download : .allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // Links that open a new window load in this one instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(suggestedFilename.isEmpty ? "download.csv" : suggestedFilename)
            destinations[ObjectIdentifier(download)] = (destination, suggestedFilename)
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let file = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            model.onDownload?(file.url, file.name)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            destinations.removeValue(forKey: ObjectIdentifier(download))
        }
    }
}
