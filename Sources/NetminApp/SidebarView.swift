import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var listAppearanceReady = false
    @State private var collapsedGroups: Set<String>
    private static let collapsedGroupsKey = "NetminCollapsedToolGroups"

    init(model: AppModel) {
        self.model = model
        _collapsedGroups = State(initialValue: Set(
            UserDefaults.standard.stringArray(forKey: Self.collapsedGroupsKey) ?? []
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                placeholder: localizedFormat("Filter %lld tools", Int64(model.tools.count)),
                text: $model.sidebarQuery,
                trailing: "⌘K",
                focusOnWindowOpen: true,
                textVerticalOffset: 0
            )
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            // A native selection list is one Tab stop and owns arrow-key navigation, scrolling,
            // focus transfer and accessibility without manually moving focus between views.
            List(selection: listAppearanceReady ? sidebarSelection : .constant(nil)) {
                ForEach(Array(model.visibleGroups.enumerated()), id: \.element.id) { index, group in
                    Section(isExpanded: expansionBinding(for: group.id)) {
                        ForEach(group.tools) { tool in
                            SidebarRow(
                                tool: tool,
                                selected: model.selectedToolID == tool.id,
                                isFavorite: model.isFavorite(tool),
                                toggleFavorite: { model.toggleFavorite(tool) }
                            )
                                .tag(tool.id)
                                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        SectionLabel(group.name)
                            .padding(.leading, 4)
                            .padding(.top, index == 0 ? 6 : 14)
                            .padding(.bottom, 6)
                            .background(SidebarListSelectionAppearance {
                                listAppearanceReady = true
                            })
                    }
                }

                if model.visibleGroups.isEmpty {
                    Text("No matching tools")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 16)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .focusEffectDisabled()
            .accessibilityLabel(localized("Tools"))
            .animation(nil, value: listAppearanceReady)
            .animation(nil, value: model.favoriteToolIDs)
        }
        .background(.regularMaterial)
        .onChange(of: model.sidebarQuery) {
            let query = model.sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let firstMatch = model.visibleGroups.first?.tools.first,
                  firstMatch.id != model.selectedToolID else { return }
            model.select(firstMatch)
        }
    }

    /// Collapse immediately. Animating lazy list rows can briefly overlap the following header.
    private func expansionBinding(for groupID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(groupID) },
            set: { expanded in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    var updated = collapsedGroups
                    if expanded {
                        updated.remove(groupID)
                    } else {
                        updated.insert(groupID)
                    }
                    collapsedGroups = updated
                    UserDefaults.standard.set(updated.sorted(), forKey: Self.collapsedGroupsKey)
                }
            }
        )
    }

    /// Hides an off-filter selection from the list while leaving the current tool open until the
    /// user chooses a visible result. `List` then selects and reveals rows using native behavior.
    private var sidebarSelection: Binding<String?> {
        Binding(
            get: {
                let visibleIDs = model.visibleGroups.lazy.flatMap(\.tools).map(\.id)
                guard let selectedID = model.selectedToolID,
                      visibleIDs.contains(selectedID) else { return nil }
                return selectedID
            },
            set: { selectedID in
                guard let selectedID,
                      selectedID != model.selectedToolID,
                      let tool = model.tools.first(where: { $0.id == selectedID }) else { return }
                model.select(tool)
            }
        )
    }
}

private struct SidebarRow: View {
    let tool: ToolDefinition
    let selected: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceRaised),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selected ? Theme.accent.opacity(0.9) : Theme.border, lineWidth: 1)
                )
            Text(tool.localizedTitle)
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(selected ? 1 : 0.86))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isFavorite ? Theme.warning : selected ? Theme.onAccent.opacity(0.72) : Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bare)
            .help(favoriteLabel)
            .accessibilityLabel(favoriteLabel)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            selected ? Theme.accent.opacity(0.13)
                : hovering ? Theme.textPrimary.opacity(0.045) : Color.clear,
            in: shape
        )
        .overlay(shape.stroke(selected ? Theme.accent.opacity(0.9) : Color.clear, lineWidth: 1))
        .shadow(color: selected ? Theme.accent.opacity(0.12) : .clear, radius: 5)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var favoriteLabel: String {
        localizedFormat(
            isFavorite ? "Remove %@ from Favorites" : "Add %@ to Favorites",
            tool.localizedTitle
        )
    }
}

/// SwiftUI's sidebar list supplies native selection and keyboard behavior, while this public
/// AppKit setting leaves the selected-row drawing to `SidebarRow` instead of adding a solid fill.
private struct SidebarListSelectionAppearance: NSViewRepresentable {
    let onConfigured: () -> Void

    func makeNSView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.onConfigured = onConfigured
        return view
    }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        nsView.onConfigured = onConfigured
        nsView.configureTable()
    }

    final class ConfigurationView: NSView {
        var onConfigured: (() -> Void)?
        private var configuredTable = false

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureTable()
        }

        func configureTable() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                while let view = ancestor {
                    if let table = view as? NSTableView {
                        table.selectionHighlightStyle = .none
                        table.focusRingType = .none
                        if self?.configuredTable == false {
                            self?.configuredTable = true
                            self?.onConfigured?()
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}
