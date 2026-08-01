// DictusApp/Audio/ObjCExceptionCatcher.m
#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)tryBlock:(__attribute__((noescape)) void (^)(void))block
           error:(NSError *_Nullable *_Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: @"Objective-C exception";
            info[@"ExceptionName"] = exception.name ?: @"unknown";
            if (exception.userInfo) {
                info[@"ExceptionUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"DictusAudio.ObjCException"
                                         code:-1
                                     userInfo:info];
        }
        return NO;
    }
}

@end
