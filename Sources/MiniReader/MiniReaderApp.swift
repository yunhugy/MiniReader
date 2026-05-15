import SwiftUI
import WebKit

@main
struct MiniReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var urlText: String = UserDefaults.standard.string(forKey: "homeURL") ?? "https://arekert.github.io/read/"
    @State private var currentURL: URL = URL(string: UserDefaults.standard.string(forKey: "homeURL") ?? "https://arekert.github.io/read/")!
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            WebView(url: currentURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("MiniReader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("地址") { showSettings = true }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        Form {
                            Section("阅读站点 / VPS 地址") {
                                TextField("https://example.com", text: $urlText)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            Section {
                                Button("保存并打开") {
                                    var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !text.contains("://") { text = "https://" + text }
                                    if let url = URL(string: text) {
                                        UserDefaults.standard.set(text, forKey: "homeURL")
                                        currentURL = url
                                        showSettings = false
                                    }
                                }
                            }
                        }
                        .navigationTitle("设置")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showSettings = false } } }
                    }
                }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
