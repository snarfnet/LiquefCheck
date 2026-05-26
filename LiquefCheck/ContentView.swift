import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = LiquefCheckViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x04131A), Color(hex: 0x063A46)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection
                        searchSection
                        if viewModel.isLoading {
                            loadingSection
                        }
                        if viewModel.showResult {
                            resultSection
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 76)
                }
            }
            .navigationTitle("液状化チェック")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                BannerAdView(adUnitID: "ca-app-pub-9404799280370656/4401657891")
                    .frame(height: 50)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GROUND RISK")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    Text("住所から液状化リスクを簡易チェック")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.cyan)
            }

            Text("J-SHISの地盤情報を参考に、地盤の硬さと液状化リスクを見やすく整理します。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(20)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12)))
    }

    private var searchSection: some View {
        VStack(spacing: 16) {
            Button(action: viewModel.useCurrentLocation) {
                Label("現在地でチェック", systemImage: "location.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)

            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.25))
                Text("または住所入力")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.25))
            }

            TextField("例: 東京都江東区豊洲", text: $viewModel.addressText)
                .textInputAutocapitalization(.never)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            Button(action: viewModel.searchByAddress) {
                Label("住所でチェック", systemImage: "magnifyingglass")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)
            .tint(.cyan)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("地盤情報を取得しています")
                .font(.subheadline.bold())
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(viewModel.riskLevel.color.opacity(0.18))
                    Image(systemName: viewModel.riskLevel.symbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(viewModel.riskLevel.color)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text("リスク \(viewModel.riskLevel.label)")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(viewModel.riskLevel.color)
                    Text(viewModel.riskLevel.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Gauge(value: viewModel.riskLevel.score) {
                Text("液状化リスク")
            } currentValueLabel: {
                Text("")
            } minimumValueLabel: {
                Text("低")
            } maximumValueLabel: {
                Text("高")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(Gradient(colors: [.cyan, .green, .yellow, .orange, .red]))

            VStack(alignment: .leading, spacing: 12) {
                detailRow("判定地点", viewModel.locationDescription)
                if let terrain = viewModel.terrainType {
                    detailRow("地形分類", terrain)
                }
                if let ground = viewModel.groundType {
                    detailRow("地盤分類", ground)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

            Text(viewModel.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("確認ポイント", systemImage: "checklist")
                    .font(.headline)
                Text(viewModel.advice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(viewModel.riskLevel.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            Text("250mメッシュ単位の簡易判定です。詳細な地盤調査や自治体のハザードマップ、重要事項説明書の確認を代替するものではありません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }
}

private extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
