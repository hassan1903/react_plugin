// SpeedCheckerPlugin.m

#import "SpeedCheckerPlugin.h"
#import <React/RCTEventDispatcherProtocol.h>
@import SpeedcheckerSDK;
@import CoreLocation;

@interface SpeedCheckerPlugin () <InternetSpeedTestDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) InternetSpeedTest *internetTest;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) SpeedTestServer *server;
@property (nonatomic, strong) NSMutableDictionary *resultDict;
@end

@implementation SpeedCheckerPlugin

#pragma mark - Init
- (instancetype)init {
    self = [super init];
    if (self) {
        self.locationManager = [CLLocationManager new];
        self.resultDict = [NSMutableDictionary new];
        // [self requestLocation];
    }
    return self;
}

#pragma mark - RCTEventEmitter supported events
- (NSArray<NSString *> *)supportedEvents {
    return @[@"onTestStarted"];
}

#pragma mark - Queue
+ (BOOL)requiresMainQueueSetup {
    return YES;
}

#pragma mark - Exports

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(startTest) {
    [self resetServer];
    // [self checkPermissionsAndStartTest];
    [self startSpeedTest];
}

RCT_EXPORT_METHOD(stopTest) {
    [self.internetTest forceFinish:^(enum SpeedTestError error) {
    }];
}

#pragma mark - Helpers
- (void)sendErrorResult:(SpeedTestError)error {
    NSDictionary *dict = @{@"error": [self descriptionForError:error]};
    
    [self sendEventWithName:@"onTestStarted" body:dict];
}

- (void)sendResultDict {
    NSDictionary *dict = [self.resultDict copy];
    
    [self sendEventWithName:@"onTestStarted" body:dict];
}

- (void)resetServer {
    self.server = nil;
}

- (void)checkPermissionsAndStartTest {
    SCLocationHelper *locationHelper = [[SCLocationHelper alloc] init];
    [locationHelper locationServicesEnabled:^(BOOL locationEnabled) {
        if (!locationEnabled) {
            [self sendErrorResult:SpeedTestErrorLocationUndefined];
            return;
        }

        [self startSpeedTest];
    }];
}

- (void)startSpeedTest {
    self.internetTest = [[InternetSpeedTest alloc] initWithLicenseKey:@"59dd8ef5a824efccf31af0c00e27bec166cfbfdfa33cd3286f42aa0339d9b392" delegate:self];
    [self.internetTest start:^(enum SpeedTestError error) {
        if (error != SpeedTestErrorOk) {
            [self sendErrorResult:error];
            [self resetServer];
        } else {
            self.resultDict = [@{
                @"status": @"Speed test started",
                @"server": @"",
                @"ping": @0,
                @"jitter": @0,
                @"downloadSpeed": @0,
                @"percent": @0,
                @"currentSpeed": @0,
                @"uploadSpeed": @0,
                @"connectionType": @"",
                @"serverInfo": @"",
                @"deviceInfo": @"",
                @"downloadTransferredMb": @0,
                @"uploadTransferredMb": @0
            } mutableCopy];
            [self sendResultDict];
        }
    }];
}

- (void)requestLocation {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if ([CLLocationManager locationServicesEnabled]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.locationManager.delegate = self;
                [self.locationManager requestWhenInUseAuthorization];
                [self.locationManager requestAlwaysAuthorization];
            });
        }
    });
}

- (NSString*)descriptionForError:(SpeedTestError)error {
    switch (error) {
        case SpeedTestErrorOk:
            return @"Ok";
        case SpeedTestErrorInvalidSettings:
            return @"Invalid settings";
        case SpeedTestErrorInvalidServers:
            return @"Invalid servers";
        case SpeedTestErrorInProgress:
            return @"In progress";
        case SpeedTestErrorFailed:
            return @"Failed";
        case SpeedTestErrorNotSaved:
            return @"Not saved";
        case SpeedTestErrorCancelled:
            return @"Cancelled";
        case SpeedTestErrorLocationUndefined:
            return @"Location undefined";
        default:
            return @"Unknown";
    }
}

