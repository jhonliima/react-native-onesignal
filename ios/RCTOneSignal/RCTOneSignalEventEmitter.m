//
//  RCTOneSignalEventEmitter.m
//  RCTOneSignal
//
//  Created by Brad Hesse on 2/8/18.
//

#import "RCTOneSignalEventEmitter.h"
#import "OneSignal.h"


#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"


@implementation RCTOneSignalEventEmitter {
    BOOL hasListeners;
}

static BOOL _didStartObserving = false;

+ (BOOL)hasSetBridge {
    return _didStartObserving;
}

/*
     This class acts as the module & event emitter
     It is initialized automatically by React-Native
     This subclass handles communication between the SDK and JavaScript
*/

RCT_EXPORT_MODULE(RCTOneSignal)

#pragma mark RCTEventEmitter Subclass Methods

-(instancetype)init {
    if (self = [super init]) {
        [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"Initialized RCTOneSignalEventEmitter"];
        
        for (NSString *eventName in [self supportedEvents])
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emitEvent:) name:eventName object:nil];
    }
    
    return self;
}

-(void)startObserving {
    hasListeners = true;
    [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"RCTOneSignalEventEmitter did start observing"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"didSetBridge" object:nil];
    
    _didStartObserving = true;
}

-(void)stopObserving {
    hasListeners = false;
    [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"RCTOneSignalEventEmitter did stop observing"];
}

-(NSArray<NSString *> *)supportedEvents {
    NSMutableArray *events = [NSMutableArray new];
    
    for (int i = 0; i < OSNotificationEventTypesArray.count; i++)
        [events addObject:OSEventString(i)];
    
    return events;
}


#pragma mark Send Event Methods

- (void)emitEvent:(NSNotification *)notification {
    if (!hasListeners) {
        [OneSignal onesignal_Log:ONE_S_LL_WARN message:[NSString stringWithFormat:@"Attempted to send an event (%@) when no listeners were set.", notification.name]];
        return;
    }
    
    [self sendEventWithName:notification.name body:notification.userInfo];
}

+ (void)sendEventWithName:(NSString *)name withBody:(NSDictionary *)body {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:body];
}


#pragma mark Exported Methods

RCT_EXPORT_METHOD(checkPermissions:(RCTResponseSenderBlock)callback)
{
    if (RCTRunningInAppExtension()) {
        callback(@[@{@"alert": @NO, @"badge": @NO, @"sound": @NO}]);
        return;
    }
    
    NSUInteger types = 0;
    if ([UIApplication instancesRespondToSelector:@selector(currentUserNotificationSettings)]) {
        types = [RCTSharedApplication() currentUserNotificationSettings].types;
    } else {
        
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0
        types = [RCTSharedApplication() enabledRemoteNotificationTypes];
#endif
        
    }
    
    callback(@[@{
       @"alert": @((types & UIUserNotificationTypeAlert) > 0),
       @"badge": @((types & UIUserNotificationTypeBadge) > 0),
       @"sound": @((types & UIUserNotificationTypeSound) > 0),
    }]);
}

RCT_EXPORT_METHOD(requestPermissions:(NSDictionary *)permissions) {
    if (RCTRunningInAppExtension()) {
        return;
    }
    
    UIUserNotificationType types = UIUserNotificationTypeNone;
    if (permissions) {
        if ([RCTConvert BOOL:permissions[@"alert"]]) {
            types |= UIUserNotificationTypeAlert;
        }
        if ([RCTConvert BOOL:permissions[@"badge"]]) {
            types |= UIUserNotificationTypeBadge;
        }
        if ([RCTConvert BOOL:permissions[@"sound"]]) {
            types |= UIUserNotificationTypeSound;
        }
    } else {
        types = UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
    }
    
    UIApplication *app = RCTSharedApplication();
    if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *notificationSettings =
        [UIUserNotificationSettings settingsForTypes:(NSUInteger)types categories:nil];
        [app registerUserNotificationSettings:notificationSettings];
        [app registerForRemoteNotifications];
    } else {
        [app registerForRemoteNotificationTypes:(NSUInteger)types];
    }
}

RCT_EXPORT_METHOD(setEmail :(NSString *)email withAuthHash:(NSString *)authHash withResponse:(RCTResponseSenderBlock)callback) {
    // Auth hash token created on server and sent to client.
    
    [OneSignal setEmail:email withEmailAuthHashToken:authHash withSuccess:^{
        callback(@[]);
    } withFailure:^(NSError *error) {
        callback(@[error]);
    }];
}

RCT_EXPORT_METHOD(setUnauthenticatedEmail:(NSString *)email withResponse:(RCTResponseSenderBlock)callback) {
    // Does not use an email auth has token, uses unauthenticated state
    [OneSignal setEmail:email withSuccess:^{
        callback(@[]);
    } withFailure:^(NSError *error) {
        callback(@[error]);
    }];
}

RCT_EXPORT_METHOD(logoutEmail:(RCTResponseSenderBlock)callback) {
    [OneSignal logoutEmailWithSuccess:^{
        callback(@[]);
    } withFailure:^(NSError *error) {
        callback(@[error]);
    }];
}

