import MochyCore
import SwiftUI
#if os(iOS) && canImport(PhotosUI)
import PhotosUI
#endif

/// First-launch 3-step Mochy Onboarding Wizard featuring the Brushed Silver `ProfileIdCardFront`.
public struct SetupWizardView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onComplete: () -> Void

    @State private var step = 0
    @State private var quickImportURL = ""
    #if os(iOS) && canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    public init(coordinator: AppCoordinator, onComplete: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.06, blue: 0.12), .black, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Step Dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { idx in
                        Capsule()
                            .fill(idx == step ? MochyTheme.defaultAccent : Color.white.opacity(0.22))
                            .frame(width: idx == step ? 28 : 8, height: 6)
                    }
                }
                .padding(.top, 24)
                .animation(.spring(response: 0.30, dampingFraction: 0.80), value: step)

                Spacer(minLength: 8)

                Group {
                    if step == 0 {
                        stepIdentityCard
                    } else if step == 1 {
                        stepStyleAndImport
                    } else {
                        stepReady
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(step < 2 ? "Continue" : "Start Listening")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.defaultAccent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var stepIdentityCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Welcome to Natch Music")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Mint your personal Brushed Silver listener ID Card.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            ProfileIdCardFront(
                username: coordinator.settings.profileUsername,
                cardNumber: coordinator.settings.profileCardNumber,
                joinedDate: Date(timeIntervalSince1970: coordinator.settings.profileJoinedTimestamp),
                avatarURL: coordinator.profileAvatarURL(),
                finish: .silver
            )
            .padding(.horizontal, 18)

            VStack(spacing: 12) {
                TextField("Your listener name", text: $coordinator.settings.profileUsername)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)

                #if os(iOS) && canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Pick Avatar Photo", systemImage: "person.crop.circle.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            coordinator.saveProfileAvatar(data: data)
                        }
                    }
                }
                #endif
            }
        }
    }

    private var stepStyleAndImport: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Pick Your Vibe")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("Choose a starting Player Style — switch among all 10 anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach([PlayerStyle.flagship, .turntable, .ipod, .poster, .timeline], id: \.self) { style in
                        let sel = coordinator.settings.playerStyle == style
                        Button {
                            coordinator.settings.playerStyle = style
                        } label: {
                            Text(style.displayName)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(sel ? MochyTheme.defaultAccent : MochyTheme.cardSurface)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Optional: Import a Public Playlist Now")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Paste a public Spotify, Apple Music, or YouTube Music playlist URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("https://open.spotify.com/playlist/...", text: $quickImportURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Import") {
                        Task { await coordinator.runPlaylistImport(urlString: quickImportURL) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.defaultAccent)
                    .disabled(quickImportURL.trimmingCharacters(in: .whitespaces).isEmpty || coordinator.isImportingPlaylist)
                }
                if coordinator.isImportingPlaylist, let prog = coordinator.importProgress {
                    ProgressView(prog.stage)
                        .font(.caption)
                } else if let status = coordinator.importStatusMessage {
                    Text(status).font(.caption).foregroundStyle(.green)
                }
            }
            .padding(16)
            .background(MochyTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 22)
        }
    }

    private var stepReady: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(MochyTheme.defaultAccent)

            Text("You're All Set")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                featureBullet("Real-Time C++ DSP", "10-band EQ, AutoEq, 8D Orbit & 3D KEMAR HRTF Stage on every stream.")
                featureBullet("Multi-Source Hi-Res", "Monochrome FLAC, JioSaavn 320k & YouTube fMP4 via LocalAudioProxy.")
                featureBullet("100% Free & Open Source", "Based on realidkroo/Mochy-Music (GPL-3.0) with zero ads or paywalls.")
            }
            .padding(18)
            .background(MochyTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 22)
        }
    }

    private func featureBullet(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MochyTheme.defaultAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
