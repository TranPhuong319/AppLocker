//
//  LockingPopupSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct LockingPopupSheet: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.headline)
        }
        .padding()
        .frame(minWidth: 200, minHeight: 100)
    }
}
