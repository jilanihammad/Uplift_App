#import "RnnoiseFlutterPlugin.h"

@implementation RnnoiseFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"rnnoise_flutter"
            binaryMessenger:[registrar messenger]];
  RnnoiseFlutterPlugin* instance = [[RnnoiseFlutterPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if ([@"processFrame" isEqualToString:call.method]) {
    // Stub implementation for iOS
    // RNNoise is not implemented on iOS, return no processing
    NSDictionary *args = call.arguments;
    NSArray *samples = args[@"samples"];

    // Return the samples unchanged and a default VAD probability
    result(@{
      @"processedSamples": samples,
      @"vadProbability": @(0.5)  // Default middle value
    });
  } else if ([@"init" isEqualToString:call.method]) {
    // Stub init - always succeed
    result(@(YES));
  } else if ([@"destroy" isEqualToString:call.method]) {
    // Stub destroy
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
