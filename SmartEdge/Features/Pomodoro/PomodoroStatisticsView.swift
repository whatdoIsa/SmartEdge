import SwiftUI
import Charts

@MainActor
struct PomodoroStatisticsView: View {
    @ObservedObject var viewModel: PomodoroViewModel
    @State private var range: Range = .week

    enum Range: String, CaseIterable, Identifiable {
        case week = "Last 7 days"
        case month = "Last 30 days"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summary
            Divider()
            chart
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Statistics")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Pomodoro sessions you've completed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $range) {
                ForEach(Range.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .labelsHidden()
        }
    }

    private var summary: some View {
        let buckets = viewModel.dailyBuckets(days: range.days)
        let totalMinutes = buckets.reduce(0) { $0 + $1.minutes }
        let totalSessions = buckets.reduce(0) { $0 + $1.count }
        let avgMinutes = buckets.isEmpty ? 0 : Double(totalMinutes) / Double(buckets.count)

        return HStack(spacing: 24) {
            statCard(title: "Total focus", value: format(minutes: totalMinutes))
            statCard(title: "Sessions", value: "\(totalSessions)")
            statCard(title: "Daily avg", value: String(format: "%.0f min", avgMinutes))
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chart: some View {
        let buckets = viewModel.dailyBuckets(days: range.days)
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Day", bucket.label),
                y: .value("Minutes", bucket.minutes)
            )
            .foregroundStyle(Color.red.gradient)
            .cornerRadius(4)
        }
        .frame(minHeight: 240)
        .chartYAxisLabel("Minutes")
    }

    private func format(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

#Preview {
    PomodoroStatisticsView(viewModel: PomodoroViewModel(service: PomodoroService()))
}
