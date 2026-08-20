import SwiftUI

// Shown as a centered panel the first time the user triggers a report
// on a fresh install (no stored name). Once the user fills in a name
// and selects Continue, the name is persisted to ReporterIdentity and
// this view is replaced by the normal ReportView. Canceling closes
// the whole report flow without submitting anything.
//
// TV note: this is the most expensive interaction in the flow (full
// remote keyboard round-trip), which is why it happens exactly once
// per install — and why hosts that know the user should call
// Issuetracker.identify(name:) and skip it entirely.
struct NamePromptView: View {
    let onContinue: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            BrandHeader(
                title: "One thing first",
                subtitle: "Stored only on this Apple TV."
            )
            .padding(.horizontal, Tokens.Space.s5)
            .padding(.vertical, Tokens.Space.s4)
            Divider().background(Tokens.lineFaint)

            // Body
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                FieldLabel(title: "Your name")
                BrandTextField(
                    value: $name,
                    placeholder: "What should we call you?"
                )
                .onSubmit(submitIfValid)
                Text("This name appears on the issues you report so the team knows who filed them.")
                    .brandFont(Tokens.TypeScale.subtitle, relativeTo: .subheadline)
                    .foregroundStyle(Tokens.fg3)
            }
            .padding(Tokens.Space.s5)

            Divider().background(Tokens.lineFaint)

            // Footer
            HStack(spacing: 16) {
                Spacer()
                BrandButton("Cancel", variant: .ghost) { onCancel() }
                    .frame(maxWidth: 240)
                BrandButton(
                    "Continue",
                    variant: .primary,
                    isDisabled: trimmed.isEmpty
                ) {
                    submitIfValid()
                }
                .frame(maxWidth: 300)
            }
            .padding(Tokens.Space.s4)
            .background(Tokens.surfaceApp)
        }
        .frame(maxWidth: 980)
        .background(Tokens.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusLg, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 60, x: 0, y: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submitIfValid() {
        guard !trimmed.isEmpty else { return }
        onContinue(trimmed)
    }
}
