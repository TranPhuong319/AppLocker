//
//  TouchBarItems.swift
//  AppLocker
//
//  Created by Doe Phương on 14/9/26.
//

import AppKit
import Observation

// MARK: - Self-Updating TouchBar Components

@MainActor
final class SearchTouchBarItem: NSPopoverTouchBarItem, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private var isUpdatingFromState = false
    private var isPopoverShown = false

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        setupItem()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupItem()
    }

    override func showPopover(_ sender: Any?) {
        super.showPopover(sender)
        isPopoverShown = true
        if !AppState.shared.isSearchPresented {
            AppState.shared.isSearchPresented = true
        }
        searchField.window?.makeFirstResponder(searchField)
    }

    override func dismissPopover(_ sender: Any?) {
        super.dismissPopover(sender)
        isPopoverShown = false
        if AppState.shared.isSearchPresented {
            AppState.shared.isSearchPresented = false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        isUpdatingFromState = true
        AppState.shared.searchTextLockApps = field.stringValue
        isUpdatingFromState = false
    }

    private func setupItem() {
        showsCloseButton = true
        collapsedRepresentationImage = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Search"
        )
        searchField.placeholderString = String(localized: "Search apps...")
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let childTouchBar = NSTouchBar()
        let contentId = NSTouchBarItem.Identifier(identifier.rawValue + ".content")
        let customItem = NSCustomTouchBarItem(identifier: contentId)
        customItem.view = searchField
        childTouchBar.defaultItemIdentifiers = [contentId]
        self.popoverTouchBar = childTouchBar

        observeSearchState()
    }

    private func observeSearchState() {
        withObservationTracking {
            let text = AppState.shared.searchTextLockApps
            let isPresented = AppState.shared.isSearchPresented
            if !self.isUpdatingFromState && self.searchField.stringValue != text {
                self.searchField.stringValue = text
            }
            if isPresented && !self.isPopoverShown {
                self.showPopover(nil)
            } else if !isPresented && self.isPopoverShown {
                self.dismissPopover(nil)
            }
        } onChange: {
            Task { @MainActor [weak self] in self?.observeSearchState() }
        }
    }
}

@MainActor
final class MissingAppsTouchBarItem: NSButtonTouchBarItem {
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "Review missing applications"
        )
        bezelColor = .systemOrange
        target = AppState.shared
        action = #selector(AppState.openMissingApps)
        setupObservation()
    }

    private func setupObservation() {
        withObservationTracking {
            let count = AppState.shared.confirmedMissingApps.count
            self.title = "\(count)"
        } onChange: {
            Task { @MainActor [weak self] in self?.setupObservation() }
        }
    }
}

@MainActor
final class DeleteQueueTouchBarButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservation()
    }

    override var intrinsicContentSize: NSSize {
        isHidden ? .zero : super.intrinsicContentSize
    }

    private func setupObservation() {
        withObservationTracking {
            let queue = AppState.shared.deleteQueue
            self.isHidden = queue.isEmpty
            self.title = String(
                localized: "Waiting to unlock \(queue.count) application(s)..."
            )
        } onChange: {
            Task { @MainActor [weak self] in self?.setupObservation() }
        }
    }
}

@MainActor
final class LockTouchBarButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservation()
    }

    private func setupObservation() {
        withObservationTracking {
            let selected = AppState.shared.selectedToLock
            let isLocking = AppState.shared.isLocking
            self.title = String(localized: "Lock")
            self.isEnabled = !selected.isEmpty && !isLocking
        } onChange: {
            Task { @MainActor [weak self] in self?.setupObservation() }
        }
    }
}

// MARK: - NSTouchBarItem Identifiers

extension NSTouchBarItem.Identifier {
    static let addAppButtons = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppButtons")
    static let deleteQueueButtons = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.deleteQueueButtons")
    static let missingAppsButtons = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.missingAppsButtons")
    static let searchItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.searchItem")
    static let deleteQueueItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.deleteQueueItem")
    static let missingAppsItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.missingAppsItem")
    static let addAppItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppItem")
}
