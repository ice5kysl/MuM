import AppKit
import UniformTypeIdentifiers

/// 系统设置面板。底栏齿轮的 `NSPopover` 内容。
///
/// 和「显示设置」（Aa）分开：这里放的是**应用行为**（启动、文件、缩进、系统集成），
/// 那些改的是"MuM 怎么运转"；Aa 里放的是"内容长什么样"。
/// 两者性质不同、改动频率也不同，混在一个面板里会让常用项被不常用项淹没。
final class SystemSettingsPanelViewController: NSViewController {

    var onChange: ((MuMSettings) -> Void)?

    private var settings: MuMSettings
    private var toggles: [String: SettingsToggleRow] = [:]
    private var segments: [String: SettingsSegmentedRow] = [:]

    private static let columnWidth: CGFloat = 300

    init(settings: MuMSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()

        let column = SettingsControls.column(width: Self.columnWidth)

        column.addArrangedSubview(SettingsControls.section("启动", width: Self.columnWidth))
        toggles["restoresLastSession"] = SettingsToggleRow(
            title: "恢复上次打开的文件",
            isOn: settings.restoresLastSession,
            width: Self.columnWidth
        ) { [weak self] isOn in
            self?.settings.restoresLastSession = isOn
            self?.emit()
        }
        column.addArrangedSubview(toggles["restoresLastSession"]!.view)

        segments["startMode"] = SettingsSegmentedRow(
            title: "启动时的呈现方式",
            labels: MuMSettings.StartMode.allCases.map(\.title),
            selected: MuMSettings.StartMode.allCases.firstIndex(of: settings.startMode) ?? 1,
            width: Self.columnWidth
        ) { [weak self] index in
            let cases = MuMSettings.StartMode.allCases
            guard cases.indices.contains(index) else { return }
            self?.settings.startMode = cases[index]
            self?.emit()
        }
        column.addArrangedSubview(segments["startMode"]!.view)

        column.addArrangedSubview(SettingsControls.section("文件", width: Self.columnWidth))
        toggles["showsHiddenFiles"] = SettingsToggleRow(
            title: "显示隐藏文件",
            isOn: settings.showsHiddenFiles,
            hint: "以 . 开头的文件与文件夹；.git、.build 这类仍在忽略列表里",
            width: Self.columnWidth
        ) { [weak self] isOn in
            self?.settings.showsHiddenFiles = isOn
            self?.emit()
        }
        column.addArrangedSubview(toggles["showsHiddenFiles"]!.view)

        column.addArrangedSubview(SettingsControls.section("编辑器", width: Self.columnWidth))
        segments["indentWidth"] = SettingsSegmentedRow(
            title: "Tab 缩进",
            labels: ["2 空格", "4 空格"],
            selected: settings.indentWidth == 4 ? 1 : 0,
            width: Self.columnWidth
        ) { [weak self] index in
            self?.settings.indentWidth = index == 1 ? 4 : 2
            self?.emit()
        }
        column.addArrangedSubview(segments["indentWidth"]!.view)

        column.addArrangedSubview(SettingsControls.section("系统集成", width: Self.columnWidth))
        column.addArrangedSubview(defaultEditorRow())

        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
        ])

        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reset)
        NSLayoutConstraint.activate([
            reset.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            reset.topAnchor.constraint(equalTo: column.bottomAnchor, constant: 16),
            reset.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -15),
        ])

        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: Self.columnWidth + 32,
            height: view.fittingSize.height
        )
    }

    // MARK: - 默认编辑器

    /// Markdown 的 UTI。`.md` 在系统里就是这个类型（可以用 `mdls` 核）。
    /// 系统没有内置 `UTType.markdown` 常量，只能按标识符构造。
    static let markdownType = UTType("net.daringfireball.markdown") ?? .plainText

    static var isDefaultMarkdownEditor: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: markdownType) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// 这一行不是开关，是"当前状态 + 一个动作按钮"，所以单独搭
    private func defaultEditorRow() -> NSView {
        let title = NSTextField(labelWithString: "默认 Markdown 编辑器")
        title.font = .systemFont(ofSize: 12)

        let state = NSTextField(labelWithString: Self.isDefaultMarkdownEditor ? "当前是 MuM" : "当前是其他应用")
        state.font = .systemFont(ofSize: 10.5)
        state.textColor = MuMDesign.tertiaryText

        let isDefault = Self.isDefaultMarkdownEditor
        let button = NSButton(
            title: isDefault ? "已是默认" : "设为默认",
            target: self,
            action: #selector(makeDefaultEditor)
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.isEnabled = !isDefault

        let header = NSStackView(views: [title, NSView(), button])
        header.orientation = .horizontal
        header.distribution = .fill

        let texts = NSStackView(views: [header, state])
        texts.orientation = .vertical
        texts.alignment = .width
        texts.spacing = 3
        texts.translatesAutoresizingMaskIntoConstraints = false
        texts.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
        return texts
    }

    @objc private func makeDefaultEditor() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            present(title: "无法设为默认编辑器",
                    detail: "MuM 当前不是从 .app 包中运行的。请先执行 scripts/build-app.sh，用生成的 dist/MuM.app 运行。")
            return
        }

        // 唯一公开的、应用能自己调用的方式（macOS 12+）。
        // Info.plist 里的 CFBundleDocumentTypes 只保证出现在「打开方式」列表里，
        // 不会让它成为默认。
        NSWorkspace.shared.setDefaultApplication(at: bundleURL, toOpen: Self.markdownType) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.present(title: "设置失败", detail: error.localizedDescription)
                } else {
                    self?.present(title: "已设为默认编辑器",
                                  detail: "以后双击 .md 会用 MuM 打开。\n\n建议把 MuM 放进「应用程序」文件夹 —— 系统按路径记住绑定，移动位置后绑定会失效。")
                }
            }
        }
    }

    private func present(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 变更

    private func emit() {
        onChange?(settings)
    }

    @objc private func resetTapped() {
        // 默认编辑器是系统状态，不进"恢复默认"的范围
        settings.restoresLastSession = MuMSettings().restoresLastSession
        settings.startMode = MuMSettings().startMode
        settings.showsHiddenFiles = MuMSettings().showsHiddenFiles
        settings.indentWidth = MuMSettings().indentWidth

        toggles["restoresLastSession"]?.setOn(settings.restoresLastSession)
        toggles["showsHiddenFiles"]?.setOn(settings.showsHiddenFiles)
        segments["startMode"]?.select(MuMSettings.StartMode.allCases.firstIndex(of: settings.startMode) ?? 1)
        segments["indentWidth"]?.select(settings.indentWidth == 4 ? 1 : 0)

        emit()
    }

    // MARK: - 诊断钩子（UITestRunner）
    //
    // 同 SettingsPanelViewController：给自驱动测试开一道只读的门

    func debugToggle(_ key: String) -> SettingsToggleRow? { toggles[key] }
    func debugSegment(_ key: String) -> SettingsSegmentedRow? { segments[key] }
}
