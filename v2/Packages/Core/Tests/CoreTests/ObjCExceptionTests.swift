import Foundation
import XCTest
@testable import Core

final class ObjCExceptionTests: XCTestCase {

    func testNSExceptionWordtEenSwiftFout() {
        XCTAssertThrowsError(try catchingObjCException {
            // NSRangeException uit Foundation, precies het soort fout dat Swift
            // zelf niet kan vangen.
            _ = NSArray().object(at: 5)
        }) { error in
            let objc = error as? ObjCExceptionError
            XCTAssertEqual(objc?.name, NSExceptionName.rangeException.rawValue)
            XCTAssertFalse(objc?.reason.isEmpty ?? true)
        }
    }

    func testGewoonResultaatKomtTerug() throws {
        XCTAssertEqual(try catchingObjCException { 42 }, 42)
    }

    func testSwiftFoutBlijftSwiftFout() {
        struct Eigen: Error {}
        XCTAssertThrowsError(try catchingObjCException { throw Eigen() }) { error in
            XCTAssertTrue(error is Eigen)
        }
    }
}
