// Verifies block writes into the scope ring wrap correctly and readers see the newest samples.
import XCTest
@testable import Tonegen

final class SampleRingBufferTests: XCTestCase {
    func testEmptyRingReadsNothing() {
        let ring = SampleRingBuffer(capacity: 8)
        var out = [Float](repeating: -1, count: 8)
        XCTAssertEqual(ring.readLatest(8, into: &out), 0)
    }

    func testPartialFillReturnsOnlyWrittenSamples() {
        let ring = SampleRingBuffer(capacity: 8)
        write(ring, [1, 2, 3])
        var out = [Float](repeating: 0, count: 8)
        let n = ring.readLatest(8, into: &out)
        XCTAssertEqual(n, 3)
        XCTAssertEqual(Array(out[0 ..< n]), [1, 2, 3])
    }

    func testBlockWritesWrapAroundInOrder() {
        let ring = SampleRingBuffer(capacity: 8)
        // 5 + 5 = 10 samples: the second block straddles the end of an 8-slot ring.
        write(ring, [1, 2, 3, 4, 5])
        write(ring, [6, 7, 8, 9, 10])
        var out = [Float](repeating: 0, count: 8)
        let n = ring.readLatest(8, into: &out)
        XCTAssertEqual(n, 8)
        XCTAssertEqual(out, [3, 4, 5, 6, 7, 8, 9, 10])

        let newest = ring.readLatest(3, into: &out)
        XCTAssertEqual(newest, 3)
        XCTAssertEqual(Array(out[0 ..< newest]), [8, 9, 10])
    }

    func testManyWrapsKeepLatestSamples() {
        let ring = SampleRingBuffer(capacity: 16)
        var next: Float = 0
        // Odd block size so block boundaries land on every ring offset over time.
        for _ in 0 ..< 100 {
            var block = [Float](repeating: 0, count: 7)
            for k in 0 ..< block.count {
                block[k] = next
                next += 1
            }
            write(ring, block)
        }
        var out = [Float](repeating: 0, count: 16)
        XCTAssertEqual(ring.readLatest(16, into: &out), 16)
        let expected = (0 ..< 16).map { next - 16 + Float($0) }
        XCTAssertEqual(out, expected)
    }

    func testBlockLargerThanCapacityKeepsNewestSamples() {
        let ring = SampleRingBuffer(capacity: 8)
        write(ring, [100])
        write(ring, (0 ..< 21).map(Float.init))
        var out = [Float](repeating: 0, count: 8)
        XCTAssertEqual(ring.readLatest(8, into: &out), 8)
        XCTAssertEqual(out, (13 ..< 21).map(Float.init))
    }

    func testReadIsClampedToOutputSize() {
        let ring = SampleRingBuffer(capacity: 8)
        write(ring, [1, 2, 3, 4, 5, 6])
        var out = [Float](repeating: 0, count: 4)
        XCTAssertEqual(ring.readLatest(8, into: &out), 4)
        XCTAssertEqual(out, [3, 4, 5, 6])
    }

    // MARK: - Helpers

    private func write(_ ring: SampleRingBuffer, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { ring.write($0) }
    }
}
