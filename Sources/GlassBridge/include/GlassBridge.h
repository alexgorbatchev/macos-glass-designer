#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Private API access is isolated here so an Objective-C exception is reported, never swallowed.
FOUNDATION_EXPORT id _Nullable GDRead(id object, NSString *keyPath, NSString * _Nullable * _Nullable failure);
FOUNDATION_EXPORT BOOL GDWrite(id object, NSString *keyPath, id _Nullable value, NSString * _Nullable * _Nullable failure);
FOUNDATION_EXPORT id _Nullable GDMakeFilter(NSString *type);
NS_ASSUME_NONNULL_END
