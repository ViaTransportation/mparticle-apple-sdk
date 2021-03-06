#import "MPIUserDefaults.h"
#import "MPPersistenceController.h"
#import "MPIConstants.h"

static NSString *const NSUserDefaultsPrefix = @"mParticle::";

@implementation MPIUserDefaults

#pragma mark Private methods
- (NSArray<NSString *> *)userSpecificKeys {
    NSArray<NSString *> *userSpecificKeys = @[
                                              @"lud",               /* kMPAppLastUseDateKey */
                                              @"lc",                /* kMPAppLaunchCountKey */
                                              @"lcu",               /* kMPAppLaunchCountSinceUpgradeKey */
                                              @"ua",                /* kMPUserAttributeKey */
                                              @"ui",                /* kMPUserIdentityArrayKey */
                                              @"ck",                /* kMPRemoteConfigCookiesKey */
                                              @"ltv",               /* kMPLifeTimeValueKey */
                                              @"is_ephemeral",      /* kMPIsEphemeralKey */
                                              @"last_date_used"     /* kMPLastIdentifiedDate  */
                                              ];
    return userSpecificKeys;
}

- (NSArray<NSString *> *)extensionExcludedKeys {
    NSArray<NSString *> *extensionExcludedKeys = @[
                                              ];
    return extensionExcludedKeys;
}

- (NSString *)globalKeyForKey:(NSString *)key {
    NSString *globalKey = [NSString stringWithFormat:@"%@%@", NSUserDefaultsPrefix, key];
    return globalKey;
}

- (NSString *)userKeyForKey:(NSString *)key userId:(NSNumber *)userId {
    NSString *userKey = [NSString stringWithFormat:@"%@%@::%@", NSUserDefaultsPrefix, userId, key];
    return userKey;
}

- (BOOL)isUserSpecificKey:(NSString *)keyName {
    NSArray<NSString *> *userSpecificKeys = [self userSpecificKeys];
    
    if ([userSpecificKeys containsObject:keyName]) {
        return YES;
    }
    else {
        return NO;
    }
}

- (NSString *)prefixedKey:(NSString *)keyName userId:(NSNumber *)userId {
    NSString *prefixedKey = nil;
    if (![self isUserSpecificKey:keyName]) {
        prefixedKey = [self globalKeyForKey:keyName];
        return prefixedKey;
    }
    else {
        NSString *prefixedKey = [self userKeyForKey:keyName userId:userId];
        return prefixedKey;
    }
}

- (NSUserDefaults *)customUserDefaults {
    NSString *sharedGroupID = [[NSUserDefaults standardUserDefaults] objectForKey:kMPUserIdentitySharedGroupIdentifier];
    if (sharedGroupID) {
        // Create and share access to an NSUserDefaults object
        return [[NSUserDefaults alloc] initWithSuiteName: sharedGroupID];
    } else {
        return [NSUserDefaults standardUserDefaults];
    }
}

#pragma mark Public class methods
+ (nonnull instancetype)standardUserDefaults {
    static MPIUserDefaults *standardUserDefaults = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        standardUserDefaults = [[MPIUserDefaults alloc] init];
    });

    return standardUserDefaults;
}

#pragma mark Public methods

- (id)mpObjectForKey:(NSString *)key userId:(NSNumber *)userId {
    NSString *prefixedKey = [self prefixedKey:key userId:userId];
    
    // If the shared key is set but that attribute hasn't been set in the shared user this defaults to getting the info for standard user info
    id mpObject = [[self customUserDefaults] objectForKey:prefixedKey];
    if (mpObject) {
        return mpObject;
    } else {
        return [[NSUserDefaults standardUserDefaults] objectForKey:prefixedKey];
    }
}

