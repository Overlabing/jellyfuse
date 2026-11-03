import DesignSystem
import LibraryKit
import SwiftUI

/// Composition layer for sign-in: owns the model, picks the step view.
struct LoginScreen: View {
    @State private var model: LoginModel
    @Environment(\.designMetrics) private var metrics

    init(onSignedIn: @escaping @MainActor (Session) -> Void) {
        _model = State(initialValue: LoginModel(onSignedIn: onSignedIn))
    }

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .topLeading) {
            Design.Palette.canvas.ignoresSafeArea()
            Wordmark().padding(.top, Design.Spacing.m)
            switch model.step {
            case .server:
                ServerStepView(
                    address: $model.serverText, isBusy: model.isBusy, errorMessage: model.errorMessage,
                    onContinue: { Task { await model.connect() } }
                )
            case .quickConnect:
                QuickConnectStepView(
                    code: model.code, link: model.quickConnectLink, host: model.serverHost,
                    onUsePassword: model.usePassword, onChangeServer: model.changeServer
                )
            case .password:
                PasswordStepView(
                    userName: $model.userName, password: $model.password, isBusy: model.isBusy,
                    errorMessage: model.errorMessage, host: model.serverHost,
                    onSubmit: { Task { await model.submitPassword() } }, onChangeServer: model.changeServer
                )
            }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, metrics.safeVertical)
    }
}

/// Sizes that differ between the 10-foot and the touch layouts (no DesignSystem token for them yet).
private enum LoginLayout {
    #if os(tvOS)
    static let topClearance: CGFloat = 170
    static let fieldWidth: CGFloat = 900
    static let digitFont: CGFloat = 92
    static let digitSize = CGSize(width: 112, height: 150)
    #else
    static let topClearance: CGFloat = 90
    static let fieldWidth: CGFloat = 480
    static let digitFont: CGFloat = 34
    static let digitSize = CGSize(width: 44, height: 62)
    #endif
}

// MARK: - Steps (pure views)

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            Text(title).font(Design.Typography.title).foregroundStyle(Design.Palette.textPrimary)
            Text(subtitle)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.textSecondary)
                .frame(maxWidth: LoginLayout.fieldWidth, alignment: .leading)
        }
    }
}

private struct ErrorLine: View {
    let message: String?

    var body: some View {
        Text(message ?? "")
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.warning)
            .opacity(message == nil ? 0 : 1)
            .accessibilityHidden(message == nil)
    }
}

private struct ServerStepView: View {
    @Binding var address: String
    let isBusy: Bool
    let errorMessage: String?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.l) {
            StepHeader(
                title: String(localized: "Serveur"),
                subtitle: String(localized: "Saisissez l'adresse de votre serveur Jellyfin.")
            )
            TextField(String(localized: "jellyfin.local:8096"), text: $address)
                .onSubmit(onContinue)
                .touchTextEntry(.url)
                .frame(maxWidth: LoginLayout.fieldWidth)
            ErrorLine(message: errorMessage)
            PillButton(isBusy ? String(localized: "Connexion…") : String(localized: "Continuer"), systemImage: "arrow.right", action: onContinue)
                .disabled(isBusy)
        }
        .padding(.top, LoginLayout.topClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct QuickConnectStepView: View {
    let code: String?
    let link: URL?
    let host: String?
    let onUsePassword: () -> Void
    let onChangeServer: () -> Void
    @Namespace private var focusNamespace
    @Environment(\.designMetrics) private var metrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                StepHeader(
                    title: String(localized: "Connexion rapide"),
                    subtitle: String(localized: "Sur un autre appareil déjà connecté à Jellyfin, ouvrez Profil › Connexion rapide et saisissez ce code.")
                )
                CodeDigits(code: code)
                Text(code == nil ? String(localized: "Génération du code…") : String(localized: "En attente d'autorisation…"))
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textSecondary)
            }
            .padding(.top, LoginLayout.topClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            #if os(tvOS)
            if let link {
                VStack(spacing: Design.Spacing.s) {
                    QRCodeView(url: link, side: 300)
                    Text("Ou scannez ce code avec votre téléphone")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 300)
                }
                .padding(.top, LoginLayout.topClearance + 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            #endif

            let layout = metrics.isTouch
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Design.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Design.Spacing.m))
            layout {
                PillButton(String(localized: "Utiliser un mot de passe"), systemImage: "key.fill", action: onUsePassword)
                    .platformDefaultFocus(in: focusNamespace)
                PillButton(String(localized: "Changer de serveur"), systemImage: "server.rack", action: onChangeServer)
                if let host {
                    Text(host).font(Design.Typography.caption).foregroundStyle(Design.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .platformFocusScope(focusNamespace)
    }
}

/// Six boxed digits, split 3 + 3 like the mockup.
private struct CodeDigits: View {
    let code: String?

    var body: some View {
        let digits = Array((code ?? "").prefix(6))
        HStack(spacing: Design.Spacing.s) {
            ForEach(0..<6, id: \.self) { index in
                if index == 3 { Spacer().frame(width: Design.Spacing.s) }
                Text(index < digits.count ? String(digits[index]) : "")
                    .font(.system(size: LoginLayout.digitFont, weight: .bold)) // ui-plan §3.2 code size; no DesignSystem token yet
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.textPrimary)
                    .frame(width: LoginLayout.digitSize.width, height: LoginLayout.digitSize.height)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Design.Spacing.m))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code.map { String(localized: "Code \($0)") } ?? String(localized: "Code en cours de génération"))
    }
}

private struct PasswordStepView: View {
    @Binding var userName: String
    @Binding var password: String
    let isBusy: Bool
    let errorMessage: String?
    let host: String?
    let onSubmit: () -> Void
    let onChangeServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.l) {
            StepHeader(
                title: String(localized: "Connexion"),
                subtitle: host.map { String(localized: "Serveur : \($0)") } ?? ""
            )
            TextField(String(localized: "Nom d'utilisateur"), text: $userName)
                .touchTextEntry(.username)
                .frame(maxWidth: LoginLayout.fieldWidth)
            SecureField(String(localized: "Mot de passe"), text: $password)
                .touchTextEntry(.password)
                .onSubmit(onSubmit)
                .frame(maxWidth: LoginLayout.fieldWidth)
            ErrorLine(message: errorMessage)
            HStack(spacing: Design.Spacing.m) {
                PillButton(isBusy ? String(localized: "Connexion…") : String(localized: "Se connecter"), systemImage: "arrow.right", action: onSubmit)
                    .disabled(isBusy)
                PillButton(String(localized: "Changer de serveur"), systemImage: "server.rack", action: onChangeServer)
            }
        }
        .padding(.top, LoginLayout.topClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// Keyboard behavior of a sign-in field on touch platforms (no-op on tvOS).
    fileprivate func touchTextEntry(_ kind: TouchTextKind) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .keyboardType(kind == .url ? .URL : .default)
            .textContentType(kind == .url ? .URL : kind == .username ? .username : .password)
        #else
        self
        #endif
    }
}

private enum TouchTextKind { case url, username, password }
