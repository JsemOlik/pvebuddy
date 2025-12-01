//
//  ContentView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("pve_server_address") private var storedServerAddress: String = ""
    @AppStorage("pve_token_id") private var storedTokenID: String = ""
    @AppStorage("pve_token_secret") private var storedTokenSecret: String = ""

    @State private var serverAddress: String = ""
    @State private var tokenID: String = ""
    @State private var tokenSecret: String = ""
    @AppStorage("has_onboarded") private var hasOnboarded: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.96, blue: 1.0),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    onboardingHeader

                    credentialsCard

                    Spacer()

                    connectButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $hasOnboarded) {
                MainTabView()
                    .interactiveDismissDisabled(true)
            }
            .onAppear {
                // Prefill fields from previously saved values so users don't have to re-enter them.
                if serverAddress.isEmpty {
                    serverAddress = storedServerAddress
                }
                if tokenID.isEmpty {
                    tokenID = storedTokenID
                }
                if tokenSecret.isEmpty {
                    tokenSecret = storedTokenSecret
                }
            }
        }
    }
}

private extension OnboardingView {
    var onboardingHeader: some View {
        VStack(spacing: 16) {
            Image("ProxmoxLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

            VStack(spacing: 4) {
                Text("PVE Buddy")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("A focused dashboard for your Proxmox VE cluster")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    var credentialsCard: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Server address")
                    .font(.headline)

                Text("Enter the URL of your Proxmox server")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)

                TextField("https://pve.example.com:8006", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .focused($isTextFieldFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("API token")
                    .font(.headline)

                Text("Generate an API token from the desktop dashboard")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("and assign at least PVEAuditor permissions")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)

                    TextField("root@pam!pvebuddy", text: $tokenID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.default)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )

                SecureField("API token secret", text: $tokenSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.default)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color(.secondarySystemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }

    var connectButton: some View {
        Button {
            let trimmedServer = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTokenSecret = tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedServer.isEmpty,
                  !trimmedTokenID.isEmpty,
                  !trimmedTokenSecret.isEmpty else { return }

            isTextFieldFocused = false
            storedServerAddress = trimmedServer
            storedTokenID = trimmedTokenID
            storedTokenSecret = trimmedTokenSecret
            hasOnboarded = true
        } label: {
            Text("Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.blue)
        .clipShape(Capsule())
        .disabled(
            serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            tokenID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .opacity(
            serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            tokenID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0
        )
    }
}

#Preview {
    OnboardingView()
}
