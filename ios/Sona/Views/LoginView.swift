import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = "admin"
    @State private var password = ""
    @AppStorage("serverURL") private var serverURL = APIClient.defaultServerURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.22, blue: 0.10), .black, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(Color.sonaGreen)
                VStack(spacing: 6) {
                    Text("Sona")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                    Text("你的私人无损曲库")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("服务器地址", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sonaField()
                    TextField("账号", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .sonaField()
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .sonaField()
                    Button {
                        Task { await session.login(username: username, password: password) }
                    } label: {
                        Group {
                            if session.isSubmitting {
                                ProgressView()
                            } else {
                                Text("登录")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(session.isSubmitting)
                }

                if let message = session.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("明文 HTTP 仅建议在可信网络或 VPN 中使用")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 480)
        }
    }
}

private extension View {
    func sonaField() -> some View {
        padding(.horizontal, 18)
            .frame(height: 52)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}
