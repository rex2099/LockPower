#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

static const char *kVersion = "0.2.0";
static const NSTimeInterval kDefaultDelaySeconds = 120.0;

typedef NS_ENUM(NSInteger, LockPowerStatusState) {
    LockPowerStatusStateFullPerformance,
    LockPowerStatusStatePending,
    LockPowerStatusStateLowPower,
    LockPowerStatusStatePaused,
    LockPowerStatusStateError,
};

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

@interface LockPowerWatcher : NSObject <NSMenuDelegate>
@property(nonatomic) NSTimeInterval delay;
@property(nonatomic) BOOL screenLocked;
@property(nonatomic) BOOL displayAsleep;
@property(nonatomic) BOOL enablePending;
@property(nonatomic) BOOL automationPaused;
@property(nonatomic) LockPowerStatusState statusState;
@property(nonatomic, strong) NSDate *scheduledEnableDate;
@property(nonatomic, copy) NSString *lastEvent;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *statusMenuItem;
@property(nonatomic, strong) NSMenuItem *detailMenuItem;
@property(nonatomic, strong) NSMenuItem *pauseMenuItem;
@property(nonatomic, strong) NSMenuItem *enableMenuItem;
@property(nonatomic, strong) NSMenuItem *disableMenuItem;
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
    self.automationPaused = NO;
    self.statusState = LockPowerStatusStateFullPerformance;
    [self setUpStatusItem];

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

- (void)setUpStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar
                       statusItemWithLength:NSSquareStatusItemLength];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"LockPower"];
    menu.delegate = self;

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"LockPower"
                                                     action:nil
                                              keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];

    self.detailMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                     action:nil
                                              keyEquivalent:@""];
    self.detailMenuItem.enabled = NO;
    [menu addItem:self.detailMenuItem];
    [menu addItem:NSMenuItem.separatorItem];

    self.enableMenuItem = [[NSMenuItem alloc]
                           initWithTitle:@"Enable Low Power Mode Now"
                                  action:@selector(enableLowPowerNow:)
                           keyEquivalent:@""];
    self.enableMenuItem.target = self;
    [menu addItem:self.enableMenuItem];

    self.disableMenuItem = [[NSMenuItem alloc]
                            initWithTitle:@"Restore Full Performance Now"
                                   action:@selector(restoreFullPerformanceNow:)
                            keyEquivalent:@""];
    self.disableMenuItem.target = self;
    [menu addItem:self.disableMenuItem];
    [menu addItem:NSMenuItem.separatorItem];

    self.pauseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Pause Automation"
                                                    action:@selector(toggleAutomationPaused:)
                                             keyEquivalent:@""];
    self.pauseMenuItem.target = self;
    [menu addItem:self.pauseMenuItem];

    NSMenuItem *showLogItem = [[NSMenuItem alloc] initWithTitle:@"Show Log in Finder"
                                                         action:@selector(showLogInFinder:)
                                                  keyEquivalent:@""];
    showLogItem.target = self;
    [menu addItem:showLogItem];

    NSMenuItem *projectItem = [[NSMenuItem alloc] initWithTitle:@"Open LockPower on GitHub"
                                                         action:@selector(openProjectPage:)
                                                  keyEquivalent:@""];
    projectItem.target = self;
    [menu addItem:projectItem];

    self.statusItem.menu = menu;
    [self updateStatusItem];

    if (self.statusItem != nil && self.statusItem.button != nil) {
        LogMessage(@"Status item ready; symbol=%@", [self symbolName]);
    } else {
        LogMessage(@"Status item unavailable");
    }
}

- (NSString *)statusTitle {
    switch (self.statusState) {
        case LockPowerStatusStatePending:
            return @"Waiting to enable Low Power Mode";
        case LockPowerStatusStateLowPower:
            return @"Low Power Mode is on";
        case LockPowerStatusStatePaused:
            return @"Automation is paused";
        case LockPowerStatusStateError:
            return @"Power mode switch failed";
        case LockPowerStatusStateFullPerformance:
        default:
            return @"Full performance mode";
    }
}

- (NSString *)symbolName {
    switch (self.statusState) {
        case LockPowerStatusStatePending:
            return @"clock";
        case LockPowerStatusStateLowPower:
            return @"leaf.fill";
        case LockPowerStatusStatePaused:
            return @"pause.fill";
        case LockPowerStatusStateError:
            return @"exclamationmark.triangle.fill";
        case LockPowerStatusStateFullPerformance:
        default:
            return @"bolt.fill";
    }
}

- (void)updateStatusItem {
    NSString *title = [self statusTitle];
    NSImage *image = [NSImage imageWithSystemSymbolName:[self symbolName]
                               accessibilityDescription:title];
    if (image != nil) {
        image.template = YES;
        self.statusItem.button.image = image;
        self.statusItem.button.title = @"";
    } else {
        self.statusItem.button.image = nil;
        self.statusItem.button.title = @"LP";
    }
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"LockPower — %@", title];
}

