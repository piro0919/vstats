import AppKit

/// 設定の窓。作りは Owler（を写した Gocci）に揃えてある。左に項目名を右寄せで置き、右に操作を並べる
@MainActor
final class SettingsWindowController: NSWindowController {
    private let languagePopUp = NSPopUpButton()
    private let tokenLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton(title: Strings.removeToken, target: nil, action: nil)

    /// 見出しの幅。操作の左端を一列に揃えるための基準
    private static let labelWidth: CGFloat = 110
    private static let width: CGFloat = 420

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = Strings.settingsTitle
        window.isReleasedWhenClosed = false
        self.init(window: window)
        build()
    }

    private func build() {
        guard let window else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"

        languagePopUp.target = self
        languagePopUp.action = #selector(changeLanguage)
        for language in Language.allCases {
            languagePopUp.addItem(withTitle: language.label)
        }

        removeButton.target = self
        removeButton.action = #selector(removeToken)
        removeButton.bezelStyle = .rounded

        let updateButton = NSButton(title: Strings.checkForUpdates, target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded

        let about = NSTextField(labelWithString: "VStats \(version)")
        about.textColor = .secondaryLabelColor
        about.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [
            row(Strings.token, tokenLabel, removeButton),
            row(Strings.language, languagePopUp),
            aligned(updateButton),
            aligned(about),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let margin: CGFloat = 24
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
        ])

        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: Self.width, height: content.fittingSize.height))
    }

    func show() {
        languagePopUp.selectItem(at: Language.allCases.firstIndex(of: Language.chosen) ?? 0)
        refreshToken()
        NSApp.activate()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 操作

    @objc private func changeLanguage() {
        let index = languagePopUp.indexOfSelectedItem
        guard Language.allCases.indices.contains(index) else { return }
        Language.chosen = Language.allCases[index]
    }

    /// 消すと窓はトークンを入れる画面に戻る。入れ直すのはそちらで
    @objc private func removeToken() {
        Keychain.remove()
        refreshToken()
        NotificationCenter.default.post(name: .tokenChanged, object: nil)
    }

    @objc private func checkForUpdates() { Updater.shared.checkNow() }

    private func refreshToken() {
        let saved = Keychain.token != nil
        tokenLabel.stringValue = saved ? Strings.tokenSaved : Strings.noToken
        tokenLabel.textColor = saved ? .labelColor : .secondaryLabelColor
        removeButton.isHidden = !saved
    }

    // MARK: - 組み立て

    private func row(_ title: String, _ controls: NSView...) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        label.alignment = .right

        let stack = NSStackView(views: [label] + controls)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        return stack
    }

    /// 見出しの無い行。操作の左端を見出しのある行に揃える
    private func aligned(_ views: NSView...) -> NSView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true

        let stack = NSStackView(views: [spacer] + views)
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }
}
