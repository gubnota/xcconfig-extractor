import Foundation

class ResultFormatter {
    let config: Config
    init(config: Config) {
        self.config = config
    }
    private var header: [String] {
        let signature = "// Generated using xcconfig-extractor \(Config.version) by Toshihiro Suzuki - https://github.com/toshi0383/xcconfig-extractor"
        return [signature]
    }
    private func addInclude(filePath: String) -> String {
        return "#include \"\(filePath)\""
    }
    func format(result: ResultObject, includes: [String] = []) -> [String] {
        return header
            + result.includes.map(addInclude)
            + includes.map(addInclude)
            + result.settings
            + ["\n"]
    }
}
