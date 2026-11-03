//
//  SettingsPaneHeader.swift
//  Ice
//

import SwiftUI

struct SettingsPaneHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        VStack(spacing: 12) {
            icon
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        if systemImage == "rectangle.bottomthird.inset.filled" {
            ZStack {
                RoundedRectangle(cornerRadius: 5).strokeBorder(lineWidth: 3)
                Rectangle().frame(height: 3).offset(y: -9)
                RoundedRectangle(cornerRadius: 1).frame(width: 26, height: 7).offset(y: 7)
            }
            .frame(width: 40, height: 32)
        } else {
            Image(systemName: systemImage)
        }
    }
}
