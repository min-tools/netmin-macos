import SwiftUI

/// One card of a summary: a title row, then key-value rows, a table, or monospaced text.
struct SummarySectionView: View {
    let section: SummarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(localized(section.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.tone == .neutral ? Theme.textPrimary : Theme.color(for: section.tone))
                if let badge = section.badge {
                    Chip(text: badge, mono: false, tone: section.tone, compact: true)
                }
                Spacer()
                if let detail = section.detail {
                    Text(localized(detail))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !section.rows.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 18) }
                    SummaryRowView(row: row)
                }
            }
            if let table = section.table {
                Rectangle().fill(Theme.border).frame(height: 1)
                SummaryTableView(table: table)
            }
            if let body = section.body {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text(body)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            if section.omittedLines > 0 {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text(localizedFormat("%lld more lines · use Copy Result for the complete output", Int64(section.omittedLines)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        }
        .card()
    }
}

struct SummaryRowView: View {
    let row: SummaryRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(localized(row.label))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 200, alignment: .leading)
            Text(localized(row.value))
                .font(Theme.mono(12.5))
                .foregroundStyle(row.tone == .neutral ? Theme.textPrimary : Theme.color(for: row.tone))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .hoverHighlight(cornerRadius: 0)
    }
}

/// A grid whose columns size to their content, with the last column taking the remaining width.
struct SummaryTableView: View {
    let table: SummaryTable

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                    SectionLabel(column)
                        .padding(.vertical, 10)
                        .gridColumnAlignment(.leading)
                        .frame(maxWidth: index == table.columns.count - 1 ? .infinity : nil, alignment: .leading)
                }
            }
            Divider().overlay(Theme.border).gridCellUnsizedAxes(.horizontal)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        cellText(cell, column: index)
                            .padding(.vertical, 9)
                            .frame(maxWidth: index == table.columns.count - 1 ? .infinity : nil, alignment: .leading)
                    }
                }
                if rowIndex < table.rows.count - 1 {
                    Divider().overlay(Theme.border).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func cellText(_ cell: String, column: Int) -> some View {
        let tone = table.statusColumn == column ? Theme.tone(forStatus: cell) : SummaryTone.neutral
        return Text(cell.isEmpty ? "—" : localized(cell))
            .font(table.monospaced.contains(column) ? Theme.mono(12.5) : .system(size: 13))
            .foregroundStyle(cell.isEmpty ? Theme.textTertiary : tone == .neutral ? Theme.textPrimary : Theme.color(for: tone))
            .textSelection(.enabled)
            .lineLimit(4)
    }
}
