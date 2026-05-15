import SwiftUI
import WebKit
import UIKit

struct ReaderSource: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

final class ReaderStore: ObservableObject {
    @Published var sources: [ReaderSource] { didSet { saveSources() } }
    @Published var homeURL: String { didSet { UserDefaults.standard.set(homeURL, forKey: "homeURL") } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "sources"),
           let decoded = try? JSONDecoder().decode([ReaderSource].self, from: data),
           !decoded.isEmpty {
            sources = decoded
        } else {
            let defaultSources = [
                ReaderSource(name: "栖阅", url: "https://arekert.github.io/read/"),
                ReaderSource(name: "GitHub", url: "https://github.com/AREKERT/read/releases")
            ]
            sources = defaultSources
        }
        homeURL = UserDefaults.standard.string(forKey: "homeURL") ?? "https://arekert.github.io/read/"
    }

    private func saveSources() {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: "sources")
        }
    }
}

@main
struct MiniReaderApp: App {
    @StateObject private var store = ReaderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var currentURL: URL = URL(string: UserDefaults.standard.string(forKey: "homeURL") ?? "https://arekert.github.io/read/")!
    @State private var addressText = ""
    @State private var pageTitle = "MiniReader"
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var loading = false
    @State private var reloadToken = UUID()
    @State private var goBackToken = UUID()
    @State private var goForwardToken = UUID()
    @State private var showSources = false
    @State private var showAddress = false
    @State private var showAddSource = false
    @State private var fullScreen = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WebView(
                    url: currentURL,
                    reloadToken: reloadToken,
                    goBackToken: goBackToken,
                    goForwardToken: goForwardToken,
                    pageTitle: $pageTitle,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    loading: $loading
                )
                .ignoresSafeArea(edges: fullScreen ? .all : .bottom)

                if !fullScreen {
                    bottomBar
                }
            }
            .navigationTitle(pageTitle.isEmpty ? "MiniReader" : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSources = true } label: {
                        Image(systemName: "books.vertical")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("输入地址", systemImage: "link") { showAddress = true }
                        Button("添加阅读源", systemImage: "plus") { showAddSource = true }
                        Button("设为首页", systemImage: "house") { setCurrentAsHome() }
                        Button("Safari 打开", systemImage: "safari") { openInSafari() }
                        Button(fullScreen ? "退出全屏" : "全屏阅读", systemImage: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { fullScreen.toggle() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .top) {
                if loading && !fullScreen {
                    ProgressView().padding(.top, 4)
                }
            }
            .sheet(isPresented: $showSources) { SourceListView(open: openURLString) }
            .sheet(isPresented: $showAddress) { AddressSheet(addressText: $addressText, open: openURLString) }
            .sheet(isPresented: $showAddSource) { AddSourceView() }
            .onAppear { addressText = currentURL.absoluteString }
            .statusBarHidden(fullScreen)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 22) {
            Button { goBackToken = UUID() } label: { Image(systemName: "chevron.left") }.disabled(!canGoBack)
            Button { goForwardToken = UUID() } label: { Image(systemName: "chevron.right") }.disabled(!canGoForward)
            Button { openURLString(store.homeURL) } label: { Image(systemName: "house") }
            Button { reloadToken = UUID() } label: { Image(systemName: "arrow.clockwise") }
            Button { showAddress = true } label: { Image(systemName: "magnifyingglass") }
            Button { fullScreen = true } label: { Image(systemName: "rectangle.expand.vertical") }
        }
        .font(.system(size: 18, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 10)
    }

    private func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://" + trimmed }
        return "https://www.baidu.com/s?wd=" + trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    }

    private func openURLString(_ text: String) {
        let normalized = normalize(text)
        if let url = URL(string: normalized) {
            currentURL = url
            addressText = normalized
        }
    }

    private func setCurrentAsHome() {
        store.homeURL = currentURL.absoluteString
    }

    private func openInSafari() {
        UIApplication.shared.open(currentURL)
    }
}

struct SourceListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let open: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sources) { source in
                    Button {
                        open(source.url)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.headline)
                            Text(source.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { store.sources.remove(atOffsets: $0) }
            }
            .navigationTitle("阅读源")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }
}

struct AddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var addressText: String
    let open: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("输入网址或搜索关键词") {
                    TextField("https://example.com", text: $addressText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("打开") {
                    open(addressText)
                    dismiss()
                }
            }
            .navigationTitle("打开")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct AddSourceView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读源") {
                    TextField("名称", text: $name)
                    TextField("网址", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("保存") {
                    let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : name
                    var finalURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalURL.contains("://") { finalURL = "https://" + finalURL }
                    store.sources.append(ReaderSource(name: finalName, url: finalURL))
                    dismiss()
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("添加阅读源")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID
    let goBackToken: UUID
    let goForwardToken: UUID
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView
        webView.addObserver(context.coordinator, forKeyPath: "title", options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "canGoBack", options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "canGoForward", options: .new, context: nil)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
        if context.coordinator.lastGoBackToken != goBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            if webView.canGoBack { webView.goBack() }
        }
        if context.coordinator.lastGoForwardToken != goForwardToken {
            context.coordinator.lastGoForwardToken = goForwardToken
            if webView.canGoForward { webView.goForward() }
        }
        if webView.url != url && context.coordinator.currentRequestedURL != url {
            context.coordinator.currentRequestedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.removeObserver(coordinator, forKeyPath: "title")
        uiView.removeObserver(coordinator, forKeyPath: "canGoBack")
        uiView.removeObserver(coordinator, forKeyPath: "canGoForward")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        weak var webView: WKWebView?
        var currentRequestedURL: URL?
        var lastReloadToken = UUID()
        var lastGoBackToken = UUID()
        var lastGoForwardToken = UUID()

        init(_ parent: WebView) { self.parent = parent }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            DispatchQueue.main.async {
                self.parent.pageTitle = self.webView?.title ?? "MiniReader"
                self.parent.canGoBack = self.webView?.canGoBack ?? false
                self.parent.canGoForward = self.webView?.canGoForward ?? false
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.pageTitle = webView.title ?? "MiniReader"
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.loading = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.loading = false }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