- (NSString*)serverInfo:(SpeedTestResult*)result {
    NSString *cityName = result.server.cityName ?: @"";
    NSString *country = result.server.country ?: @"";
    NSString *serverInfo = [NSString stringWithFormat:@"%@, %@", cityName, country];
    if ([cityName isEqualToString:@""] || [country isEqualToString:@""]) {
        serverInfo = [serverInfo stringByReplacingOccurrencesOfString:@", " withString:@""];
    }
    return serverInfo;
}

- (id)objectOrNull:(id)object {
  return object ?: [NSNull null];
}

- (id)objectOrNil:(id)object {
    return [object isEqual:[NSNull null]] ? nil : object;
}

#pragma mark - InternetSpeedTestDelegate

- (void)internetTestErrorWithError:(enum SpeedTestError)error {
    [self sendErrorResult:error];
    [self resetServer];
}

- (void)internetTestFinishWithResult:(SpeedTestResult *)result {
    self.resultDict[@"status"] = @"Speed test finished";
    self.resultDict[@"server"] = [self objectOrNull:result.server.domain];
    self.resultDict[@"ping"] = [NSNumber numberWithInteger:result.latencyInMs];
    self.resultDict[@"jitter"] = [NSNumber numberWithDouble:result.jitter];
    self.resultDict[@"downloadSpeed"] = [NSNumber numberWithDouble:result.downloadSpeed.mbps];
    self.resultDict[@"uploadSpeed"] = [NSNumber numberWithDouble:result.uploadSpeed.mbps];
    self.resultDict[@"connectionType"] = [self objectOrNull:result.connectionType];
    self.resultDict[@"serverInfo"] = [self objectOrNull:[self serverInfo:result]];
    self.resultDict[@"deviceInfo"] = [self objectOrNull:result.deviceInfo];
    self.resultDict[@"downloadTransferredMb"] = [NSNumber numberWithDouble:result.downloadTransferredMb];
    self.resultDict[@"uploadTransferredMb"] = [NSNumber numberWithDouble:result.uploadTransferredMb];
    [self sendResultDict];
    [self resetServer];
}

- (void)internetTestReceivedWithServers:(NSArray<SpeedTestServer *> *)servers {
    self.resultDict[@"status"] = @"Ping";
    [self sendResultDict];
}

- (void)internetTestSelectedWithServer:(SpeedTestServer *)server latency:(NSInteger)latency jitter:(NSInteger)jitter {
    self.resultDict[@"ping"] = [NSNumber numberWithInteger:latency];
    self.resultDict[@"server"] = [self objectOrNull:server.domain];
    self.resultDict[@"jitter"] = [NSNumber numberWithInteger:jitter];
    [self sendResultDict];
}

- (void)internetTestDownloadStart {
    self.resultDict[@"status"] = @"Download Test";
    [self sendResultDict];
}

- (void)internetTestDownloadFinish {
}

- (void)internetTestDownloadWithProgress:(double)progress speed:(SpeedTestSpeed *)speed {
    self.resultDict[@"status"] = @"Download Test";
    self.resultDict[@"percent"] = [NSNumber numberWithDouble:progress * 100];
    self.resultDict[@"currentSpeed"] = [NSNumber numberWithDouble:speed.mbps];
    self.resultDict[@"downloadSpeed"] = [NSNumber numberWithDouble:speed.mbps];
    [self sendResultDict];
}

- (void)internetTestUploadStart {
    self.resultDict[@"status"] = @"Upload Test";
    self.resultDict[@"currentSpeed"] = @0;
    self.resultDict[@"percent"] = @0;
    [self sendResultDict];
}

- (void)internetTestUploadFinish {
}

- (void)internetTestUploadWithProgress:(double)progress speed:(SpeedTestSpeed *)speed {
    self.resultDict[@"percent"] = [NSNumber numberWithDouble:progress * 100];
    self.resultDict[@"currentSpeed"] = [NSNumber numberWithDouble:speed.mbps];
    self.resultDict[@"uploadSpeed"] = [NSNumber numberWithDouble:speed.mbps];
    [self sendResultDict];
}

@end
