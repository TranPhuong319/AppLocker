//
//  TouchBarBuilders.swift
//  AppLocker
//
//  Created by Doe Phương on 14/9/26.
//

import AppKit

// MARK: - TouchBar View Builders

extension TouchBarManager {
    static func makeButton(
        title: String,
        target: AnyObject?,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSButton {
        let btn = NSButton(title: title, target: target, action: action)
        btn.isBordered = true
        btn.bezelStyle = .rounded
        btn.keyEquivalent = keyEquivalent
        return btn
    }

    static func buildAddAppTouchBarContent(appState: AppState) -> NSView {
        let otherButton = makeButton(
            title: String(localized: "Others…"),
            target: appState,
            action: #selector(AppState.chooseCustomApp)
        )
        let width = otherButton.intrinsicContentSize.width + 80
        otherButton.widthAnchor.constraint(equalToConstant: width).isActive = true

        let closeButton = makeButton(
            title: String(localized: "Close"),
            target: appState,
            action: #selector(AppState.dismissAddAppSheet)
        )
        let lockButton = LockTouchBarButton(
            title: String(localized: "Lock"),
            target: appState,
            action: #selector(AppState.lockSelectedApps)
        )
        lockButton.isBordered = true
        lockButton.bezelStyle = .rounded
        lockButton.keyEquivalent = "\r"

        let centerStack = NSStackView(views: [closeButton, lockButton])
        centerStack.orientation = .horizontal
        centerStack.spacing = 6
        centerStack.alignment = .centerY

        let mainStack = NSStackView(views: [otherButton, centerStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 50
        mainStack.alignment = .centerY

        NSLayoutConstraint.activate([
            lockButton.widthAnchor.constraint(equalTo: otherButton.widthAnchor),
            closeButton.widthAnchor.constraint(equalTo: otherButton.widthAnchor)
        ])
        return mainStack
    }

    static func buildMissingAppsTouchBarContent(appState: AppState) -> NSView {
        let cancelButton = makeButton(
            title: String(localized: "Cancel"),
            target: appState,
            action: #selector(AppState.closeMissingApps)
        )
        let hideButton = makeButton(
            title: String(localized: "Hide"),
            target: appState,
            action: #selector(AppState.hideAllMissingApps)
        )
        let removeButton = makeButton(
            title: String(localized: "Remove"),
            target: appState,
            action: #selector(AppState.removeAllMissingApps),
            keyEquivalent: "\r"
        )

        let maxWidth = max(
            cancelButton.intrinsicContentSize.width,
            hideButton.intrinsicContentSize.width,
            removeButton.intrinsicContentSize.width
        ) + 80
        cancelButton.widthAnchor.constraint(equalToConstant: maxWidth).isActive = true

        let rightStack = NSStackView(views: [hideButton, removeButton])
        rightStack.orientation = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .centerY

        let mainStack = NSStackView(views: [cancelButton, rightStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 50
        mainStack.alignment = .centerY

        NSLayoutConstraint.activate([
            hideButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor),
            removeButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor)
        ])
        return mainStack
    }

    static func buildDeleteQueueButtons(appState: AppState) -> NSView {
        let unlockButton = makeButton(
            title: String(localized: "Unlock"),
            target: appState,
            action: #selector(AppState.unlockQueuedApps),
            keyEquivalent: "\r"
        )
        let clearButton = makeButton(
            title: String(localized: "Cancel"),
            target: appState,
            action: #selector(AppState.clearDeleteQueue)
        )
        let width = max(unlockButton.intrinsicContentSize.width, clearButton.intrinsicContentSize.width) + 80
        clearButton.widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView(views: [clearButton, unlockButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY

        NSLayoutConstraint.activate([
            unlockButton.widthAnchor.constraint(equalTo: clearButton.widthAnchor)
        ])
        return stack
    }

    static func buildDeleteQueueProminentButton() -> NSView {
        let button = DeleteQueueTouchBarButton(
            title: "",
            target: AppState.shared,
            action: #selector(AppState.showDeleteQueueSheet)
        )
        button.isBordered = false
        button.contentTintColor = NSColor.white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.systemRed.cgColor
        button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }
}
