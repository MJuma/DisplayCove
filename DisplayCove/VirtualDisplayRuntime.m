#import "VirtualDisplayRuntime.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const DCVirtualDisplayErrorDomain =
    @"dev.juma.DisplayCove.VirtualDisplay";

typedef NS_ENUM(NSInteger, DCVirtualDisplayErrorCode) {
    DCVirtualDisplayErrorUnavailable = 1,
    DCVirtualDisplayErrorCreationFailed = 2,
    DCVirtualDisplayErrorSettingsRejected = 3,
};

static NSError *DCError(
    DCVirtualDisplayErrorCode code,
    NSString *description
) {
    return [NSError errorWithDomain:DCVirtualDisplayErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey: description,
                           }];
}

static BOOL DCRequireClassAndSelectors(
    Class cls,
    NSString *className,
    NSArray<NSString *> *selectors,
    NSError **error
) {
    if (cls == Nil) {
        if (error != NULL) {
            *error = DCError(
                DCVirtualDisplayErrorUnavailable,
                [NSString stringWithFormat:@"%@ is unavailable.", className]
            );
        }
        return NO;
    }

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![cls instancesRespondToSelector:selector]) {
            if (error != NULL) {
                *error = DCError(
                    DCVirtualDisplayErrorUnavailable,
                    [NSString stringWithFormat:
                        @"%@ does not support %@.",
                        className,
                        selectorName]
                );
            }
            return NO;
        }
    }
    return YES;
}

static NSArray *DCMakeModes(
    Class modeClass,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *modes
) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:modes.count];
    SEL initializer =
        NSSelectorFromString(@"initWithWidth:height:refreshRate:");
    typedef id (*InitializeMode)(
        id,
        SEL,
        uint32_t,
        uint32_t,
        double
    );
    InitializeMode initializeMode = (InitializeMode)objc_msgSend;

    for (NSDictionary<NSString *, NSNumber *> *mode in modes) {
        id value = initializeMode(
            [modeClass alloc],
            initializer,
            mode[@"width"].unsignedIntValue,
            mode[@"height"].unsignedIntValue,
            mode[@"refreshRate"].doubleValue
        );
        if (value != nil) {
            [result addObject:value];
        }
    }
    return result;
}

BOOL DCVirtualDisplayApplyModes(
    id display,
    BOOL hiDPI,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *modes,
    NSError **error
) {
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!DCRequireClassAndSelectors(
            settingsClass,
            @"CGVirtualDisplaySettings",
            @[@"init", @"setHiDPI:", @"setModes:"],
            error
        ) ||
        !DCRequireClassAndSelectors(
            modeClass,
            @"CGVirtualDisplayMode",
            @[@"initWithWidth:height:refreshRate:"],
            error
        )) {
        return NO;
    }

    id settings = [[settingsClass alloc] init];
    [settings setValue:@(hiDPI) forKey:@"hiDPI"];
    [settings setValue:DCMakeModes(modeClass, modes) forKey:@"modes"];

    SEL applySelector = NSSelectorFromString(@"applySettings:");
    typedef BOOL (*ApplySettings)(id, SEL, id);
    BOOL applied = ((ApplySettings)objc_msgSend)(
        display,
        applySelector,
        settings
    );
    if (!applied && error != NULL) {
        *error = DCError(
            DCVirtualDisplayErrorSettingsRejected,
            @"macOS rejected the virtual display settings."
        );
    }
    return applied;
}

id DCVirtualDisplayCreate(
    NSString *name,
    uint32_t maxPixelsWide,
    uint32_t maxPixelsHigh,
    CGSize sizeInMillimeters,
    uint32_t productID,
    uint32_t vendorID,
    uint32_t serialNumber,
    BOOL hiDPI,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *modes,
    NSError **error
) {
    Class descriptorClass =
        NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!DCRequireClassAndSelectors(
            descriptorClass,
            @"CGVirtualDisplayDescriptor",
            @[@"init", @"setDispatchQueue:"],
            error
        ) ||
        !DCRequireClassAndSelectors(
            displayClass,
            @"CGVirtualDisplay",
            @[@"initWithDescriptor:", @"applySettings:", @"displayID"],
            error
        )) {
        return nil;
    }

    id descriptor = [[descriptorClass alloc] init];
    [descriptor setValue:name forKey:@"name"];
    [descriptor setValue:@(maxPixelsWide) forKey:@"maxPixelsWide"];
    [descriptor setValue:@(maxPixelsHigh) forKey:@"maxPixelsHigh"];
    [descriptor setValue:
        [NSValue valueWithSize:NSSizeFromCGSize(sizeInMillimeters)]
        forKey:@"sizeInMillimeters"];
    [descriptor setValue:@(productID) forKey:@"productID"];
    [descriptor setValue:@(vendorID) forKey:@"vendorID"];
    [descriptor setValue:@(serialNumber) forKey:@"serialNum"];

    typedef void (*SetDispatchQueue)(id, SEL, dispatch_queue_t);
    ((SetDispatchQueue)objc_msgSend)(
        descriptor,
        NSSelectorFromString(@"setDispatchQueue:"),
        dispatch_get_main_queue()
    );

    typedef id (*InitializeDisplay)(id, SEL, id);
    id display = ((InitializeDisplay)objc_msgSend)(
        [displayClass alloc],
        NSSelectorFromString(@"initWithDescriptor:"),
        descriptor
    );
    if (display == nil) {
        if (error != NULL) {
            *error = DCError(
                DCVirtualDisplayErrorCreationFailed,
                @"macOS could not create the virtual display."
            );
        }
        return nil;
    }

    if (!DCVirtualDisplayApplyModes(
            display,
            hiDPI,
            modes,
            error
        )) {
        return nil;
    }
    return display;
}

CGDirectDisplayID DCVirtualDisplayGetDisplayID(id display) {
    typedef uint32_t (*GetDisplayID)(id, SEL);
    return ((GetDisplayID)objc_msgSend)(
        display,
        NSSelectorFromString(@"displayID")
    );
}
