import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = LiquefCheckViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    locationSection
                    if viewModel.isLoading {
                        ProgressView("地盤情報を取得中...")
                            .padding()
                    }
                    if viewModel.showResult {
                        resultSection
                    }
                    Spacer(minLength: 60)
                }
                .padding()
            }
            .navigationTitle("液状化チェック")
            .safeAreaInset(edge: .bottom) {
                BannerAdView(adUnitID: "ca-app-pub-9404799280370656/LIQUEFCHK_B")
                    .frame(height: 50)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("地盤の液状化リスク簡易判定")
                .font(.headline)
            Text("J-SHIS（地震ハザードステーション）と\n国土地理院データに基づいてリスクを判定します")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
    }

    private var locationSection: some View {
        VStack(spacing: 16) {
            Button(action: { viewModel.useCurrentLocation() }) {
                Label("現在地で診断", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
            }

            HStack {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.secondary.opacity(0.3))
                Text("または住所入力")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.secondary.opacity(0.3))
            }

            TextField("住所を入力（例：東京都江東区豊洲）", text: $viewModel.addressText)
                .textFieldStyle(.roundedBorder)

            Button(action: { viewModel.searchByAddress() }) {
                Text("住所で診断")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    private var resultSection: some View {
        VStack(spacing: 16) {
            Text("診断結果")
                .font(.title2.bold())

            // リスクレベル表示
            VStack(spacing: 12) {
                Text(viewModel.riskLevel.emoji)
                    .font(.system(size: 60))

                Text(viewModel.riskLevel.label)
                    .font(.title.bold())
                    .foregroundColor(viewModel.riskLevel.color)

                Text("液状化可能性: \(viewModel.riskLevel.description)")
                    .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.riskLevel.color.opacity(0.08))
            .cornerRadius(12)

            // 詳細情報
            VStack(alignment: .leading, spacing: 8) {
                Text("判定根拠")
                    .font(.headline)

                if let terrain = viewModel.terrainType {
                    detailRow("地形分類", terrain)
                }
                if let groundType = viewModel.groundType {
                    detailRow("表層地盤", groundType)
                }
                detailRow("判定位置", viewModel.locationDescription)

                if !viewModel.explanation.isEmpty {
                    Divider()
                    Text(viewModel.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 対策アドバイス
            VStack(alignment: .leading, spacing: 8) {
                Text("対策・アドバイス")
                    .font(.headline)
                Text(viewModel.advice)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(12)

            Text("※ 250mメッシュ単位の簡易判定です。\n詳細な地盤調査（ボーリング等）の代替にはなりません。\n土地購入時は必ず専門機関の調査を受けてください。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }
}
