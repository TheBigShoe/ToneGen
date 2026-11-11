import XCTest
@testable import Tonegen

final class DBMathTests: XCTestCase {
    func testDbfsToLinearMinus6() {
        XCTAssertEqual(dbfsToLinear(-6), 0.501, accuracy: 1e-3)
    }

    func testDbfsToLinearZero() {
        XCTAssertEqual(dbfsToLinear(0), 1.0, accuracy: 1e-10)
    }

    func testDbfsToLinearFloor() {
        XCTAssertEqual(dbfsToLinear(-120), 1e-6, accuracy: 1e-10)
        XCTAssertEqual(dbfsToLinear(-200), 1e-6, accuracy: 1e-10)
    }

    func testLinearToDbfsRoundTrip() {
        let values: [Double] = [1.0, 0.5, 0.1, 0.01, 1e-6]
        for linear in values {
            let result = dbfsToLinear(linearToDbfs(linear))
            XCTAssertEqual(result, linear, accuracy: linear * 1e-9)
        }
    }

    func testLinearToDbfsZero() {
        XCTAssertEqual(linearToDbfs(0), -120, accuracy: 1e-10)
    }

    func testLinearToDbfsFloor() {
        XCTAssertGreaterThanOrEqual(linearToDbfs(1e-10), -120)
    }
}
