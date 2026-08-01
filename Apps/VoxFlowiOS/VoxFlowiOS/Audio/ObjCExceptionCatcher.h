// DictusApp/Audio/ObjCExceptionCatcher.h
// Tiny Objective-C shim that catches NSException thrown by AVFoundation APIs
// (installTapOnBus, engine.start) and converts them into a Swift-catchable NSError.
// Swift's do/catch cannot intercept NSException — the process aborts with SIGABRT.
// See issues #71 and #102 for crashes this protects against.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCExceptionCatcher : NSObject

/// Execute `block` inside an @try/@catch for NSException.
/// Returns YES if the block completed normally, NO if it raised an NSException.
/// On NO, `error` (if non-null) is populated with the exception reason and name.
/// Swift imports this as `catchException(_:)` which throws on NSException.
+ (BOOL)tryBlock:(__attribute__((noescape)) void (^)(void))block
           error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(catchException(_:));

@end

NS_ASSUME_NONNULL_END