- (void)setMPObject:(id)value forKey:(NSString *)key userId:(nonnull NSNumber *)userId {
    NSString *sharedGroupID = [[NSUserDefaults standardUserDefaults] objectForKey:kMPUserIdentitySharedGroupIdentifier];
    NSString *prefixedKey = [self prefixedKey:key userId:userId];
    
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:prefixedKey];
    if (sharedGroupID && ![self.extensionExcludedKeys containsObject:key]) {
        [[[NSUserDefaults alloc] initWithSuiteName: sharedGroupID] setObject:value forKey:prefixedKey];
    }
}

- (void)removeMPObjectForKey:(NSString *)key userId:(nonnull NSNumber *)userId {
    NSString *sharedGroupID = [[NSUserDefaults standardUserDefaults] objectForKey:kMPUserIdentitySharedGroupIdentifier];
    NSString *prefixedKey = [self prefixedKey:key userId:userId];
    
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:prefixedKey];
    if (sharedGroupID) {
        [[[NSUserDefaults alloc] initWithSuiteName: sharedGroupID] removeObjectForKey:prefixedKey];
    }
}

- (void)removeMPObjectForKey:(NSString *)key {
    [self removeMPObjectForKey:key userId:[MPPersistenceController mpId]];
}

- (void)synchronize {
    NSString *sharedGroupID = [[NSUserDefaults standardUserDefaults] objectForKey:kMPUserIdentitySharedGroupIdentifier];
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (sharedGroupID) {
        [[[NSUserDefaults alloc] initWithSuiteName: sharedGroupID] synchronize];
    }
}

- (void)migrateUserKeysWithUserId:(NSNumber *)userId {
    NSArray<NSString *> *userSpecificKeys = [self userSpecificKeys];
    NSUserDefaults *userDefaults = [self customUserDefaults];
    
    [userSpecificKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *globalKey = [self globalKeyForKey:key];
        NSString *userKey = [self userKeyForKey:key userId:userId];
        id value = [userDefaults objectForKey:globalKey];
        [userDefaults setObject:value forKey:userKey];
        [userDefaults removeObjectForKey:globalKey];
    }];
    [userDefaults synchronize];
}

- (void)migrateToSharedGroupIdentifier:(NSString *)groupIdentifier {
    //Set up our identities to be shared between the main app and its extensions
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *groupUserDefaults = [[NSUserDefaults alloc] initWithSuiteName: groupIdentifier];
    
    [standardUserDefaults setValue:groupIdentifier forKey:kMPUserIdentitySharedGroupIdentifier];
    
    for (NSString *key in [[standardUserDefaults dictionaryRepresentation] allKeys]) {
        if (![self.extensionExcludedKeys containsObject:key]) {
            [groupUserDefaults setObject:[standardUserDefaults objectForKey:key] forKey:key];
        }
    }
}

- (void)migrateFromSharedGroupIdentifier {
    //Revert to the original way of storing our user identity info
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    NSUserDefaults *groupUserDefaults = [[NSUserDefaults alloc] initWithSuiteName: [standardUserDefaults objectForKey:kMPUserIdentitySharedGroupIdentifier]];
    
    for (NSString *key in [[groupUserDefaults dictionaryRepresentation] allKeys]) {
        [groupUserDefaults removeObjectForKey:key];
    }
    
    [standardUserDefaults removeObjectForKey:kMPUserIdentitySharedGroupIdentifier];
}

- (BOOL)isExistingUserId:(NSNumber *)userId {
    NSDate *dateLastIdentified = [self mpObjectForKey:kMPLastIdentifiedDate userId:userId];
    if (dateLastIdentified != nil) {
        return true;
    }
    
    return false;
}

#pragma mark Objective-C Literals
- (id)objectForKeyedSubscript:(NSString *const)key {
    if ([key isEqualToString:@"mpid"]) {
        return [self mpObjectForKey:key userId:@0];
    }
    return [self mpObjectForKey:key userId:[MPPersistenceController mpId]];
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    if (obj) {
        [self setMPObject:obj forKey:key userId:[MPPersistenceController mpId]];
    } else {
        [self removeMPObjectForKey:key userId:[MPPersistenceController mpId]];
    }
}


@end
