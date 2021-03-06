#import <Foundation/Foundation.h>

@class MPAttributionResult;

@interface MPKitAPI : NSObject

- (void)logError:(NSString *)format, ...;
- (void)logWarning:(NSString *)format, ...;
- (void)logDebug:(NSString *)format, ...;
- (void)logVerbose:(NSString *)format, ...;

- (NSDictionary<NSString *, NSString *> *)integrationAttributes;
- (NSDictionary<NSNumber *, NSString *> *)userIdentities;
- (NSDictionary<NSString *, id> *)userAttributes;
- (void)onAttributionCompleteWithResult:(MPAttributionResult *)result error:(NSError *)error;

@end
