//
//  main.swift
//  xcconfig-extractor
//
//  Created by Toshihiro Suzuki on 2017/04/27.
//  Copyright © 2017 Toshihiro Suzuki. All rights reserved.
//

import Foundation
import Commander
import PathKit
import Pbxproj
import Utilities

func write(to path: Path, lines: [String] = []) throws {
    let data = (lines.joined(separator: "\n") as NSString).data(using: String.Encoding.utf8.rawValue)!
    try path.write(data)
}

let main = command(
    Argument<Path>("PATH", description: "xcodeproj file", validator: dirExists),
    Argument<Path>("DIR", description: "Output directory of xcconfig files. Mkdirs if missing. Files are overwritten."),
    Flag("no-trim-duplicates", description: "Don't extract duplicated lines to common xcconfig files, simply map each buildSettings to one file.", default: false),
    Flag("no-edit-pbxproj", description: "Do not modify pbxproj.", default: false),
    Flag("include-existing", description: "`#include` already configured xcconfigs.", default: true),
    Flag("preserve-configured", description: "Replace existing xcconfig configured on Xcode. Ignored if `--no-edit-pbxproj` is true.", default: false)
) { xcodeprojPath, dirPath, isNoTrimDuplicates, isNoEdit, isIncludeExisting, isPreserveConfigured in

    let pbxprojPath = xcodeprojPath + Path("project.pbxproj")
    guard pbxprojPath.isFile else {
        printStdError("pbxproj not exist!: \(pbxprojPath.string)")
        exit(1)
    }
    let projRoot = xcodeprojPath + ".."
    // validate DIR
    guard dirPath.absolute().components.starts(with: projRoot.absolute().components) else {
        printStdError("Invalid DIR parameter: \(dirPath.string)\nIt must be descendant of xcodeproj's root dir: \(projRoot.string)")
        exit(1)
    }

    if dirPath.isFile {
        printStdError("file already exists: \(dirPath.string)")
        exit(1)
    }
    if dirPath.isDirectory == false {
        try! dirPath.mkpath()
    }

    // config
    let config = Config(isIncludeExisting: isIncludeExisting)
    let formatter = ResultFormatter(config: config)

    //
    // read
    //
    guard let pbxproj = try? Pbxproj(path: pbxprojPath.string) else {
        printStdError("Failed to parse Pbxproj")
        exit(1)
    }

    //
    // write
    //
    var baseResults = [ResultObject]()
    var targetResults = [ResultObject]()

    // base
    for configuration in pbxproj.rootObject.buildConfigurationList.buildConfigurations {
        let filePath = Path("\(dirPath.string)/\(configuration.name).xcconfig")
        let buildSettings = configuration.buildSettings.dictionary
        let lines = convertToLines(buildSettings)
        let r = ResultObject(path: filePath, settings: lines, configurationName: configuration.name)
        if config.isIncludeExisting {
            if let fileref = configuration.baseConfigurationReference {
                let depth = (dirPath.components - projRoot.components).count
                let prefix = (0..<depth).reduce("") { $0.0 + "../" }
                r.includes = [prefix + fileref.fullPath]
            }
        }
        baseResults.append(r)
    }

    // targets
    let configurations = pbxproj.rootObject.buildConfigurationList.buildConfigurations
    let configurationNames = Set(configurations.map { c in c.name })
    for target in pbxproj.targets {
        let targetName = target.name
        for configuration in target.buildConfigurationList.buildConfigurations {
            let filePath = Path("\(dirPath.string)/\(targetName)-\(configuration.name).xcconfig")
            let buildSettings = configuration.buildSettings.dictionary
            let lines = convertToLines(buildSettings)

            let r = ResultObject(path: filePath, settings: lines, targetName: targetName, configurationName: configuration.name)
            if config.isIncludeExisting {
                if let fileref = configuration.baseConfigurationReference {
                    let depth = (dirPath.components - projRoot.components).count
                    let prefix = (0..<depth).reduce("") { $0.0 + "../" }
                    r.includes = [prefix + fileref.fullPath]
                }
            }
            targetResults.append(r)
        }
    }

    // Base.xcconfig
    if isNoTrimDuplicates {
        for r in (baseResults + targetResults) {
            try write(to: r.path, lines: formatter.format(result: r))
        }
    } else {
        // Trim Duplicates in same configurationNames
        for configurationName in configurationNames {
            let filtered = targetResults
                .filter { $0.path.components.last!.contains("-\(configurationName).xcconfig") }
            let common: [String] = commonElements(filtered.map { $0.settings })
            let idx = baseResults.index { $0.configurationName == configurationName }!
            baseResults[idx].settings = distinctArray(common + baseResults[idx].settings)
            // Write Upper Layer Configs (e.g. App-Debug.xcconfig, AppTests-Debug.xcconfig)
            for r in filtered {
                let idx = targetResults.index(of: r)!
                targetResults[idx].settings = r.settings - common
            }
        }
        // Trim Duplicates in target configs (e.g. App-Debug.xcconfig and App-Release.xcconfig)
        for target in pbxproj.targets {
            let filtered = targetResults
                .filter { $0.path.components.last!.characters.starts(with: "\(target.name)-".characters) }
            let common: [String] = commonElements(filtered.map { $0.settings })
            let targetConfigPath = Path("\(dirPath.string)/\(target.name).xcconfig")
            let r = ResultObject(path: targetConfigPath, settings: common)
            try write(to: r.path, lines: formatter.format(result: r))
            for r in filtered {
                let idx = targetResults.index(of: r)!
                targetResults[idx].settings = r.settings - common
                targetResults[idx].includes += [targetConfigPath.lastComponent]
                try write(to: r.path, lines: formatter.format(result: targetResults[idx]))
            }
        }

        // Trim Duplicates in configurationName configs (e.g. Debug.xcconfig and Release.xcconfig)
        let common = commonElements(baseResults.map { $0.settings })
        // Write Configuration Base Configs (e.g. Debug.xcconfig, Release.xcconfig)
        for r in baseResults {
            r.settings = r.settings - common
            try write(to: r.path, lines: formatter.format(result: r, includes: ["Base.xcconfig"]))
        }
        // Finally Write Base.xcconfig
        let r = ResultObject(path: Path("\(dirPath.string)/Base.xcconfig"), settings: common)
        try write(to: r.path, lines: formatter.format(result: r))
    }

    if isNoEdit {
        return
    }
    // Remove buildSettings from pbxproj and Setup xcconfigs
    try! pbxproj.rootObject.mainGroup.addFiles(paths: [dirPath.normalize().string])
    for configuration in pbxproj.rootObject.buildConfigurationList.buildConfigurations {
        configuration.buildSettings = [:]
        if isPreserveConfigured {
            continue
        }
        if let fileref = pbxproj.fileReferences(named: "\(configuration.name).xcconfig").first  {
            configuration.baseConfigurationReference = fileref
        } else {
            printStdError("Failed to locate xcconfig")
        }
    }
    for target in pbxproj.targets {
        for configuration in target.buildConfigurationList.buildConfigurations {
            configuration.buildSettings = [:]
            if isPreserveConfigured {
                continue
            }
            if let fileref = pbxproj.fileReferences(named: "\(target.name)-\(configuration.name).xcconfig").first {
                configuration.baseConfigurationReference = fileref
            }
        }
    }
    do {
        try pbxproj.write(path: pbxprojPath.string)
    } catch {
        printStdError("Failed to save pbxproj.")
    }
}

main.run(Config.version)
