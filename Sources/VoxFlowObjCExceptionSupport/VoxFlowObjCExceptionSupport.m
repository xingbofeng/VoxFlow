#import "VoxFlowObjCExceptionSupport.h"

BOOL VoxFlowPerformCatchingException(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}
