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

struct BookSource: Identifiable, Codable, Equatable {
    let id: UUID
    var bookSourceName: String
    var bookSourceUrl: String
    var searchUrl: String?
    var rawJSON: String

    init(id: UUID = UUID(), bookSourceName: String, bookSourceUrl: String, searchUrl: String? = nil, rawJSON: String) {
        self.id = id
        self.bookSourceName = bookSourceName
        self.bookSourceUrl = bookSourceUrl
        self.searchUrl = searchUrl
        self.rawJSON = rawJSON
    }
}

struct BookSourceParser {
    static func parseMany(_ text: String) throws -> [BookSource] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("{") || cleaned.hasPrefix("[") else {
            let preview = String(cleaned.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            throw NSError(domain: "MiniReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "返回内容不是 JSON，可能是 404/网页/链接失效。开头：\(preview)"])
        }
        let data = Data(cleaned.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let items: [Any]
        if let array = object as? [Any] {
            items = array
        } else if let dict = object as? [String: Any], let array = dict["bookSources"] as? [Any] {
            items = array
        } else if let dict = object as? [String: Any], let array = dict["sources"] as? [Any] {
            items = array
        } else if let dict = object as? [String: Any], let array = dict["data"] as? [Any] {
            items = array
        } else {
            items = [object]
        }
        let sources = try items.compactMap { item -> BookSource? in
            guard let dict = item as? [String: Any] else { return nil }
            let rawData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            let raw = String(data: rawData, encoding: .utf8) ?? "{}"
            let name = dict["bookSourceName"] as? String
                ?? dict["sourceName"] as? String
                ?? dict["name"] as? String
                ?? "未命名书源"
            let url = dict["bookSourceUrl"] as? String
                ?? dict["sourceUrl"] as? String
                ?? dict["url"] as? String
                ?? ""
            let search = dict["searchUrl"] as? String
            return BookSource(bookSourceName: name, bookSourceUrl: url, searchUrl: search, rawJSON: raw)
        }
        guard !sources.isEmpty else {
            throw NSError(domain: "MiniReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "JSON 能读取，但里面没有识别到阅读 3.0 书源。"])
        }
        return sources
    }
}

final class ReaderStore: ObservableObject {
    @Published var sources: [ReaderSource] { didSet { saveSources() } }
    @Published var bookSources: [BookSource] { didSet { saveBookSources() } }
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
        if let data = UserDefaults.standard.data(forKey: "bookSources"),
           let decoded = try? JSONDecoder().decode([BookSource].self, from: data) {
            bookSources = decoded
        } else {
            bookSources = []
        }
        homeURL = UserDefaults.standard.string(forKey: "homeURL") ?? "https://arekert.github.io/read/"
    }

    private func saveSources() {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: "sources")
        }
    }

    private func saveBookSources() {
        if let data = try? JSONEncoder().encode(bookSources) {
            UserDefaults.standard.set(data, forKey: "bookSources")
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
    @State private var showBookSources = false
    @State private var showImportBookSource = false
    @State private var showBookSearch = false
    @State private var fullScreen = false
    @State private var showWeb = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if showWeb {
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
                } else {
                    nativeHome
                }
            }
            .navigationTitle(showWeb ? (pageTitle.isEmpty ? "MiniReader" : pageTitle) : "MiniReader")
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
                        Button("网页入口源", systemImage: "books.vertical") { showSources = true }
                        Button("添加网页入口", systemImage: "plus") { showAddSource = true }
                        Button("阅读书源 JSON", systemImage: "doc.text.magnifyingglass") { showBookSources = true }
                        Button("导入书源 JSON", systemImage: "square.and.arrow.down") { showImportBookSource = true }
                        Button("书源搜索", systemImage: "magnifyingglass.circle") { showBookSearch = true }
                        if showWeb {
                            Button("返回首页", systemImage: "house") { showWeb = false; fullScreen = false }
                            Button("设为网页首页", systemImage: "house") { setCurrentAsHome() }
                            Button("Safari 打开", systemImage: "safari") { openInSafari() }
                            Button(fullScreen ? "退出全屏" : "全屏阅读", systemImage: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { fullScreen.toggle() }
                        }
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
            .sheet(isPresented: $showBookSources) { BookSourceListView() }
            .sheet(isPresented: $showImportBookSource) { ImportBookSourceView() }
            .sheet(isPresented: $showBookSearch) { BookSearchView(open: openURLString) }
            .onAppear { addressText = currentURL.absoluteString }
            .statusBarHidden(fullScreen)
        }
    }

