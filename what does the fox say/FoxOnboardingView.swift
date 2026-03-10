import SwiftUI
import UIKit

struct FoxOnboardingView: View {
    @EnvironmentObject private var viewModel: FoxAppViewModel
    @State private var page = 0
    @State private var selectedNative = UserProfile.placeholder.nativeLanguage
    @State private var selectedTarget = UserProfile.placeholder.targetLanguage
    @State private var selectedPersona = UserProfile.placeholder.persona
    @State private var pickingLanguageRole: LanguageRole?

    var body: some View {
        ZStack {
            FoxTheme.pageGradient.ignoresSafeArea()

            VStack(spacing: 16) {
                topProgress

                TabView(selection: $page) {
                    onboardingPage(
                        imageName: "foxlaunchpage",
                        eyebrow: "Your practice partner",
                        title: "Practice real speaking with a multilingual fox who actually talks back.",
                        subtitle: "Every session becomes a clean transcript, topic summary, and feedback card you can revisit later.",
                        selectionLabel: selectedNative.rawValue,
                        buttonTitle: "Choose your native language"
                    ) {
                        pickingLanguageRole = .native
                    }
                    .tag(0)

                    onboardingPage(
                        imageName: "foxeyesopen",
                        eyebrow: "Build the habit",
                        title: "Pick the language you want to speak more naturally, more often.",
                        subtitle: "Short practice loops, fast correction, and a fox persona that keeps the energy high.",
                        selectionLabel: selectedTarget.rawValue,
                        buttonTitle: "Choose your practice language"
                    ) {
                        pickingLanguageRole = .target
                    }
                    .tag(1)

                    personaPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .safeAreaInset(edge: .bottom) {
            controls
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(
                        colors: [Color.clear, FoxTheme.backgroundBottom.opacity(0.24), FoxTheme.backgroundBottom.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .sheet(item: $pickingLanguageRole) { role in
            LanguagePickerSheet(
                title: role == .native ? "Native Language" : "Practice Language",
                selected: role == .native ? selectedNative : selectedTarget
            ) { language in
                if role == .native {
                    selectedNative = language
                } else {
                    selectedTarget = language
                }
            }
        }
    }

    private var topProgress: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? Color.white : Color.white.opacity(0.24))
                    .frame(height: 6)
            }
        }
        .padding(.top, 6)
        .accessibilityElement()
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("Step \(page + 1) of 3")
    }

    private func onboardingPage(
        imageName: String,
        eyebrow: String,
        title: String,
        subtitle: String,
        selectionLabel: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                OnboardingHeroImage(imageName: imageName)

                VStack(alignment: .leading, spacing: 12) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FoxTheme.accentSoft)
                    Text(title)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: action) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(buttonTitle)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Text(selectionLabel)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(buttonTitle)
                .accessibilityValue(selectionLabel)
                .accessibilityHint("Double tap to choose a language.")

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var personaPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                OnboardingHeroImage(imageName: "foxlaugh", preferredHeight: 228)

                VStack(alignment: .leading, spacing: 12) {
                    Text("MAKE THE FOX YOURS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FoxTheme.accentSoft)
                    Text("Choose the fox persona that will push you to keep speaking.")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("You can change native language, target language, and persona later from settings.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    ForEach(FoxPersona.allCases) { persona in
                        Button {
                            selectedPersona = persona
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(persona.title)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.black.opacity(0.82))
                                    Text(persona.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedPersona == persona {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(FoxTheme.accent)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(selectedPersona == persona ? Color.white : Color.white.opacity(0.9))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(persona.title)
                        .accessibilityValue(selectedPersona == persona ? "Selected" : "Not selected")
                        .accessibilityHint(persona.summary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var controls: some View {
        HStack {
            Button(page == 0 ? "Skip intro" : "Back") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    page = max(0, page - 1)
                }
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.84))
            .accessibilityHint(page == 0 ? "Skips onboarding and uses the current selections." : "Returns to the previous onboarding step.")

            Spacer()

            Button(page == 2 ? "Start Practicing" : "Continue") {
                if page == 2 {
                    viewModel.completeOnboarding(
                        nativeLanguage: selectedNative,
                        targetLanguage: selectedTarget,
                        persona: selectedPersona
                    )
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page += 1
                    }
                }
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color.white, in: Capsule())
            .accessibilityHint(page == 2 ? "Finishes onboarding and enters the main app." : "Moves to the next onboarding step.")
        }
    }

    private enum LanguageRole: Identifiable {
        case native
        case target

        var id: Int {
            self == .native ? 0 : 1
        }
    }
}

struct LanguagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let selected: PracticeLanguage
    let onSelect: (PracticeLanguage) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                searchBar

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredLanguages) { language in
                            Button {
                                onSelect(language)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(language.rawValue)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if language == selected {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(FoxTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 15)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(language == selected ? Color.white : Color.white.opacity(0.9))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(language.rawValue)
                            .accessibilityValue(language == selected ? "Selected" : "Not selected")
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityHint("Closes the language picker.")
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search languages", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9), in: Capsule())
    }

    private var filteredLanguages: [PracticeLanguage] {
        guard !query.isEmpty else { return PracticeLanguage.allCases }
        return PracticeLanguage.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct OnboardingHeroImage: View {
    let imageName: String
    var preferredHeight: CGFloat = 248

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))

            Group {
                if let image = FoxBundleImageLoader.load(named: imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Image unavailable")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .frame(height: preferredHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FoxTheme.glassStroke, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private enum FoxBundleImageLoader {
    static func load(named name: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }

        for fileExtension in ["png", "jpg", "jpeg", "webp"] {
            if let path = Bundle.main.path(forResource: name, ofType: fileExtension),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }

        debugLog("missing bundled image \(name)")
        return nil
    }
}
