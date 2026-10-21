//
//  AppIconView.swift
//  AppLocker
//
//  Created by Doe Phương on 11/1/26.
//

import SwiftUI

struct AppIconView: View {
    let path: String
    let size: CGFloat
    var isMissing: Bool = false
    @State private var image: NSImage?

    init(path: String, size: CGFloat, isMissing: Bool = false) {
        self.path = path
        self.size = size
        self.isMissing = isMissing
        _image = State(initialValue: AppIconProvider.shared.cachedIcon(for: path, size: size))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: "\(path)_\(isMissing)") {
            self.image = AppIconProvider.shared.icon(for: path, size: size)
        }
    }
}
