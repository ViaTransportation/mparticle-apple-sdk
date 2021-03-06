//
//  MPIdentityApi.m
//

#import "MPIdentityApi.h"
#import "MPIdentityApiManager.h"
#import "mParticle.h"
#import "MPBackendController.h"
#import "MPStateMachine.h"
#import "MPConsumerInfo.h"
#import "MPIUserDefaults.h"
#import "MPSession.h"
#import "MPPersistenceController.h"
#import "MPIdentityDTO.h"
#import "MPEnums.h"
#import "MPILogger.h"

@interface MPIdentityApi ()

@property (nonatomic, strong) MPIdentityApiManager *apiManager;
@property(nonatomic, strong, readwrite, nonnull) MParticleUser *currentUser;

@end

@interface MParticle ()

@property (nonatomic, strong, nonnull) MPBackendController *backendController;

@end

@interface MPBackendController ()

- (NSMutableDictionary<NSString *, id> *)userAttributesForUserId:(NSNumber *)userId;

@end

@interface MParticleUser ()

- (void)setUserIdentity:(NSString *)identityString identityType:(MPUserIdentity)identityType;
- (void)setUserId:(NSNumber *)userId;
@end

@implementation MPIdentityApi

@synthesize currentUser = _currentUser;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _apiManager = [[MPIdentityApiManager alloc] init];
    }
    return self;
}

- (void)onModifyRequestComplete:(MPIdentityApiRequest *)request httpResponse:(MPIdentityHTTPModifySuccessResponse *) httpResponse completion:(MPIdentityApiResultCallback)completion error: (NSError *) error {
    if (error) {
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    if (request.userIdentities) {
        [request.userIdentities enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id identityValue, BOOL * _Nonnull stop) {
            MPUserIdentity identityType = (MPUserIdentity)key.intValue;
            if ((NSNull *)identityValue == [NSNull null]) {
                identityValue = nil;
            }
            [self.currentUser setUserIdentity:identityValue identityType:identityType];
        }];
    }
    if (completion) {
        MPIdentityApiResult *apiResult = [[MPIdentityApiResult alloc] init];
        apiResult.user = self.currentUser;
        completion(apiResult, nil);
    }
}

- (void)onIdentityRequestComplete:(MPIdentityApiRequest *)request httpResponse:(MPIdentityHTTPSuccessResponse *) httpResponse completion:(MPIdentityApiResultCallback)completion error: (NSError *) error {
    if (error) {
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    NSNumber *previousMPID = [MPPersistenceController mpId];
    [MPPersistenceController setMpid:httpResponse.mpid];
    MPIdentityApiResult *apiResult = [[MPIdentityApiResult alloc] init];
    MParticleUser *previousUser = self.currentUser;
    MParticleUser *user = [[MParticleUser alloc] init];
    user.userId = httpResponse.mpid;
    apiResult.user = user;
    self.currentUser = user;
    MPSession *session = [MParticle sharedInstance].backendController.session;
    session.userId = httpResponse.mpid;
    NSString *userIdsString = session.sessionUserIds;
    NSMutableArray *userIds = [[userIdsString componentsSeparatedByString:@","] mutableCopy];
    
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];

    if (user.userId.longLongValue != 0) {
        [userDefaults setMPObject:[NSDate date] forKey:kMPLastIdentifiedDate userId:user.userId];
        [userDefaults synchronize];
    }
    
    if (httpResponse.mpid.longLongValue != 0 &&
        ([userIds lastObject] && ![[userIds lastObject] isEqualToString:httpResponse.mpid.stringValue])) {
        [userIds addObject:httpResponse.mpid];
    }
    
    session.sessionUserIds = userIds.count > 0 ? [userIds componentsJoinedByString:@","] : @"";
    [[MPPersistenceController sharedInstance] updateSession:session];
    
    if (request.userIdentities) {
        [request.userIdentities enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id  _Nonnull identityValue, BOOL * _Nonnull stop) {
            MPUserIdentity identityType = (MPUserIdentity)key.intValue;
            [self.currentUser setUserIdentity:identityValue identityType:identityType];
        }];
    }
    
    if (httpResponse.mpid.intValue == previousMPID.intValue) {
        if (completion) {
            completion(apiResult, nil);
        }
        return;
    }
    
    if (request.onUserAlias) {
        @try {
            request.onUserAlias(previousUser, user);
        } @catch (NSException *exception) {
            MPILogError(@"Identity request - onUserAlias block threw an exception when invoked by the SDK: %@", exception);
        }
    }
    
    [userDefaults setMPObject:@(httpResponse.isEphemeral) forKey:kMPIsEphemeralKey userId:httpResponse.mpid];
    [userDefaults synchronize];

    [[MPPersistenceController sharedInstance] moveContentFromMpidZeroToMpid:httpResponse.mpid];
    
    if (user) {
        NSDictionary *userInfo = @{mParticleUserKey:user};
        [[NSNotificationCenter defaultCenter] postNotificationName:mParticleIdentityStateChangeListenerNotification object:nil userInfo:userInfo];
    }
    
    if (completion) {
        completion(apiResult, nil);
    }
}

