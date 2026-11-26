import Foundation

/// Full ISO/IEC 15417 Code 128 (Set B) barcode encoder ported 1:1 from Mochy Music's `IdCardBack.kt`.
/// Produces an array of boolean modules (`true` = dark bar, `false` = light space) ready for vector rendering.
public enum Code128Encoder {
    /// Complete 107-entry Code 128 module width table (codes 0..105 have 6 alternating bar/space widths; code 106 STOP has 7).
    private static let patterns: [String] = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
        "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
        "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
        "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
        "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
        "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
        "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
        "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
        "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
        "114131", "311141", "411131", "211412", "211214", "211232", "2331112"
    ]

    private static let startCodeB = 104
    private static let stopCode = 106

    /// Encodes printable ASCII (`32...126`) into a scannable Code 128B module bitmap (`true` = bar, `false` = space).
    public static func encode(_ text: String) -> [Bool] {
        var codes: [Int] = [startCodeB]
        var checksum = startCodeB
        var position = 1

        for scalar in text.unicodeScalars {
            let v = Int(scalar.value)
            let code = (v >= 32 && v <= 126) ? (v - 32) : 0
            codes.append(code)
            checksum += code * position
            position += 1
        }

        codes.append(checksum % 103)
        codes.append(stopCode)

        var modules: [Bool] = []
        modules.reserveCapacity(codes.count * 11 + 2)

        for code in codes {
            guard code >= 0, code < patterns.count else { continue }
            var isBar = true
            for ch in patterns[code] {
                let width = Int(String(ch)) ?? 1
                for _ in 0..<width {
                    modules.append(isBar)
                }
                isBar.toggle()
            }
        }
        return modules
    }
}
