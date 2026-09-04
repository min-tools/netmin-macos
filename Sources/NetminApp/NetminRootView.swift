import SwiftUI

struct NetminRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var runner: CommandRunner

    init(model: AppModel) {
        self.model = model
        _runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(model: model)
                    .frame(width: 300)
                Rectangle().fill(Theme.border).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            NetminAccessBanner()
        }
        .background(Theme.background)
        .background(WindowChrome())
        .tint(Theme.accent)
    }

    @ViewBuilder private var content: some View {
        if let error = model.catalogError {
            placeholder(symbol: "exclamationmark.triangle", title: "Tools unavailable", detail: error)
        } else if let tool = model.selectedTool {
            if let run = runner.result {
                ResultView(model: model, run: run)
                    .id(run.startedAt)
            } else {
                ToolFormView(model: model, tool: tool)
                    .id(tool.id)
            }
        } else {
            placeholder(symbol: "network", title: "Choose a tool", detail: "Pick a tool from the sidebar or press ⌘K to search all of them.")
        }
    }

    private func placeholder(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            ToolIconTile(symbol: symbol, size: 64)
            Text(localized(title)).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(localized(detail))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
