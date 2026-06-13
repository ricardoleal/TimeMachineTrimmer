import SwiftUI

struct TrimByAgeView: View {
    @Environment(BackupViewModel.self) private var viewModel

    private var display: String {
        let value = viewModel.trimThresholdValue
        let unit = viewModel.trimThresholdUnit
        return "\(value) \(unit.displayName(count: value))"
    }

    private var maxLabel: String {
        let unit = viewModel.trimThresholdUnit
        return "\(unit.maxValue) \(unit.displayName(count: unit.maxValue))"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Delete backups older than")
                    .font(.callout)
                Text(display)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
            }

            Picker("Unit", selection: Binding(
                get: { viewModel.trimThresholdUnit },
                set: { newUnit in
                    viewModel.trimThresholdUnit = newUnit
                    viewModel.trimThresholdValue = min(viewModel.trimThresholdValue, newUnit.maxValue)
                }
            )) {
                ForEach(TrimUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Slider(
                value: Binding(
                    get: { Double(viewModel.trimThresholdValue) },
                    set: { viewModel.trimThresholdValue = Int($0) }
                ),
                in: 1...Double(viewModel.trimThresholdUnit.maxValue),
                step: 1
            )
            .padding(.horizontal, 2)

            HStack {
                Text("1 \(viewModel.trimThresholdUnit.displayName(count: 1))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(maxLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
