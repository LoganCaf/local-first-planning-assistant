import SwiftUI

struct SettingsView: View {
	@AppStorage("calendarIndicatorStyle") private var indicatorStyle: String = "centered"

	var body: some View {
		NavigationStack {
			Form {
				Section(header: Text("Calendar indicators")) {
					Picker("Indicator style", selection: $indicatorStyle) {
						Text("Centered (circle)").tag("centered")
						Text("Centered (shapes)").tag("centeredShape")
						Text("Bottom dot").tag("bottom")
					}
					.pickerStyle(.inline)

					Text("Choose how calendar event indicators are shown on each day cell.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
			.navigationTitle("Settings")
		}
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView()
	}
}
