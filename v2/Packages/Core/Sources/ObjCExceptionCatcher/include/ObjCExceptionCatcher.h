#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Voert `block` uit en vangt een Objective-C `NSException` op die Swift zelf
/// niet kan vangen. Geeft `nil` terug als alles goed ging, anders de exceptie.
///
/// Waarom dit bestaat (24 september 2026): `AVAudioInputNode.installTap` gooit
/// een NSException bij een formaatverschil na een microfoonwissel. Zo'n
/// exceptie die door een Swift-async-taak heen vliegt en door AppKit wordt
/// opgevangen, laat de Swift-concurrency-runtime achter met een kapotte
/// executorreferentie; de eerstvolgende isolatiecheck crasht dan met
/// EXC_BAD_ACCESS in swift_task_isCurrentExecutor. Vangen bij de bron is de
/// enige remedie.
NSException * _Nullable WCCatchObjCException(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
