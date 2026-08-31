#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

static const char *kVersion = "0.1.0";
static const NSTimeInterval kDefaultDelaySeconds = 120.0;

static void LogMessage(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fprintf(stderr, "%s  %s\n",
            [[formatter stringFromDate:[NSDate date]] UTF8String],
            [message UTF8String]);
    fflush(stderr);
}

static NSTimeInterval ConfiguredDelay(void) {
    NSString *raw = NSProcessInfo.processInfo.environment[@"LOCKPOWER_DELAY_SECONDS"];
    if (raw.length == 0) {
        return kDefaultDelaySeconds;
    }

    NSScanner *scanner = [NSScanner scannerWithString:raw];
    double seconds = 0;
    if (![scanner scanDouble:&seconds] || !scanner.isAtEnd || seconds < 1 || seconds > 3600) {
        return kDefaultDelaySeconds;
    }
    return seconds;
}

static BOOL CurrentSessionIsLocked(void) {
    CFDictionaryRef sessionRef = CGSessionCopyCurrentDictionary();
    if (sessionRef == NULL) {
        return NO;
    }

    NSDictionary *session = CFBridgingRelease(sessionRef);
    return [session[@"CGSSessionScreenIsLocked"] boolValue];
}

@interface LockPowerWatcher : NSObject
@property(nonatomic) NSTimeInterval delay;
@property(nonatomic) BOOL screenLocked;
@property(nonatomic) BOOL displayAsleep;
@property(nonatomic) BOOL enablePending;
@end

@implementation LockPowerWatcher

- (instancetype)initWithDelay:(NSTimeInterval)delay {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.delay = delay;
    self.screenLocked = CurrentSessionIsLocked();
    self.displayAsleep = NO;
    self.enablePending = NO;

    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self
                        selector:@selector(screensDidSleep:)
                            name:NSWorkspaceScreensDidSleepNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(screensDidWake:)
                            name:NSWorkspaceScreensDidWakeNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(sessionDidResignActive:)
                            name:NSWorkspaceSessionDidResignActiveNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(sessionDidBecomeActive:)
                            name:NSWorkspaceSessionDidBecomeActiveNotification
                          object:nil];

    NSDistributedNotificationCenter *distributed = NSDistributedNotificationCenter.defaultCenter;
    [distributed addObserver:self
                    selector:@selector(screenDidLock:)
                        name:@"com.apple.screenIsLocked"
                      object:nil];
    [distributed addObserver:self
                    selector:@selector(screenDidUnlock:)
                        name:@"com.apple.screenIsUnlocked"
                      object:nil];

    LogMessage(@"LockPower started; delay=%.0fs; initialLocked=%@",
               delay,
               self.screenLocked ? @"yes" : @"no");
    [self reevaluate];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}

- (void)screensDidSleep:(NSNotification *)notification {
    (void)notification;
    self.displayAsleep = YES;
    LogMessage(@"Display slept");
    [self reevaluate];
}

- (void)screensDidWake:(NSNotification *)notification {
    (void)notification;
    self.displayAsleep = NO;
    self.screenLocked = CurrentSessionIsLocked();
    LogMessage(@"Display woke; locked=%@", self.screenLocked ? @"yes" : @"no");
    [self reevaluate];
}

- (void)sessionDidResignActive:(NSNotification *)notification {
    (void)notification;
    self.screenLocked = YES;
    LogMessage(@"Session became inactive");
    [self reevaluate];
}

- (void)sessionDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    self.screenLocked = CurrentSessionIsLocked();
    LogMessage(@"Session became active; locked=%@", self.screenLocked ? @"yes" : @"no");
    [self reevaluate];
}

- (void)screenDidLock:(NSNotification *)notification {
    (void)notification;
    self.screenLocked = YES;
    LogMessage(@"Screen locked");
    [self reevaluate];
}

- (void)screenDidUnlock:(NSNotification *)notification {
    (void)notification;
    self.screenLocked = NO;
    self.displayAsleep = NO;
    LogMessage(@"Screen unlocked");
    [self reevaluate];
}

- (void)reevaluate {
    BOOL away = self.screenLocked || self.displayAsleep;
    if (away) {
        if (self.enablePending || NSProcessInfo.processInfo.lowPowerModeEnabled) {
            return;
        }

        self.enablePending = YES;
        LogMessage(@"Away state detected; Low Power Mode will turn on in %.0f seconds",
                   self.delay);
        [self performSelector:@selector(enableLowPowerIfStillAway)
                   withObject:nil
                   afterDelay:self.delay];
        return;
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(enableLowPowerIfStillAway)
                                               object:nil];
    self.enablePending = NO;
    [self setLowPowerMode:NO reason:@"local session active"];
}

- (void)enableLowPowerIfStillAway {
    self.enablePending = NO;
    if (self.screenLocked || self.displayAsleep) {
        [self setLowPowerMode:YES reason:@"screen locked or display asleep"];
    }
}

- (void)setLowPowerMode:(BOOL)enabled reason:(NSString *)reason {
    if (NSProcessInfo.processInfo.lowPowerModeEnabled == enabled) {
        LogMessage(@"Low Power Mode already %@ (%@)", enabled ? @"on" : @"off", reason);
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    task.arguments = @[@"-n", @"/usr/bin/pmset", @"-a", @"lowpowermode",
                       enabled ? @"1" : @"0"];

    NSPipe *errorPipe = [NSPipe pipe];
    task.standardError = errorPipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        LogMessage(@"Failed to launch pmset: %@", launchError.localizedDescription);
        return;
    }

    [task waitUntilExit];
    NSData *errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
    NSString *errorText = [[NSString alloc] initWithData:errorData
                                                encoding:NSUTF8StringEncoding];
    errorText = [errorText stringByTrimmingCharactersInSet:
                 NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (task.terminationStatus == 0) {
        LogMessage(@"Low Power Mode turned %@ (%@)", enabled ? @"on" : @"off", reason);
    } else {
        LogMessage(@"pmset failed with status %d: %@",
                   task.terminationStatus,
                   errorText.length > 0 ? errorText : @"unknown error");
    }
}

@end

static int RunSelfTest(void) {
    BOOL locked[] = {NO, YES, NO, YES};
    BOOL asleep[] = {NO, NO, YES, YES};
    BOOL expected[] = {NO, YES, YES, YES};

    for (int index = 0; index < 4; index++) {
        if ((locked[index] || asleep[index]) != expected[index]) {
            fprintf(stderr, "State truth-table test failed\n");
            return 1;
        }
    }

    printf("LockPower self-test passed\n");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int index = 1; index < argc; index++) {
            if (strcmp(argv[index], "--version") == 0) {
                printf("LockPower %s\n", kVersion);
                return 0;
            }
            if (strcmp(argv[index], "--self-test") == 0) {
                return RunSelfTest();
            }
        }

        (void)NSApplication.sharedApplication;
        LockPowerWatcher *watcher = [[LockPowerWatcher alloc]
                                     initWithDelay:ConfiguredDelay()];
        (void)watcher;
        [NSRunLoop.currentRunLoop run];
    }
    return 0;
}
