//
//  Pair.swift
//  
//
//  Created by Eric Rabil on 1/28/22.
//

import Foundation

@_spi(featureFlagInternals) public enum Pair<A: Hashable, B: Hashable>: Hashable {
    // In terms of Swift memory, a single-case enum is equivalent to a tuple.
    // So, we get a hashable tuple. Yay.
    case some(A,B)
}
