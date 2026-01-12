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

    var body: some View {
        Image(nsImage: AppIconProvider.shared.icon(forPath: path, size: size))
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(6)
    }
}
