#import "MPResponseEvents.h"
#import "MPConsumerInfo.h"
#import "MPIConstants.h"
#import "MPPersistenceController.h"
#import "MPStateMachine.h"
#import "MPIUserDefaults.h"
#import "MPSession.h"

@implementation MPResponseEvents

+ (void)parseConfiguration:(nonnull NSDictionary *)configuration {
    if (MPIsNull(configuration) || MPIsNull(configuration[kMPMessageTypeKey])) {
        return;
    }
    
    MPPersistenceController *persistence = [MPPersistenceController sharedInstance];

    // Consumer Information
    MPConsumerInfo *consumerInfo = [MPStateMachine sharedInstance].consumerInfo;
    [consumerInfo updateWithConfiguration:configuration[kMPRemoteConfigConsumerInfoKey]];
    [persistence updateConsumerInfo:consumerInfo];
    [persistence fetchConsumerInfoForUserId:[MPPersistenceController mpId] completionHandler:^(MPConsumerInfo *consumerInfo) {
        if (consumerInfo.cookies != nil) {
            [MPStateMachine sharedInstance].consumerInfo.cookies = consumerInfo.cookies;
        }
    }];
}

@end
