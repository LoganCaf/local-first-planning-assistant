import SwiftUI
import UIKit

/// CombinedTasksView: single tab that lets the user switch between personal todos and school assignments.
struct CombinedTasksView: View {
	@State private var selection: Int = 0 // 0 = Personal, 1 = School

    init() {
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemOrange,
            .font: UIFont.preferredFont(forTextStyle: .headline)
        ]
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.secondaryLabel
        ]

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes(normalAttributes, for: .normal)
        segmented.setTitleTextAttributes(selectedAttributes, for: .selected)
    }

	var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selection == 0 {
                    TodoListView(showNavigationTitle: false)
                } else {
                    SchoolWorkView(showNavigationTitle: false)
                }
            }
            VStack(spacing: 0) {
                ZStack {
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.75))
                        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                        .frame(height: 30)

                    Picker(selection: $selection, label: Text("")) {
                        Text("Personal").tag(0)
                        Text("School").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, -1)
                    
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 10)
            }
            .background(Color.clear)
        }
	}
}

#Preview {
	CombinedTasksView()
		.environmentObject(AppData())
}
