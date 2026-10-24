#import "GlassBridge.h"

id GDRead(id object, NSString *keyPath, NSString **failure) {
    @try { return [object valueForKeyPath:keyPath]; }
    @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:@"%@: %@", keyPath, exception.reason];
        return nil;
    }
}

BOOL GDWrite(id object, NSString *keyPath, id value, NSString **failure) {
    @try { [object setValue:value forKeyPath:keyPath]; return YES; }
    @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:@"%@: %@", keyPath, exception.reason];
        return NO;
    }
}

id GDMakeFilter(NSString *type) {
    Class cls = NSClassFromString(@"CAFilter");
    SEL selector = NSSelectorFromString(@"filterWithType:");
    if (!cls || ![cls respondsToSelector:selector]) return nil;
    typedef id (*Factory)(id, SEL, NSString *);
    return ((Factory)[cls methodForSelector:selector])(cls, selector, type);
}