- (MParticleUser *)currentUser {
    if (_currentUser) {
        return _currentUser;
    }

    NSNumber *mpid = [MPPersistenceController mpId];
    MParticleUser *user = [[MParticleUser alloc] init];
    user.userId = mpid;
    _currentUser = user;
    return _currentUser;
}

- (MParticleUser *)getUser:(NSNumber *)mpId {
    MPIUserDefaults *userDefaults = [MPIUserDefaults standardUserDefaults];
    if ([userDefaults isExistingUserId:mpId]) {
        MParticleUser *user = [[MParticleUser alloc] init];
        user.userId = mpId;
        return user;
    } else {
        return nil;
    }
}

- (void)identify:(MPIdentityApiRequest *)identifyRequest completion:(nullable MPIdentityApiResultCallback)completion {
    [_apiManager identify:identifyRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
        [self onIdentityRequestComplete:identifyRequest httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:completion error: error];
    }];
}

- (void)identifyWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self identify:(id _Nonnull)nil completion:completion];
}

- (void)login:(MPIdentityApiRequest *)loginRequest completion:(nullable MPIdentityApiResultCallback)completion {
    [_apiManager loginRequest:loginRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
        [self onIdentityRequestComplete:loginRequest httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:completion error: error];
    }];
}

- (void)loginWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self login:(id _Nonnull)nil completion:completion];
}

- (void)logout:(MPIdentityApiRequest *)logoutRequest completion:(nullable MPIdentityApiResultCallback)completion {
    [_apiManager logout:logoutRequest completion:^(MPIdentityHTTPBaseSuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
        [self onIdentityRequestComplete:logoutRequest httpResponse:(MPIdentityHTTPSuccessResponse *)httpResponse completion:completion error: error];
    }];
}

- (void)logoutWithCompletion:(nullable MPIdentityApiResultCallback)completion {
    [self logout:(id _Nonnull)nil completion:completion];
}

- (void)modify:(MPIdentityApiRequest *)modifyRequest completion:(nullable MPIdentityApiResultCallback)completion {
    [_apiManager modify:modifyRequest completion:^(MPIdentityHTTPModifySuccessResponse * _Nonnull httpResponse, NSError * _Nullable error) {
        [self onModifyRequestComplete:modifyRequest httpResponse:httpResponse completion:completion error: error];
    }];
}

@end

@implementation MPIdentityApiResult

@end

@implementation MPIdentityHTTPErrorResponse

- (instancetype)initWithJsonObject:(NSDictionary *)dictionary httpCode:(NSInteger) httpCode {
    self = [super init];
    if (self) {
        _httpCode = httpCode;
        if (dictionary) {
            _code = [dictionary[@"code"] unsignedIntegerValue];
            _message = dictionary[@"message"];
        } else {
            _code = httpCode;
        }
    }
    return self;
}

- (instancetype)initWithCode:(MPIdentityErrorResponseCode) code message: (NSString *) message error: (NSError *) error {
    self = [super init];
    if (self) {
        _code = code;
        _innerError = error;
        _message = message;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [[NSMutableString alloc] initWithString:@"MPIdentityHTTPErrorResponse {\n"];
    [description appendFormat:@"  httpCode: %@\n", @(_httpCode)];
    [description appendFormat:@"  code: %@\n", @(_code)];
    [description appendFormat:@"  message: %@\n", _message];
    [description appendFormat:@"  inner error: %@\n", _innerError];
    [description appendString:@"}"];
    return description;
}

@end
