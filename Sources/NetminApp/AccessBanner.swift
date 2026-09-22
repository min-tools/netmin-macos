import SwiftUI

/// Offers purchase and restore after the full-access trial has ended.
struct NetminAccessBanner: View {
    @ObservedObject private var store = NetminProStore.shared
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        // Wait for StoreKit and trial state so the expired banner cannot flash during launch.
        if store.hasResolvedEntitlement && store.hasPreparedFreeAccess && !store.hasFullAccess {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(restoreMessage ?? detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Button(isRestoring ? localized("Restoring…") : localized("Restore Purchases"), action: restore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRestoring)
                    .keyboardFocusable()
                Button(localized("Purchase")) { store.present() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRestoring)
                    .keyboardFocusable()
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(Color(nsColor: .systemOrange).opacity(0.16))
            .overlay(alignment: .top) {
                Rectangle().fill(Color(nsColor: .systemOrange).opacity(0.48)).frame(height: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    // State the transition without repeating purchase instructions.
    private var title: String {
        localized("Trial ended")
    }

    // Name the exact limit that now applies to diagnostics.
    private var detail: String {
        localized("Netmin is now limited to 5 diagnostic requests per day.")
    }

    // restore(): Sync verified purchases once and keep failure feedback inside the banner.
    private func restore() {
        // Ignore repeated clicks while StoreKit is synchronizing the account.
        guard !isRestoring else { return }
        isRestoring = true
        restoreMessage = nil
        Task { @MainActor in
            defer { isRestoring = false }
            do {
                // Leave the banner visible and explain when no active purchase exists.
                let restored = try await store.restore()
                if !restored {
                    restoreMessage = localized("No active purchase was found.")
                }
            } catch {
                // StoreKit supplies a user-readable message for synchronization failures.
                restoreMessage = error.localizedDescription
            }
        }
    }
}
