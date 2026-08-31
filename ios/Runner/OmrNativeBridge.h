#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Native OMR + OpenCV pipeline for iOS (parity with Android `OmrProcessor` / MethodChannel `opencv`).
@interface OmrNativeBridge : NSObject

+ (BOOL)isOpenCvReady;

+ (nullable NSString *)processWithImageBytes:(NSData *)data
                              totalQuestions:(NSInteger)totalQuestions
                               sessionLayout:(nullable NSDictionary<NSString *, id> *)sessionLayout;

/// Same as Android `process` → JSON string.
+ (nullable NSString *)processImageBytesLegacy:(NSData *)data;

+ (nullable NSDictionary<NSString *, id> *)detectSheet:(NSData *)data;

+ (nullable NSDictionary<NSString *, NSNumber *> *)analyzeImageQuality:(NSData *)data;

+ (NSDictionary<NSString *, id> *)deviceInfo;

@end

NS_ASSUME_NONNULL_END
