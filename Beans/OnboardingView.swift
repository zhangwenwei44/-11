import SwiftUI

// MARK: - 首次启动免责声明确认

/// 首次进入 App 只保留免责声明页：必须输入「我已了解并同意继续使用」才能进入软件。
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var typed = ""
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue

    private var confirmText: String {
        languageRaw == AppLanguage.english.rawValue ? "I understand and agree to continue" : "我已了解并同意继续使用"
    }

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }
    private var enterText: String { isEnglish ? "Enter Kugou Player" : "进入软件" }

    var body: some View {
        ZStack {
            Color.beansBackground.ignoresSafeArea()
            // 主题色光晕（跟随当前配色主题）
            LinearGradient(
                colors: [Color.clear, Color.beansHighlight.opacity(0.12), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                disclaimerPage

                confirmBar
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
            .overlay(alignment: .topTrailing) {
                Picker("语言", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.beansHighlight)
                .padding(.top, 14)
                .padding(.trailing, 18)
            }
        }
    }

    // MARK: 免责确认输入框（上方固定提示，输入时不会消失）

    private var confirmBar: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey("请输入："))
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansHighlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(LinearGradient.beansAccent)
                    TextField(confirmText, text: $typed)
                        .font(BeansFont.appFont(14))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if typed != confirmText {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { typed = confirmText }
                        } label: {
                            Text(isEnglish ? "Fill" : "一键填入")
                                .font(BeansFont.appFont(12, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    Capsule().fill(LinearGradient.beansAccent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.beansCard.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            Color.beansHighlight.opacity(typed.isEmpty ? 0.3 : 0.75),
                            lineWidth: 1.2
                        )
                )
            }

            Button {
                onFinish()
            } label: {
                Text(enterText)
                    .font(BeansFont.appFont(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(typed == confirmText ? Color.beansHighlight : Color.beansHighlight.opacity(0.35))
                    )
                    .beansCardShadow(radius: 10, y: 4)
            }
            .disabled(typed != confirmText)
            .animation(.easeOut(duration: 0.2), value: typed == confirmText)
        }
    }

    // MARK: 免责声明

    private var disclaimerPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "shield.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.beansAccent)

            Text(isEnglish ? "Disclaimer" : "免责声明")
                .font(BeansFont.appFont(24, .bold))
                .foregroundStyle(Color.beansLabel)

            VStack(alignment: .leading, spacing: 10) {
                Text(isEnglish ? "· Kugou Player is for personal learning and research only. Commercial and illegal use is prohibited." : "· 酷狗播放器只用作个人学习研究，禁止用于商业及非法用途，如产生法律纠纷与本人无关。")
                Text(isEnglish ? "· Music APIs come from open-source GitHub projects. This app does not store audio. Please support official music services." : "· 音乐 API 来自于 GitHub 开源项目（非官方版 API），本软件不提供任何音频存储服务，如需下载音频，请支持正版！")
                Text(isEnglish ? "· Music copyrights belong to their respective platforms. Kugou Player assumes no related legal liability." : "· 音乐版权归各网站所有，本站不承担任何法律责任和连带责任。")
            }
            .font(BeansFont.appFont(13))
            .foregroundStyle(Color.beansSecondary)
            .lineSpacing(5)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.beansCard.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.beansHighlight.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            Text(isEnglish ? "Enter the exact text shown above to continue" : "请按输入框上方的提示，完整输入指定文字后进入软件")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansSecondary.opacity(0.8))

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
