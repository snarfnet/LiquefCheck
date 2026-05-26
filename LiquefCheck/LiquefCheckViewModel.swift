import SwiftUI
import CoreLocation

enum RiskLevel {
    case veryHigh
    case high
    case medium
    case low
    case veryLow

    var label: String {
        switch self {
        case .veryHigh: return "非常に高い"
        case .high: return "高い"
        case .medium: return "やや高い"
        case .low: return "低い"
        case .veryLow: return "かなり低い"
        }
    }

    var symbol: String {
        switch self {
        case .veryHigh: return "exclamationmark.triangle.fill"
        case .high: return "waveform.path.ecg.rectangle.fill"
        case .medium: return "water.waves"
        case .low: return "checkmark.shield.fill"
        case .veryLow: return "shield.lefthalf.filled"
        }
    }

    var color: Color {
        switch self {
        case .veryHigh: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        case .veryLow: return .cyan
        }
    }

    var score: Double {
        switch self {
        case .veryHigh: return 0.95
        case .high: return 0.76
        case .medium: return 0.55
        case .low: return 0.30
        case .veryLow: return 0.12
        }
    }

    var description: String {
        switch self {
        case .veryHigh: return "液状化が起きやすい条件です"
        case .high: return "液状化リスクに注意が必要です"
        case .medium: return "条件次第で注意が必要です"
        case .low: return "一般的には低めのリスクです"
        case .veryLow: return "液状化の可能性はかなり低めです"
        }
    }
}

struct TerrainResult {
    let name: String
    let groundClass: String
    let riskLevel: RiskLevel
    let explanation: String

    static let unknown = TerrainResult(
        name: "地盤情報を取得できませんでした",
        groundClass: "推定不可",
        riskLevel: .medium,
        explanation: "J-SHISの応答から地盤情報を読み取れませんでした。住所を変えて再検索するか、専門調査で確認してください。"
    )
}

final class LiquefCheckViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var addressText = ""
    @Published var isLoading = false
    @Published var showResult = false
    @Published var riskLevel: RiskLevel = .low
    @Published var terrainType: String?
    @Published var groundType: String?
    @Published var locationDescription = ""
    @Published var explanation = ""
    @Published var advice = ""

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func useCurrentLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        isLoading = true
    }

    func searchByAddress() {
        guard !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true

        geocoder.geocodeAddressString(addressText) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let location = placemarks?.first?.location {
                    self.locationDescription = self.addressText
                    self.fetchLiquefactionData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                } else {
                    self.isLoading = false
                    self.apply(result: .unknown, location: "住所を特定できませんでした")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        locationDescription = "現在地"

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let placemark = placemarks?.first else { return }
                let address = [placemark.administrativeArea, placemark.locality, placemark.subLocality]
                    .compactMap { $0 }
                    .joined()
                if !address.isEmpty {
                    self?.locationDescription = address
                }
            }
        }

        fetchLiquefactionData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.apply(result: .unknown, location: "現在地を取得できませんでした")
        }
    }

    private func fetchLiquefactionData(latitude: Double, longitude: Double) {
        fetchTerrainClassification(lat: latitude, lon: longitude) { [weak self] result in
            DispatchQueue.main.async {
                self?.apply(result: result, location: self?.locationDescription ?? "判定地点")
            }
        }
    }

    private func apply(result: TerrainResult, location: String) {
        terrainType = result.name
        groundType = result.groundClass
        riskLevel = result.riskLevel
        locationDescription = location
        explanation = result.explanation
        advice = generateAdvice(for: result.riskLevel)
        isLoading = false
        showResult = true
    }

    private func fetchTerrainClassification(lat: Double, lon: Double, completion: @escaping (TerrainResult) -> Void) {
        let urlString = "https://www.j-shis.bosai.go.jp/map/api/pshm/Y2024/AVR/TTL_MTTL/meshinfo.geojson?position=\(lon),\(lat)"
        guard let url = URL(string: urlString) else {
            completion(estimateFromLocation(lat: lat, lon: lon))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else {
                completion(self?.estimateFromLocation(lat: lat, lon: lon) ?? .unknown)
                return
            }
            completion(self.parseJSHISResponse(data: data) ?? self.estimateFromLocation(lat: lat, lon: lon))
        }.resume()
    }

    private func parseJSHISResponse(data: Data) -> TerrainResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let feature = features.first,
              let properties = feature["properties"] as? [String: Any] else {
            return nil
        }

        if let avs30 = properties["AVS"] as? Double {
            return classifyByAVS30(avs30)
        }
        if let avs30 = properties["AVS30"] as? Double {
            return classifyByAVS30(avs30)
        }
        return nil
    }

    private func classifyByAVS30(_ avs30: Double) -> TerrainResult {
        if avs30 < 150 {
            return TerrainResult(
                name: "軟弱地盤・低地相当",
                groundClass: "第3種地盤 / AVS30 \(Int(avs30))m/s",
                riskLevel: .veryHigh,
                explanation: "表層30m平均S波速度が低く、軟弱な地盤と推定されます。地下水位が高い地域では液状化に注意が必要です。"
            )
        } else if avs30 < 200 {
            return TerrainResult(
                name: "やや軟弱な地盤",
                groundClass: "第2種地盤 / AVS30 \(Int(avs30))m/s",
                riskLevel: .high,
                explanation: "締まりの弱い砂質地盤を含む可能性があります。購入や建築前には地盤調査を確認しましょう。"
            )
        } else if avs30 < 300 {
            return TerrainResult(
                name: "一般的な地盤",
                groundClass: "第2種地盤 / AVS30 \(Int(avs30))m/s",
                riskLevel: .medium,
                explanation: "一般的な地盤条件です。河川沿い、埋立地、旧水田では局所的なリスクが残ります。"
            )
        } else if avs30 < 500 {
            return TerrainResult(
                name: "比較的良好な地盤",
                groundClass: "第1種地盤 / AVS30 \(Int(avs30))m/s",
                riskLevel: .low,
                explanation: "締まった地盤と推定されます。液状化リスクは低めですが、詳細は自治体のハザードマップも確認してください。"
            )
        } else {
            return TerrainResult(
                name: "硬質地盤・岩盤相当",
                groundClass: "第1種地盤 / AVS30 \(Int(avs30))m/s",
                riskLevel: .veryLow,
                explanation: "かなり硬い地盤と推定されます。液状化の可能性は低いと考えられます。"
            )
        }
    }

    private func estimateFromLocation(lat: Double, lon: Double) -> TerrainResult {
        TerrainResult(
            name: "地盤分類を取得中",
            groundClass: "J-SHIS応答外の簡易判定",
            riskLevel: .medium,
            explanation: "詳細な地盤値を取得できなかったため、中間リスクとして表示しています。自治体の液状化ハザードマップも確認してください。"
        )
    }

    private func generateAdvice(for risk: RiskLevel) -> String {
        switch risk {
        case .veryHigh:
            return "購入前・建築前にボーリング調査を確認してください。地盤改良、杭、排水対策、地震保険の検討を強くおすすめします。"
        case .high:
            return "地盤調査報告書、地下水位、過去の液状化履歴を確認しましょう。周辺のハザードマップも合わせて見ると判断しやすくなります。"
        case .medium:
            return "一律に危険とは言えません。河川、埋立地、旧水田、海岸近くかどうかを追加で確認してください。"
        case .low:
            return "一般的には低めです。念のため自治体のハザードマップと重要事項説明書の地盤情報を確認しましょう。"
        case .veryLow:
            return "液状化の可能性はかなり低めです。通常の耐震性、地盤条件、周辺災害リスクを総合的に確認してください。"
        }
    }
}