RCT_EXPORT_METHOD(getPermissionSubscriptionState:(RCTResponseSenderBlock)callback)
{
    if (RCTRunningInAppExtension()) {
        callback(@[@{
                       @"hasPrompted": @NO,
                       @"notificationsEnabled": @NO,
                       @"subscriptionEnabled": @NO,
                       @"userSubscriptionEnabled": @NO,
                       @"pushToken": [NSNull null],
                       @"userId": [NSNull null],
                       }]);
    }
    
    OSPermissionSubscriptionState *state = [OneSignal getPermissionSubscriptionState];
    OSPermissionState *permissionState = state.permissionStatus;
    OSSubscriptionState *subscriptionState = state.subscriptionStatus;
    OSEmailSubscriptionState *emailState = state.emailSubscriptionStatus;
    
    // Received push notification prompt? (iOS only property)
    BOOL hasPrompted = permissionState.hasPrompted == 1;
    
    // Notifications enabled for app? (iOS Settings)
    BOOL notificationsEnabled = permissionState.status == 2;
    
    // User subscribed to OneSignal? (automatically toggles with notificationsEnabled)
    BOOL subscriptionEnabled = subscriptionState.subscribed == 1;
    
    // User's original subscription preference (regardless of notificationsEnabled)
    BOOL userSubscriptionEnabled = subscriptionState.userSubscriptionSetting == 1;
    
    callback(@[@{
       @"hasPrompted": @(hasPrompted),
       @"notificationsEnabled": @(notificationsEnabled),
       @"subscriptionEnabled": @(subscriptionEnabled),
       @"userSubscriptionEnabled": @(userSubscriptionEnabled),
       @"pushToken": subscriptionState.pushToken ?: [NSNull null],
       @"userId": subscriptionState.userId ?: [NSNull null],
       @"emailSubscribed" : @(emailState.subscribed),
       @"emailAddress" : emailState.emailAddress ?: [NSNull null]
    }]);
}

RCT_EXPORT_METHOD(setInFocusDisplayType:(int)displayType) {
    [OneSignal setInFocusDisplayType:displayType];
}

RCT_EXPORT_METHOD(registerForPushNotifications) {
    [OneSignal registerForPushNotifications];
}

RCT_EXPORT_METHOD(promptForPushNotificationsWithUserResponse:(RCTResponseSenderBlock)callback) {
    [OneSignal promptForPushNotificationsWithUserResponse:^(BOOL accepted) {
        [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"Prompt For Push Notifications Success"];
        callback(@[@(accepted)]);
    }];
}

RCT_EXPORT_METHOD(sendTag:(NSString *)key value:(NSString*)value) {
    [OneSignal sendTag:key value:value];
}

RCT_EXPORT_METHOD(configure) {
    [OneSignal IdsAvailable:^(NSString* userId, NSString* pushToken) {
        
        NSDictionary *params = @{
         @"pushToken": pushToken ?: [NSNull null],
         @"userId" : userId ?: [NSNull null]
        };
        
        [RCTOneSignalEventEmitter sendEventWithName:@"OneSignal-idsAvailable" withBody:params];
    }];
}

RCT_EXPORT_METHOD(sendTags:(NSDictionary *)properties) {
    [OneSignal sendTags:properties onSuccess:^(NSDictionary *sucess) {
        [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"Send Tags Success"];
    } onFailure:^(NSError *error) {
        [OneSignal onesignal_Log:ONE_S_LL_ERROR message:[NSString stringWithFormat:@"Send Tags Failure With Error: %@", error]];
    }];}

RCT_EXPORT_METHOD(getTags:(RCTResponseSenderBlock)callback) {
    [OneSignal getTags:^(NSDictionary *tags) {
        [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:@"Get Tags Success"];
        callback(@[tags]);
    } onFailure:^(NSError *error) {
        [OneSignal onesignal_Log:ONE_S_LL_VERBOSE message:[NSString stringWithFormat:@"Get Tags Failure with error: %@", error]];
        callback(@[error]);
    }];
}

RCT_EXPORT_METHOD(setLocationShared:(BOOL)shared) {
    [OneSignal setLocationShared:shared];
}

RCT_EXPORT_METHOD(deleteTag:(NSString *)key) {
    [OneSignal deleteTag:key];
}

RCT_EXPORT_METHOD(setSubscription:(BOOL)enable) {
    [OneSignal setSubscription:enable];
}

RCT_EXPORT_METHOD(promptLocation) {
    [OneSignal promptLocation];
}

RCT_EXPORT_METHOD(postNotification:(NSDictionary *)contents data:(NSDictionary *)data player_id:(NSString*)player_id other_parameters:(NSDictionary *)other_parameters) {
    NSDictionary * additionalData = @{@"p2p_notification": data};
    
    NSMutableDictionary * extendedData = [additionalData mutableCopy];
    BOOL isHidden = [[other_parameters objectForKey:@"hidden"] boolValue];
    if (isHidden) {
        [extendedData setObject:[NSNumber numberWithBool:YES] forKey:@"hidden"];
    }
    
    NSDictionary *notification = @{
                                   @"contents" : contents,
                                   @"data" : extendedData,
                                   @"include_player_ids": @[player_id]
                                   };
    NSMutableDictionary * extendedNotification = [notification mutableCopy];
    [extendedNotification addEntriesFromDictionary: other_parameters];
    
    [OneSignal postNotification:extendedNotification];
}

RCT_EXPORT_METHOD(syncHashedEmail:(NSString*)email) {
    [OneSignal syncHashedEmail:email];
}

RCT_EXPORT_METHOD(setLogLevel:(int)logLevel visualLogLevel:(int)visualLogLevel) {
    [OneSignal setLogLevel:logLevel visualLevel:visualLogLevel];
}


@end
