//
//  Config.swift
//  xcconfig-extractor
//
//  Created by Toshihiro Suzuki on 2017/04/30.
//  Copyright © 2017 Toshihiro Suzuki. All rights reserved.
//

import Foundation

struct Config {
    static let version = "0.2.0"
    let isCocoaPods: Bool
    init(isCocoaPods: Bool) {
        self.isCocoaPods = isCocoaPods
    }
}