    private var nativeHome: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("这不是网页壳了")
                        .font(.title2.bold())
                    Text("导入书源后，请点下面的“搜索小说”，输入书名。现在先显示搜索结果链接；下一步继续做详情、目录、正文阅读。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("书源") {
                HStack {
                    Label("已导入书源", systemImage: "doc.text")
                    Spacer()
                    Text("\(store.bookSources.count) 个").foregroundStyle(.secondary)
                }
                Button { showImportBookSource = true } label: {
                    Label("导入阅读 3.0 JSON", systemImage: "square.and.arrow.down")
                }
                Button { showBookSources = true } label: {
                    Label("查看已导入书源", systemImage: "list.bullet.rectangle")
                }
            }

            Section("找小说") {
                Button { showBookSearch = true } label: {
                    Label("搜索小说", systemImage: "magnifyingglass")
                        .font(.headline)
                }
                if store.bookSources.isEmpty {
                    Text("先导入书源，否则搜索不到小说。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("已导入书源后，从这里输入小说名搜索。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("网页模式") {
                Button { openURLString(store.homeURL) } label: {
                    Label("打开网页阅读入口", systemImage: "safari")
                }
                Text("网页模式只是备用，不再作为默认首页。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            showWeb = true
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

struct BookSourceListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BookSource?

    var body: some View {
        NavigationStack {
            List {
                if store.bookSources.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                        Text("暂无阅读书源").font(.headline)
                        Text("从右上角导入阅读 3.0 JSON 书源").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                } else {
                    ForEach(store.bookSources) { source in
                        Button { selected = source } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.bookSourceName).font(.headline)
                                Text(source.bookSourceUrl.isEmpty ? "无 bookSourceUrl" : source.bookSourceUrl)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let search = source.searchUrl, !search.isEmpty {
                                    Text("searchUrl: \(search)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .onDelete { store.bookSources.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("阅读书源")
            .navigationBarItems(leading: Button("关闭") { dismiss() }, trailing: EditButton())
            .sheet(item: $selected) { source in
                BookSourceDetailView(source: source)
            }
        }
    }
}

struct BookSourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let source: BookSource

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    LabeledContent("名称", value: source.bookSourceName)
                    LabeledContent("地址", value: source.bookSourceUrl)
                    if let search = source.searchUrl { LabeledContent("搜索", value: search) }
                }
                Section("原始 JSON") {
                    ScrollView(.horizontal) {
                        Text(source.rawJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(source.bookSourceName)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

struct ImportBookSourceView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var message = ""
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("导入方式") {
                    Text("支持粘贴阅读 3.0 书源 JSON 数组/对象，或输入一个 JSON URL。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $input)
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !message.isEmpty {
                    Section("结果") { Text(message).font(.caption) }
                }
                Section {
                    Button(importing ? "导入中…" : "导入") { Task { await importSources() } }
                        .disabled(importing || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("导入书源 JSON")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        }
    }

    private func importSources() async {
        importing = true
        defer { importing = false }
        do {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonText: String
            if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
                guard let url = URL(string: trimmed) else { throw NSError(domain: "MiniReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"]) }
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(domain: "MiniReader", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "下载失败，HTTP \(http.statusCode)。这个书源链接可能失效或路径写错。"])
                }
                jsonText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) ?? ""
            } else {
                jsonText = trimmed
            }
            let parsed = try BookSourceParser.parseMany(jsonText)
            var added = 0
            for source in parsed {
                if !store.bookSources.contains(where: { $0.bookSourceName == source.bookSourceName && $0.bookSourceUrl == source.bookSourceUrl }) {
                    store.bookSources.append(source)
                    added += 1
                }
            }
            message = "解析 \(parsed.count) 个，新增 \(added) 个。"
            if added > 0 { input = "" }
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
}

struct SearchCandidate: Identifiable {
    let id = UUID()
    let title: String
    let href: String
}

struct BookSearchView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let open: (String) -> Void

    @State private var selectedSourceID: UUID?
    @State private var keyword = ""
    @State private var searchURL = ""
    @State private var status = ""
    @State private var running = false
    @State private var candidates: [SearchCandidate] = []

    private var selectedSource: BookSource? {
        store.bookSources.first(where: { $0.id == selectedSourceID })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("书源") {
                        if store.bookSources.isEmpty {
                            Text("暂无已导入 JSON 书源，请先导入。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("选择书源", selection: Binding(
                                get: { selectedSourceID ?? store.bookSources.first?.id },
                                set: { selectedSourceID = $0 }
                            )) {
                                ForEach(store.bookSources) { s in
                                    Text(s.bookSourceName).tag(Optional(s.id))
                                }
                            }
                        }
                    }

                    Section("关键词") {
                        TextField("输入小说名", text: $keyword)
                        Button(running ? "搜索中…" : "开始搜索") { Task { await runSearch() } }
                            .disabled(running || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.bookSources.isEmpty)
                    }

                    if !searchURL.isEmpty {
                        Section("搜索 URL") {
                            Text(searchURL).font(.caption2).textSelection(.enabled)
                        }
                    }

                    if !status.isEmpty {
                        Section("状态") { Text(status).font(.caption) }
                    }
                }

                if !candidates.isEmpty {
                    List(candidates) { item in
                        Button {
                            open(item.href)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title.isEmpty ? "(无标题)" : item.title)
                                Text(item.href).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("书源搜索")
            .navigationBarItems(leading: Button("关闭") { dismiss() })
            .onAppear {
                if selectedSourceID == nil { selectedSourceID = store.bookSources.first?.id }
            }
        }
    }

    private func buildSearchURL(source: BookSource, keyword: String) -> String {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let template = source.searchUrl ?? source.bookSourceUrl
        return template
            .replacingOccurrences(of: "{{key}}", with: encoded)
            .replacingOccurrences(of: "{{keyword}}", with: encoded)
            .replacingOccurrences(of: "{{searchKey}}", with: encoded)
    }

    private func absoluteURL(base: URL, href: String) -> String {
        if let u = URL(string: href), u.scheme != nil { return u.absoluteString }
        if let u = URL(string: href, relativeTo: base)?.absoluteURL { return u.absoluteString }
        return href
    }

    private func runSearch() async {
        guard let source = selectedSource else {
            status = "请先选择书源"
            return
        }
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status = "请输入关键词"
            return
        }
        let urlString = buildSearchURL(source: source, keyword: key)
        searchURL = urlString
        guard let url = URL(string: urlString) else {
            status = "搜索 URL 无效"
            return
        }

        running = true
        defer { running = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                status = "响应解码失败"
                return
            }

            let matches = htmlMatches(in: html)
            let base = URL(string: source.bookSourceUrl) ?? url
            candidates = matches.prefix(60).map { m in
                SearchCandidate(title: m.0, href: absoluteURL(base: base, href: m.1))
            }
            status = "抓取成功：候选 \(candidates.count) 条（MVP 粗匹配）"
        } catch {
            status = "搜索失败：\(error.localizedDescription)"
        }
    }

    private func htmlMatches(in html: String) -> [(String, String)] {
        var result: [(String, String)] = []
        let pattern = "<a[^>]*href=[\\\"']([^\\\"'#]+)[\\\"'][^>]*>(.*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: html, options: [], range: range) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 3 else { return }
            let href = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            var title = ns.substring(with: m.range(at: 2))
            title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "&nbsp;", with: " ")
            title = title.replacingOccurrences(of: "&amp;", with: "&")
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { return }
            if title.count > 0 {
                result.append((title, href))
            }
        }
        return result
    }
}
