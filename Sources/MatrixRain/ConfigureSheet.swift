import AppKit

/// The "Options…" sheet, built in code. Edits stay in the controls until OK; Cancel discards them.
@MainActor
final class ConfigureSheetController: NSObject {
    let window: NSWindow
    let speedSlider: NSSlider
    let glyphSizeSlider: NSSlider
    let colorWell: NSColorWell
    let bloomCheckbox: NSButton
    private let onSave: (Settings) -> Void

    init(onSave: @escaping (Settings) -> Void) {
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: true)
        speedSlider = NSSlider(value: Settings.defaultSpeed,
                               minValue: Settings.speedRange.lowerBound,
                               maxValue: Settings.speedRange.upperBound,
                               target: nil, action: nil)
        glyphSizeSlider = NSSlider(value: Settings.defaultGlyphSize,
                                   minValue: Settings.glyphSizeRange.lowerBound,
                                   maxValue: Settings.glyphSizeRange.upperBound,
                                 target: nil, action: nil)
        colorWell = NSColorWell()
        bloomCheckbox = NSButton(checkboxWithTitle: "Glow (bloom)", target: nil, action: nil)
        super.init()
        buildLayout()
    }

    func present(settings: Settings) -> NSWindow {
        load(settings)
        return window
    }

    func load(_ settings: Settings) {
        speedSlider.doubleValue = settings.speed
        glyphSizeSlider.doubleValue = settings.glyphSize
        colorWell.color = NSColor(srgbRed: settings.color.red, green: settings.color.green,
                                  blue: settings.color.blue, alpha: 1)
        bloomCheckbox.state = settings.bloom ? .on : .off
    }

    var editedSettings: Settings {
        let fallback = Settings.defaultColor
        let color = colorWell.color.usingColorSpace(.sRGB)
        return Settings(
            speed: speedSlider.doubleValue,
            glyphSize: glyphSizeSlider.doubleValue,
            color: Settings.RGB(red: color.map { Double($0.redComponent) } ?? fallback.red,
                                green: color.map { Double($0.greenComponent) } ?? fallback.green,
                                blue: color.map { Double($0.blueComponent) } ?? fallback.blue),
            bloom: bloomCheckbox.state == .on
        )
    }

    @objc func ok(_ sender: Any?) {
        onSave(editedSettings)
        close()
    }

    @objc func cancel(_ sender: Any?) {
        close()
    }

    private func close() {
        colorWell.deactivate()
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.orderOut(nil)
        }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    private func buildLayout() {
        let okButton = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Fall speed:"), speedSlider],
            [NSTextField(labelWithString: "Glyph size:"), glyphSizeSlider],
            [NSTextField(labelWithString: "Color:"), colorWell],
            [NSGridCell.emptyContentView, bloomCheckbox],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.yPlacement = .center
        speedSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        glyphSizeSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let buttons = NSStackView(views: [cancelButton, okButton])
        buttons.spacing = 12
        buttons.setHuggingPriority(.defaultHigh, for: .horizontal)

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        window.contentView = container
        window.setContentSize(container.fittingSize)
    }
}
