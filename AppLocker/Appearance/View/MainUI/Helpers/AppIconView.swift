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

    var body: some View {
        Image(nsImage: AppIconProvider.shared.icon(for: path, size: size))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
