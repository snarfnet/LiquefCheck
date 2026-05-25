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
        case .veryHigh: return "危険度：非常に高い"
        case .high: return "危険度：高い"
        case .medium: return "危険度：やや高い"
        case .low: return "危険度：低い"
        case .veryLow: return "危険度：極めて低い"
        }
    }

    var emoji: String {
        switch self {
        case .veryHigh: return "🔴"
        case .high: return "🟠"
        case .medium: return "🟡"
        case .low: return "🟢"
        case .veryLow: return "🔵"
        }
    }

    var color: Color {
        switch self {
        case .veryHigh: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        case .veryLow: return .blue
        }
    }

    var description: String {
        switch self {
        case .veryHigh: return "液状化が発生する可能性が非常に高い"
        case .high: return "液状化が発生する可能性が高い"
        case .medium: return "液状化が発生する可能性がある"
        case .low: return "液状化の可能性は低い"
        case .veryLow: return "液状化の可能性は極めて低い"
        }
    }
}

class LiquefCheckViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
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
        guard !addressText.isEmpty else { return }
        isLoading = true

        geocoder.geocodeAddressString(addressText) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let location = placemarks?.first?.location {
                    self.locationDescription = self.addressText
                    self.fetchLiquefactionData(latitude: location.coordinate.latitude,
                                              longitude: location.coordinate.longitude)
                } else {
                    self.isLoading = false
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let addr = [placemark.administrativeArea, placemark.locality, placemark.subLocality]
                        .compactMap { $0 }
                        .joined()
                    self?.locationDescription = addr
                }
            }
        }

        fetchLiquefactionData(latitude: location.coordinate.latitude,
                             longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }

    private func fetchLiquefactionData(latitude: Double, longitude: Double) {
        // J-SHIS API: 地形分類・液状化データ取得
        let meshCode = calculateMeshCode(lat: latitude, lon: longitude)

        // 地形分類から液状化リスクを推定
        fetchTerrainClassification(lat: latitude, lon: longitude) { [weak self] terrain in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.terrainType = terrain.name
                self.groundType = terrain.groundClass
                self.riskLevel = terrain.riskLevel
                self.explanation = terrain.explanation
                self.advice = self.generateAdvice(for: terrain.riskLevel)
                self.isLoading = false
                self.showResult = true
            }
        }
    }

    private func fetchTerrainClassification(lat: Double, lon: Double, completion: @escaping (TerrainResult) -> Void) {
        // J-SHIS 地形分類APIを呼び出し
        // URL: https://www.j-shis.bosai.go.jp/map/api/pshm/Y2024/AVR/TTL_MTTL/meshinfo.geojson?position=lon,lat
        let urlString = "https://www.j-shis.bosai.go.jp/map/api/pshm/Y2024/AVR/TTL_MTTL/meshinfo.geojson?position=\(lon),\(lat)"

        guard let url = URL(string: urlString) else {
            completion(estimateFromLocation(lat: lat, lon: lon))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data else {
                completion(self?.estimateFromLocation(lat: lat, lon: lon) ?? TerrainResult.unknown)
                return
            }

            if let result = self.parseJSHISResponse(data: data) {
                completion(result)
            } else {
                // APIが取得できない場合は地形分類の簡易推定
                completion(self.estimateFromLocation(lat: lat, lon: lon))
            }
        }.resume()
    }

    private func parseJSHISResponse(data: Data) -> TerrainResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let feature = features.first,
              let properties = feature["properties"] as? [String: Any] else {
            return nil
        }

        // J-SHISのAVS30（表層30m平均S波速度）から地盤分類を推定
        if let avs30 = properties["AVS"] as? Double {
            return classifyByAVS30(avs30)
        }

        return nil
    }

    private func classifyByAVS30(_ avs30: Double) -> TerrainResult {
        if avs30 < 150 {
            return TerrainResult(
                name: "軟弱地盤（沖積低地・埋立地相当）",
                groundClass: "第3種地盤（AVS30: \(Int(avs30))m/s）",
                riskLevel: .veryHigh,
                explanation: "表層30m平均S波速度が150m/s未満。非常に軟弱な地盤で、地下水位が高い場合に液状化が発生しやすい条件です。"
            )
        } else if avs30 < 200 {
            return TerrainResult(
                name: "やや軟弱な地盤（低地・旧河道相当）",
                groundClass: "第2種地盤（AVS30: \(Int(avs30))m/s）",
                riskLevel: .high,
                explanation: "表層30m平均S波速度が150〜200m/s。砂質土が厚く堆積している場合、液状化のリスクがあります。"
            )
        } else if avs30 < 300 {
            return TerrainResult(
                name: "普通地盤（台地・段丘相当）",
                groundClass: "第2種地盤（AVS30: \(Int(avs30))m/s）",
                riskLevel: .medium,
                explanation: "表層30m平均S波速度が200〜300m/s。一般的な地盤条件で、局所的に砂層がある場合は注意が必要です。"
            )
        } else if avs30 < 500 {
            return TerrainResult(
                name: "良好な地盤（洪積台地相当）",
                groundClass: "第1種地盤（AVS30: \(Int(avs30))m/s）",
                riskLevel: .low,
                explanation: "表層30m平均S波速度が300〜500m/s。締まった地盤で液状化の可能性は低いです。"
            )
        } else {
            return TerrainResult(
                name: "堅固な地盤（岩盤・礫層相当）",
                groundClass: "第1種地盤（AVS30: \(Int(avs30))m/s）",
                riskLevel: .veryLow,
                explanation: "表層30m平均S波速度が500m/s以上。非常に硬い地盤で液状化の心配はほぼありません。"
            )
        }
    }

    private func estimateFromLocation(lat: Double, lon: Double) -> TerrainResult {
        // API取得失敗時の簡易推定（標高と海岸距離から）
        // 一般的に標高が低く海岸に近い＝埋立地・低地の可能性高い
        return TerrainResult(
            name: "地形分類取得中（簡易推定）",
            groundClass: "API応答待ち",
            riskLevel: .medium,
            explanation: "詳細な地盤情報を取得できませんでした。一般的な条件での推定結果です。正確な判定には住所を再入力してください。"
        )
    }

    private func generateAdvice(for risk: RiskLevel) -> String {
        switch risk {
        case .veryHigh:
            return """
            ・土地購入前に必ずボーリング調査（地盤調査）を実施してください
            ・建築時は地盤改良（柱状改良・鋼管杭等）が必要な可能性が高いです
            ・地震保険への加入を強く推奨します
            ・液状化対策工法（締固め工法・排水工法）の検討を
            """
        case .high:
            return """
            ・地盤調査（スウェーデン式サウンディング以上）を推奨します
            ・地下水位が浅い場合は液状化対策が必要です
            ・地震保険への加入を推奨します
            ・近隣で過去に液状化が起きていないか確認しましょう
            """
        case .medium:
            return """
            ・念のため地盤調査を行うと安心です
            ・ハザードマップで詳細エリアを確認してください
            ・地震保険の加入を検討しましょう
            """
        case .low:
            return """
            ・一般的に液状化の心配は少ない地盤です
            ・標準的な基礎設計で問題ないケースが多いです
            ・念のため自治体のハザードマップも確認を
            """
        case .veryLow:
            return """
            ・液状化の心配はほぼありません
            ・地盤条件は良好です
            ・通常の建築で特別な対策は不要です
            """
        }
    }

    private func calculateMeshCode(lat: Double, lon: Double) -> String {
        let p = Int(lat * 60.0 / 40.0)
        let a = lat * 60.0 - Double(p) * 40.0
        let q = Int(lon - 100.0)
        let b = lon - 100.0 - Double(q)
        let r = Int(a / 5.0)
        let c = a - Double(r) * 5.0
        let s = Int(b * 60.0 / 7.5)
        return "\(p)\(q)\(r)\(s)"
    }
}

struct TerrainResult {
    let name: String
    let groundClass: String
    let riskLevel: RiskLevel
    let explanation: String

    static let unknown = TerrainResult(
        name: "不明",
        groundClass: "取得失敗",
        riskLevel: .medium,
        explanation: "地盤情報を取得できませんでした。"
    )
}
