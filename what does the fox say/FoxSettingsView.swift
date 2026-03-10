import SwiftUI

struct FoxSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profile: UserProfile
    let onSave: (UserProfile) -> Void

    @State private var pickingLanguageRole: Role?

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FoxTheme.settingsBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        headerText
                        languagesSection
                        personaSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FoxSheetGhostCircleButton(systemName: "xmark") {
                        dismiss()
                    }
                    .accessibilityLabel("Close settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    FoxSheetPrimaryButton(title: "Save") {
                        onSave(profile)
                        dismiss()
                    }
                    .accessibilityLabel("Save settings")
                }
            }
        }
        .presentationBackground(.clear)
        .sheet(item: $pickingLanguageRole) { role in
            LanguagePickerSheet(
                title: role == .native ? "Native Language" : "Practice Language",
                selected: role == .native ? profile.nativeLanguage : profile.targetLanguage
            ) { language in
                if role == .native {
                    profile.nativeLanguage = language
                } else {
                    profile.targetLanguage = language
                }
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Update your default language pair and the fox's conversation style for the next session.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.top, 8)
    }

    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Languages", subtitle: "These defaults apply when a new session starts.")

            VStack(spacing: 12) {
                languageTile(
                    title: "Native language",
                    value: profile.nativeLanguage.rawValue,
                    systemImage: "globe.americas.fill"
                ) {
                    pickingLanguageRole = .native
                }

                languageTile(
                    title: "Practice language",
                    value: profile.targetLanguage.rawValue,
                    systemImage: "character.bubble.fill"
                ) {
                    pickingLanguageRole = .target
                }
            }
        }
        .padding(20)
        .background(settingsGlassShape)
    }

    private var personaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Fox persona", subtitle: "This changes the tone sent to your backend prompt.")

            VStack(spacing: 10) {
                ForEach(FoxPersona.allCases) { persona in
                    Button {
                        profile.persona = persona
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(profile.persona == persona ? FoxTheme.accent.opacity(0.22) : Color.white.opacity(0.12))
                                Image(systemName: personaIcon(for: persona))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(profile.persona == persona ? FoxTheme.accent : .white.opacity(0.78))
                            }
                            .frame(width: 38, height: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(persona.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(persona.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.68))
                            }

                            Spacer()

                            if profile.persona == persona {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(FoxTheme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(profile.persona == persona ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(profile.persona == persona ? FoxTheme.accent.opacity(0.42) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(persona.title)
                    .accessibilityValue(profile.persona == persona ? "Selected" : "Not selected")
                    .accessibilityHint(persona.summary)
                }
            }
        }
        .padding(20)
        .background(settingsGlassShape)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.64))
        }
    }

    private func languageTile(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(value)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Double tap to choose a different language.")
    }

    private var settingsGlassShape: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func personaIcon(for persona: FoxPersona) -> String {
        switch persona {
        case .sarcastic:
            return "sparkles"
        case .sweet:
            return "heart.fill"
        case .indifferent:
            return "minus"
        case .impatient:
            return "bolt.fill"
        }
    }

    private enum Role: Identifiable {
        case native
        case target

        var id: Int {
            self == .native ? 0 : 1
        }
    }
}
