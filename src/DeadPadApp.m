#import <Cocoa/Cocoa.h>

@interface DeadPadAppDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *statusMenuItem;
@property(nonatomic, strong) NSMenuItem *startMenuItem;
@property(nonatomic, strong) NSMenuItem *stopMenuItem;
@property(nonatomic, strong) NSMenuItem *restartMenuItem;
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSFileHandle *logHandle;
@property(nonatomic, copy) NSString *logPath;
@property(nonatomic, assign) BOOL restartAfterStop;

@end

@implementation DeadPadAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self prepareLogPath];
    [self buildStatusMenu];
    [self updateMenuStateWithStatus:@"Stopped"];
    [self startFilter:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    self.restartAfterStop = NO;
    [self stopFilter:nil];
}

- (void)prepareLogPath {
    NSString *logsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DeadPad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.logPath = [logsDir stringByAppendingPathComponent:@"deadpad.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.logPath]) {
        [[NSData data] writeToFile:self.logPath atomically:YES];
    }
}

- (void)buildStatusMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"DP";
    self.statusItem.button.toolTip = @"DeadPad";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"DeadPad"];

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"DeadPad: Stopped"
                                                     action:nil
                                              keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];

    self.startMenuItem = [[NSMenuItem alloc] initWithTitle:@"Start Filter"
                                                    action:@selector(startFilter:)
                                             keyEquivalent:@""];
    self.startMenuItem.target = self;
    [menu addItem:self.startMenuItem];

    self.stopMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stop Filter"
                                                   action:@selector(stopFilter:)
                                            keyEquivalent:@""];
    self.stopMenuItem.target = self;
    [menu addItem:self.stopMenuItem];

    self.restartMenuItem = [[NSMenuItem alloc] initWithTitle:@"Restart Filter"
                                                      action:@selector(restartFilter:)
                                               keyEquivalent:@""];
    self.restartMenuItem.target = self;
    [menu addItem:self.restartMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *accessibilityItem =
        [[NSMenuItem alloc] initWithTitle:@"Open Accessibility Settings"
                                   action:@selector(openAccessibilitySettings:)
                            keyEquivalent:@""];
    accessibilityItem.target = self;
    [menu addItem:accessibilityItem];

    NSMenuItem *logItem = [[NSMenuItem alloc] initWithTitle:@"Open Log"
                                                     action:@selector(openLog:)
                                              keyEquivalent:@""];
    logItem.target = self;
    [menu addItem:logItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit DeadPad"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (BOOL)isFilterRunning {
    return self.task != nil && self.task.isRunning;
}

- (NSString *)helperPath {
    NSString *bundledPath = [[NSBundle mainBundle] pathForResource:@"deadpad" ofType:nil];
    if (bundledPath.length > 0) {
        return bundledPath;
    }

    NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    return [currentDir stringByAppendingPathComponent:@"deadpad"];
}

- (void)appendLogLine:(NSString *)line {
    NSString *stamp = [[NSDate date] descriptionWithLocale:nil];
    NSString *entry = [NSString stringWithFormat:@"\n[%@] %@\n", stamp, line];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (NSFileHandle *)openLogHandle {
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
    [handle seekToEndOfFile];
    return handle;
}

- (NSArray<NSString *> *)deadPadArguments {
    return @[
        @"--left-cm", @"2",
        @"--right-cm", @"2",
        @"--policy", @"all",
        @"--verbose"
    ];
}

- (void)startFilter:(id)sender {
    (void)sender;

    if ([self isFilterRunning]) {
        return;
    }

    NSString *helperPath = [self helperPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
        [self updateMenuStateWithStatus:@"Helper missing"];
        [self showErrorWithTitle:@"DeadPad helper not found"
                          detail:[NSString stringWithFormat:@"Expected executable helper at:\n%@", helperPath]];
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:helperPath];
    task.arguments = [self deadPadArguments];
    task.currentDirectoryURL = [NSURL fileURLWithPath:[helperPath stringByDeletingLastPathComponent]];

    self.logHandle = [self openLogHandle];
    task.standardOutput = self.logHandle;
    task.standardError = self.logHandle;

    __weak DeadPadAppDelegate *weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DeadPadAppDelegate *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.task != finishedTask) {
                return;
            }

            int status = finishedTask.terminationStatus;
            [strongSelf.logHandle closeFile];
            strongSelf.logHandle = nil;
            strongSelf.task = nil;

            if (strongSelf.restartAfterStop) {
                strongSelf.restartAfterStop = NO;
                [strongSelf startFilter:nil];
            } else {
                [strongSelf updateMenuStateWithStatus:[NSString stringWithFormat:@"Stopped (%d)", status]];
            }
        });
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self.logHandle closeFile];
        self.logHandle = nil;
        [self updateMenuStateWithStatus:@"Launch failed"];
        NSString *detail = error.localizedDescription ? error.localizedDescription : @"Unknown launch error";
        [self showErrorWithTitle:@"Could not start DeadPad" detail:detail];
        return;
    }

    self.task = task;
    [self appendLogLine:@"DeadPad app started helper."];
    [self updateMenuStateWithStatus:@"Running"];
}

- (void)stopFilter:(id)sender {
    (void)sender;

    if (![self isFilterRunning]) {
        return;
    }

    [self appendLogLine:@"DeadPad app stopping helper."];
    [self.task terminate];
    [self updateMenuStateWithStatus:@"Stopping"];
}

- (void)restartFilter:(id)sender {
    (void)sender;

    if ([self isFilterRunning]) {
        self.restartAfterStop = YES;
        [self stopFilter:nil];
    } else {
        [self startFilter:nil];
    }
}

- (void)openAccessibilitySettings:(id)sender {
    (void)sender;

    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openLog:(id)sender {
    (void)sender;

    if (self.logPath.length > 0) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.logPath]];
    }
}

- (void)updateMenuStateWithStatus:(NSString *)status {
    BOOL running = [self isFilterRunning];

    self.statusMenuItem.title = [NSString stringWithFormat:@"DeadPad: %@", status];
    self.startMenuItem.enabled = !running;
    self.stopMenuItem.enabled = running;
    self.restartMenuItem.enabled = running;
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"DeadPad: %@", status];
}

- (void)showErrorWithTitle:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        DeadPadAppDelegate *delegate = [[DeadPadAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }

    return 0;
}
