//
//  TouchBarItems.swift
//  AppLocker
//
//  Created by Doe Phương on 14/9/26.
//

import AppKit
import Observation

@MainActor
func observeOnMainActor<Owner: AnyObject & Sendable>(
    owner: Owner,
    apply: @escaping @MainActor (Owner) -> Void
) {
    withObservationTracking {
        apply(owner)
    } onChange: { [weak owner] in
        Task { @MainActor in
            guard let owner else { return }
            observeOnMainActor(owner: owner, apply: apply)
        }
    }
}

// MARK: - Search Popover TouchBar Item

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
        collapsedRepresentationImage = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: String(localized: "Search")
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

        observeOnMainActor(owner: self) { item in
            let text = AppState.shared.searchTextLockApps
            let isPresented = AppState.shared.isSearchPresented
            if !item.isUpdatingFromState && item.searchField.stringValue != text {
                item.searchField.stringValue = text
            }
            if isPresented && !item.isPopoverShown {
                item.showPopover(nil)
            } else if !isPresented && item.isPopoverShown {
                item.dismissPopover(nil)
            }
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
    static let resumeProtectionItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.resumeProtectionItem")
    static let addAppItem = NSTouchBarItem.Identifier("com.TranPhuong319.AppLocker.addAppItem")
}
