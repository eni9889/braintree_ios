#import "BTPayPalAppSwitchHandler_Internal.h"

#import "BTClient+BTPayPal.h"
#import "BTMutablePayPalPaymentMethod.h"
#import "BTLogger.h"
#import "BTErrors+BTPayPal.h"

#import "PayPalMobile.h"
#import "PayPalTouch.h"

@implementation BTPayPalAppSwitchHandler

@synthesize returnURLScheme;
@synthesize delegate;

+ (instancetype)sharedHandler {
    static BTPayPalAppSwitchHandler *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BTPayPalAppSwitchHandler alloc] init];
    });
    return instance;
}

- (BOOL)canHandleReturnURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication {
    if (![[self class] validateClient:self.client delegate:self.delegate returnURLScheme:self.returnURLScheme]) {
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.can-handle.invalid"];
        return NO;
    }

    if (![url.scheme isEqualToString:self.returnURLScheme]) {
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.can-handle.different-scheme"];
        return NO;
    }

    if (![PayPalTouch canHandleURL:url sourceApplication:sourceApplication]) {
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.can-handle.paypal-cannot-handle"];
        return NO;
    }
    return YES;
}

- (void)handleReturnURL:(NSURL *)url {
    PayPalTouchResult *result = [PayPalTouch parseAppSwitchURL:url];
    NSString *code;
    switch (result.resultType) {
        case PayPalTouchResultTypeError: {
            [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.handle.parse-error"];
            NSError *error = [NSError errorWithDomain:BTBraintreePayPalErrorDomain code:BTPayPalUnknownError userInfo:nil];
            [self informDelegateDidFailWithError:error];
            return;
        }
        case PayPalTouchResultTypeCancel:
            [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.handle.cancel"];
            if (result.error) {
                [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.handle.cancel-error"];
                [[BTLogger sharedLogger] log:[NSString stringWithFormat:@"PayPal Wallet error: %@", result.error]];
            }
            [self informDelegateDidCancel];
            return;
        case PayPalTouchResultTypeSuccess:
            code = result.authorization[@"response"][@"code"];
            break;
    }

    if (!code) {
        NSError *error = [NSError errorWithDomain:BTBraintreePayPalErrorDomain code:BTPayPalUnknownError userInfo:@{NSLocalizedDescriptionKey: @"Auth code not found in PayPal Touch app switch response" }];
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.handle.code-error"];
        [self informDelegateDidFailWithError:error];
        return;
    }

    [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.handle.authorized"];

    [self informDelegateWillCreatePayPalPaymentMethod];

    [self.client savePaypalPaymentMethodWithAuthCode:code
                            applicationCorrelationID:[self.client btPayPal_applicationCorrelationId]
                                             success:^(BTPayPalPaymentMethod *paypalPaymentMethod) {
                                                 NSString *userDisplayStringFromAppSwitchResponse = result.authorization[@"user"][@"display_string"];
                                                 if (paypalPaymentMethod.email == nil && [userDisplayStringFromAppSwitchResponse isKindOfClass:[NSString class]]) {
                                                     BTMutablePayPalPaymentMethod *mutablePayPalPaymentMethod = [paypalPaymentMethod mutableCopy];
                                                     mutablePayPalPaymentMethod.email = userDisplayStringFromAppSwitchResponse;
                                                     paypalPaymentMethod = mutablePayPalPaymentMethod;
                                                 }
                                                 [self informDelegateDidCreatePayPalPaymentMethod:paypalPaymentMethod];
                                             } failure:^(NSError *error) {
                                                 [self informDelegateDidFailWithError:error];

                                             }];

}

- (BOOL)initiateAppSwitchWithClient:(BTClient *)client delegate:(id<BTAppSwitchingDelegate>)theDelegate {

    if ([client btPayPal_isTouchDisabled]){
        [client postAnalyticsEvent:@"ios.paypal.appswitch-handler.initiate.disabled"];
        return  NO;
    }

    if (![[self class] validateClient:client delegate:theDelegate returnURLScheme:self.returnURLScheme]) {
        [client postAnalyticsEvent:@"ios.paypal.appswitch-handler.initiate.invalid"];
        return NO;
    }

    if (![PayPalTouch canAppSwitchForUrlScheme:self.returnURLScheme]) {
        [client postAnalyticsEvent:@"ios.paypal.appswitch-handler.initiate.bad-callback-url-scheme"];
        [[BTLogger sharedLogger] log:@"BTPayPalAppSwitchHandler appSwitchCallbackURLScheme not supported by PayPal."];
        return NO;
    }

    _client = client;
    self.delegate = theDelegate;

    PayPalConfiguration *configuration = client.btPayPal_configuration;
    configuration.callbackURLScheme = self.returnURLScheme;

    [self informDelegateWillAppSwitch];
    BOOL payPalTouchDidAuthorize = [PayPalTouch authorizeFuturePayments:configuration];
    if (payPalTouchDidAuthorize) {
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.initiate.success"];
    } else {
        [self.client postAnalyticsEvent:@"ios.paypal.appswitch-handler.initiate.fail"];
    }
    return payPalTouchDidAuthorize;
}

+ (BOOL)validateClient:(BTClient *)client delegate:(id<BTAppSwitchingDelegate>)theDelegate returnURLScheme:(NSString *)theReturnURLScheme {
    if (client == nil) {
        [[BTLogger sharedLogger] log:@"BTPayPalAppSwitchHandler is missing a client."];
        return NO;
    }

    if (theDelegate == nil) {
        [[BTLogger sharedLogger] log:@"BTPayPalAppSwitchHandler is missing a delegate."];
        return NO;
    }

    if (!theReturnURLScheme) {
        [[BTLogger sharedLogger] log:@"BTPayPalAppSwitchHandler is missing a return URL scheme."];
        return NO;
    }

    return YES;
}


#pragma mark Delegate Method Invocations

- (void)informDelegateWillAppSwitch {
  if ([self.delegate respondsToSelector:@selector(appSwitcherWillSwitch:)]) {
    [self.delegate appSwitcherWillSwitch:self];
  }
}

- (void)informDelegateWillCreatePayPalPaymentMethod {
    if ([self.delegate respondsToSelector:@selector(appSwitcherWillCreatePaymentMethod:)]) {
        [self.delegate appSwitcherWillCreatePaymentMethod:self];
    }
}

- (void)informDelegateDidCreatePayPalPaymentMethod:(BTPaymentMethod *)paymentMethod {
    [self.delegate appSwitcher:self didCreatePaymentMethod:paymentMethod];
}

- (void)informDelegateDidFailWithError:(NSError *)error {
    [self.delegate appSwitcher:self didFailWithError:error];
}

- (void)informDelegateDidCancel {
    [self.delegate appSwitcherDidCancel:self];
}

@end