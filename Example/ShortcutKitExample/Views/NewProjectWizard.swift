import ShortcutKit
import SwiftUI

@MainActor
struct NewProjectWizard: View {
    @EnvironmentObject var model: WizardContextModel

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.title2)
                .padding(.top)

            Group {
                switch model.pageIndex {
                case 0: pageProjectName
                case 1: pageTemplate
                default: pageConfirm
                }
            }
            .frame(minHeight: 120)

            Spacer()

            HStack {
                Button("Cancel") { model.context.dispatch(.cancel) }
                Spacer()
                if model.pageIndex > 0 {
                    Button("Back") { model.context.dispatch(.previous) }
                }
                Button(model.pageIndex == model.pageCount - 1 ? "Finish" : "Next") {
                    model.context.dispatch(model.pageIndex == model.pageCount - 1 ? .finish : .next)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
        .activeShortcutContext(model.context)
    }

    private var pageProjectName: some View {
        VStack(alignment: .leading) {
            Text("Step 1: Project name").font(.headline)
            TextField("My Project", text: .constant(""))
        }
    }

    private var pageTemplate: some View {
        VStack(alignment: .leading) {
            Text("Step 2: Template").font(.headline)
            Text("(placeholder)")
        }
    }

    private var pageConfirm: some View {
        VStack(alignment: .leading) {
            Text("Step 3: Confirm").font(.headline)
            Text("Press Finish to create.")
        }
    }
}
