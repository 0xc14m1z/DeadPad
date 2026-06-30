#import <Cocoa/Cocoa.h>

@interface DeadPadAppDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, strong) NSButton *restartButton;
@property(nonatomic, strong) NSButton *startAtLoginCheckbox;
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
    [self buildStatusItem];
    [self updateAppStateWithStatus:@"Stopped"];
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

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"DP";
    self.statusItem.button.toolTip = @"DeadPad";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(showWindow:);
}

- (void)buildWindow {
    if (self.window) {
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 360, 238);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"DeadPad";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;

    NSTextField *titleLabel = [self labelWithFrame:NSMakeRect(22, 190, 250, 24)
                                            string:@"DeadPad"
                                          fontSize:18
                                              bold:YES];
    [content addSubview:titleLabel];

    self.statusLabel = [self labelWithFrame:NSMakeRect(22, 166, 300, 20)
                                     string:@"Status: Stopped"
                                   fontSize:13
                                       bold:NO];
    [content addSubview:self.statusLabel];

    self.startAtLoginCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 130, 220, 24)];
    self.startAtLoginCheckbox.buttonType = NSButtonTypeSwitch;
    self.startAtLoginCheckbox.title = @"Start at login";
    self.startAtLoginCheckbox.target = self;
    self.startAtLoginCheckbox.action = @selector(toggleStartAtLogin:);
    [content addSubview:self.startAtLoginCheckbox];

    self.startButton = [self buttonWithFrame:NSMakeRect(22, 86, 92, 30)
                                       title:@"Start"
                                      action:@selector(startFilter:)];
    [content addSubview:self.startButton];

    self.stopButton = [self buttonWithFrame:NSMakeRect(128, 86, 92, 30)
                                      title:@"Stop"
                                     action:@selector(stopFilter:)];
    [content addSubview:self.stopButton];

    self.restartButton = [self buttonWithFrame:NSMakeRect(234, 86, 104, 30)
                                         title:@"Restart"
                                        action:@selector(restartFilter:)];
    [content addSubview:self.restartButton];

    NSButton *accessibilityButton = [self buttonWithFrame:NSMakeRect(22, 42, 154, 30)
                                                    title:@"Accessibility"
                                                   action:@selector(openAccessibilitySettings:)];
    [content addSubview:accessibilityButton];

    NSButton *logButton = [self buttonWithFrame:NSMakeRect(190, 42, 70, 30)
                                          title:@"Log"
                                         action:@selector(openLog:)];
    [content addSubview:logButton];

    NSButton *quitButton = [self buttonWithFrame:NSMakeRect(274, 42, 64, 30)
                                           title:@"Quit"
                                          action:@selector(quitApp:)];
    [content addSubview:quitButton];

    [self refreshStartAtLoginCheckbox];
}

- (NSTextField *)labelWithFrame:(NSRect)frame
                         string:(NSString *)string
                       fontSize:(CGFloat)fontSize
                           bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = string;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = bold ? [NSFont boldSystemFontOfSize:fontSize] : [NSFont systemFontOfSize:fontSize];
    return label;
}

- (NSButton *)buttonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (void)showWindow:(id)sender {
    (void)sender;

    [self buildWindow];
    [self refreshStartAtLoginCheckbox];
    [self updateAppStateWithStatus:[self isFilterRunning] ? @"Running" : @"Stopped"];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (NSString *)launchAgentPath {
    NSString *agentsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    return [agentsDir stringByAppendingPathComponent:@"com.local.deadpad.app.plist"];
}

- (BOOL)isStartAtLoginEnabled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPath]];
}

- (BOOL)setStartAtLoginEnabled:(BOOL)enabled error:(NSError **)error {
    NSString *path = [self launchAgentPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (!enabled) {
        if (![fileManager fileExistsAtPath:path]) {
            return YES;
        }
        return [fileManager removeItemAtPath:path error:error];
    }

    NSString *agentsDir = [path stringByDeletingLastPathComponent];
    if (![fileManager createDirectoryAtPath:agentsDir
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:error]) {
        return NO;
    }

    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    NSDictionary *plist = @{
        @"Label": @"com.local.deadpad.app",
        @"ProgramArguments": @[@"/usr/bin/open", bundlePath],
        @"RunAtLoad": @YES
    };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data) {
        return NO;
    }

    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (void)refreshStartAtLoginCheckbox {
    self.startAtLoginCheckbox.state =
        [self isStartAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleStartAtLogin:(id)sender {
    (void)sender;

    BOOL enabled = self.startAtLoginCheckbox.state == NSControlStateValueOn;
    NSError *error = nil;
    if (![self setStartAtLoginEnabled:enabled error:&error]) {
        [self refreshStartAtLoginCheckbox];
        NSString *detail = error.localizedDescription ? error.localizedDescription : @"Unknown error";
        [self showErrorWithTitle:@"Could not update login setting" detail:detail];
    }
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
        [self updateAppStateWithStatus:@"Helper missing"];
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
                [strongSelf updateAppStateWithStatus:[NSString stringWithFormat:@"Stopped (%d)", status]];
            }
        });
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self.logHandle closeFile];
        self.logHandle = nil;
        [self updateAppStateWithStatus:@"Launch failed"];
        NSString *detail = error.localizedDescription ? error.localizedDescription : @"Unknown launch error";
        [self showErrorWithTitle:@"Could not start DeadPad" detail:detail];
        return;
    }

    self.task = task;
    [self appendLogLine:@"DeadPad app started helper."];
    [self updateAppStateWithStatus:@"Running"];
}

- (void)stopFilter:(id)sender {
    (void)sender;

    if (![self isFilterRunning]) {
        return;
    }

    [self appendLogLine:@"DeadPad app stopping helper."];
    [self.task terminate];
    [self updateAppStateWithStatus:@"Stopping"];
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

- (void)quitApp:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
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

- (void)updateAppStateWithStatus:(NSString *)status {
    BOOL running = [self isFilterRunning];

    self.statusLabel.stringValue = [NSString stringWithFormat:@"Status: %@", status];
    self.startButton.enabled = !running;
    self.stopButton.enabled = running;
    self.restartButton.enabled = running;
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
