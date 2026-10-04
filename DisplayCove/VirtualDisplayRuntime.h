#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT id _Nullable DCVirtualDisplayCreate(
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
);

FOUNDATION_EXPORT BOOL DCVirtualDisplayApplyModes(
    id display,
    BOOL hiDPI,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *modes,
    NSError **error
);

FOUNDATION_EXPORT CGDirectDisplayID DCVirtualDisplayGetDisplayID(id display);

NS_ASSUME_NONNULL_END
