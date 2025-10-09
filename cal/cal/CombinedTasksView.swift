import SwiftUI

/// CombinedTasksView: single tab that lets the user switch between personal todos and school assignments.
struct CombinedTasksView: View {
	@State private var selection: Int = 0 // 0 = Personal, 1 = School

	var body: some View {
		VStack(spacing: 0) {
			Picker(selection: $selection, label: Text("")) {
				Text("Personal").tag(0)
				Text("School").tag(1)
			}
			.pickerStyle(.segmented)
			.padding(.horizontal)
			.padding(.top, 8)

			Divider()

			// Embed the existing views; pass showNavigationTitle=false so the combined tab controls the header
			if selection == 0 {
				TodoListView(showNavigationTitle: false)
			} else {
				SchoolWorkView(showNavigationTitle: false)
			}
		}
	}
}

#Preview {
	CombinedTasksView()
		.environmentObject(AppData())
}

