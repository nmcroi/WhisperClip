import Foundation
import ObjCExceptionCatcher

/// Een Objective-C-exceptie, opgevangen bij de bron en omgezet naar een gewone
/// Swift-fout, zodat hij nooit door een async-taak heen kan vliegen.
public struct ObjCExceptionError: LocalizedError, Sendable {
    public let name: String
    public let reason: String

    public var errorDescription: String? {
        "\(name): \(reason)"
    }
}

/// Voert `body` uit en zet een `NSException` om in ``ObjCExceptionError``.
/// Zie de toelichting in `ObjCExceptionCatcher.h` voor waarom dit nodig is.
public func catchingObjCException<T>(_ body: () throws -> T) throws -> T {
    var result: Result<T, Error>?
    let exception = WCCatchObjCException {
        result = Result { try body() }
    }
    if let exception {
        throw ObjCExceptionError(
            name: exception.name.rawValue,
            reason: exception.reason ?? "geen reden"
        )
    }
    guard let result else {
        throw ObjCExceptionError(name: "WCCatchObjCException", reason: "geen resultaat")
    }
    return try result.get()
}