- (void)setStatusState:(LockPowerStatusState)state detail:(NSString *)detail {
    _statusState = state;
    if (detail.length > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = NSLocale.currentLocale;
        formatter.timeStyle = NSDateFormatterMediumStyle;
        formatter.dateStyle = NSDateFormatterNoStyle;
        self.lastEvent = [NSString stringWithFormat:@"%@ · %@",
                          detail,
                          [formatter stringFromDate:[NSDate date]]];
    }
    [self updateStatusItem];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    self.statusMenuItem.title = [self statusTitle];

    if (self.statusState == LockPowerStatusStatePending && self.scheduledEnableDate != nil) {
        NSInteger remaining = MAX(0, (NSInteger)ceil([self.scheduledEnableDate timeIntervalSinceNow]));
        self.detailMenuItem.title = [NSString stringWithFormat:@"Low Power Mode in %ld seconds",
                                     (long)remaining];
    } else if (self.lastEvent.length > 0) {
        self.detailMenuItem.title = self.lastEvent;
    } else {
        self.detailMenuItem.title = [NSString stringWithFormat:@"Delay: %.0f seconds", self.delay];
    }

    BOOL lowPowerEnabled = NSProcessInfo.processInfo.lowPowerModeEnabled;
    self.enableMenuItem.enabled = !lowPowerEnabled && !self.automationPaused;
    self.disableMenuItem.enabled = lowPowerEnabled;
    self.pauseMenuItem.title = self.automationPaused ? @"Resume Automation" : @"Pause Automation";
}

- (void)cancelPendingEnable {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(enableLowPowerIfStillAway)
                                               object:nil];
    self.enablePending = NO;
    self.scheduledEnableDate = nil;
}

- (void)enableLowPowerNow:(id)sender {
    (void)sender;
    [self cancelPendingEnable];
    [self setLowPowerMode:YES reason:@"manual menu action"];
}

- (void)restoreFullPerformanceNow:(id)sender {
    (void)sender;
    [self cancelPendingEnable];
    [self setLowPowerMode:NO reason:@"manual menu action"];
}

- (void)toggleAutomationPaused:(id)sender {
    (void)sender;
    self.automationPaused = !self.automationPaused;
    if (self.automationPaused) {
        [self cancelPendingEnable];
        LogMessage(@"Automation paused from the menu");
        [self setLowPowerMode:NO reason:@"automation paused"];
        [self setStatusState:LockPowerStatusStatePaused detail:@"Automation paused"];
    } else {
        LogMessage(@"Automation resumed from the menu");
        [self reevaluate];
    }
}

- (void)showLogInFinder:(id)sender {
    (void)sender;
    NSString *path = [@"~/Library/Logs/LockPower.log" stringByExpandingTildeInPath];
    NSURL *url = [NSURL fileURLWithPath:path];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
}

- (void)openProjectPage:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://github.com/rex2099/LockPower"];
    [NSWorkspace.sharedWorkspace openURL:url];
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
    if (self.automationPaused) {
        [self setStatusState:LockPowerStatusStatePaused detail:nil];
        return;
    }

    BOOL away = self.screenLocked || self.displayAsleep;
    if (away) {
        if (self.enablePending) {
            return;
        }
        if (NSProcessInfo.processInfo.lowPowerModeEnabled) {
            [self setStatusState:LockPowerStatusStateLowPower detail:nil];
            return;
        }

        self.enablePending = YES;
        self.scheduledEnableDate = [NSDate dateWithTimeIntervalSinceNow:self.delay];
        [self setStatusState:LockPowerStatusStatePending detail:@"Away state detected"];
        LogMessage(@"Away state detected; Low Power Mode will turn on in %.0f seconds",
                   self.delay);
        [self performSelector:@selector(enableLowPowerIfStillAway)
                   withObject:nil
                   afterDelay:self.delay];
        return;
    }

    [self cancelPendingEnable];
    [self setLowPowerMode:NO reason:@"local session active"];
}

- (void)enableLowPowerIfStillAway {
    self.enablePending = NO;
    self.scheduledEnableDate = nil;
    if (self.screenLocked || self.displayAsleep) {
        [self setLowPowerMode:YES reason:@"screen locked or display asleep"];
    }
}

- (void)setLowPowerMode:(BOOL)enabled reason:(NSString *)reason {
    if (NSProcessInfo.processInfo.lowPowerModeEnabled == enabled) {
        LogMessage(@"Low Power Mode already %@ (%@)", enabled ? @"on" : @"off", reason);
        [self setStatusState:(enabled ? LockPowerStatusStateLowPower
                                      : LockPowerStatusStateFullPerformance)
                      detail:reason];
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
        [self setStatusState:LockPowerStatusStateError detail:@"Unable to run pmset"];
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
        [self setStatusState:(enabled ? LockPowerStatusStateLowPower
                                      : LockPowerStatusStateFullPerformance)
                      detail:(enabled ? @"Low Power Mode enabled"
                                      : @"Full performance restored")];
    } else {
        LogMessage(@"pmset failed with status %d: %@",
                   task.terminationStatus,
                   errorText.length > 0 ? errorText : @"unknown error");
        [self setStatusState:LockPowerStatusStateError detail:@"pmset command failed"];
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

        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        LockPowerWatcher *watcher = [[LockPowerWatcher alloc]
                                     initWithDelay:ConfiguredDelay()];
        (void)watcher;
        [application run];
    }
    return 0;
}
