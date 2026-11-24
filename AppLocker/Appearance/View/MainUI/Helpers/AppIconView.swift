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

    @State private var loadedImage: NSImage?

    var body: some View {
        let displayImage = loadedImage
            ?? AppIconProvider.shared.cachedIcon(for: path, size: size)
            ?? AppIconProvider.shared.defaultPlaceholder(size: size)

        Image(nsImage: displayImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: "\(path)_\(Int(size))_\(AppIconProvider.shared.revision)") {
                loadedImage = await AppIconProvider.shared.loadIcon(for: path, size: size)
            }
    }
}
