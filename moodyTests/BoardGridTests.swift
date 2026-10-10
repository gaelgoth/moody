//
//  BoardGridTests.swift
//  moodyTests
//

import CoreGraphics
import Testing
@testable import moody

struct BoardGridTests {
    @Test func originAtZeroStartsAtZero() {
        #expect(gridLineOffsets(origin: 0, length: 100, spacing: 40) == [0, 40, 80])
    }

    @Test func negativeNonMultipleOriginStartsAtTheNextBoardMultiple() {
        // Board lines at -40, 0, 40 → local 10, 50, 90.
        #expect(gridLineOffsets(origin: -50, length: 100, spacing: 40) == [10, 50, 90])
    }

    @Test func originExactlyOnAMultipleStartsAtZero() {
        #expect(gridLineOffsets(origin: -80, length: 100, spacing: 40) == [0, 40, 80])
    }

    @Test func lengthShorterThanFirstOffsetIsEmpty() {
        #expect(gridLineOffsets(origin: 30, length: 5, spacing: 40).isEmpty)
    }
}
