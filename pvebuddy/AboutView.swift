import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("ProxmoxLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 4)

            Text("PVE Buddy")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(appVersion)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                Link(destination: URL(string: "https://www.proxmox.com/en/")!) {
                    HStack {
                        Image(systemName: "link")
                        Text("Proxmox")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }

                Link(destination: URL(string: "https://github.com/JsemOlik/pvebuddy")!) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Source code")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 8) {
                Text("Acknowledgements")
                    .font(.headline)

                Text("PVE Buddy is an independent project and is not affiliated with Proxmox.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Text("© 2025 PVE Buddy")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, -12)
            Text("Made with ❤️ by Oliver Steiner")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
