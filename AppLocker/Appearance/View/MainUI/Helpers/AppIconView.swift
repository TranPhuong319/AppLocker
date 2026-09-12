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
            if !isMissing, let cached = AppIconProvider.shared.cachedIcon(forPath: path, size: size) {
                self.image = cached
                return
            }
            self.image = AppIconProvider.shared.icon(forPath: path, size: size)
        }
    }
}
