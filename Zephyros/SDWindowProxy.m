//
//  MyWindow.m
//  Zephyros
//
//  Created by Steven Degutis on 2/28/13.
//  Copyright (c) 2013 Steven Degutis. All rights reserved.
//

#import "SDWindowProxy.h"

#import "SDAppProxy.h"

#import "SDUniversalAccessHelper.h"

#import "SDGeometry.h"

@interface SDWindowProxy ()

@property CFTypeRef window;

@end

@implementation SDWindowProxy

- (id) initWithElement:(AXUIElementRef)win {
    if (self = [super init]) {
        self.window = CFRetain(win);
    }
    return self;
}

- (void) dealloc {
    if (self.window)
        CFRelease(self.window);
}

+ (NSArray*) allWindows {
    if ([SDUniversalAccessHelper complainIfNeeded])
        return nil;
    
    NSMutableArray* windows = [NSMutableArray array];
    
    for (SDAppProxy* app in [SDAppProxy runningApps]) {
        [windows addObjectsFromArray:[app allWindows]];
    }
    
    return windows;
}

- (BOOL) isNormalWindow {
    return [[self subrole] isEqualToString: (__bridge NSString*)kAXStandardWindowSubrole];
}

+ (NSArray*) visibleWindows {
    if ([SDUniversalAccessHelper complainIfNeeded])
        return nil;
    
    return [[self allWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SDWindowProxy* win, NSDictionary *bindings) {
        return ![[win app] isHidden]
        && ![win isWindowMinimized]
        && [win isNormalWindow];
    }]];
}

- (NSArray*) otherWindowsOnSameScreen {
    return [[SDWindowProxy visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SDWindowProxy* win, NSDictionary *bindings) {
        return !CFEqual(self.window, win.window) && [[self screen] isEqual: [win screen]];
    }]];
}

- (NSArray*) otherWindowsOnAllScreens {
    return [[SDWindowProxy visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SDWindowProxy* win, NSDictionary *bindings) {
        return !CFEqual(self.window, win.window);
    }]];
}

+ (AXUIElementRef) systemWideElement {
    static AXUIElementRef systemWideElement;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        systemWideElement = AXUIElementCreateSystemWide();
    });
    return systemWideElement;
}

+ (SDWindowProxy*) focusedWindow {
    if ([SDUniversalAccessHelper complainIfNeeded])
        return nil;
    
    CFTypeRef app;
    AXUIElementCopyAttributeValue([self systemWideElement], kAXFocusedApplicationAttribute, &app);
    
    CFTypeRef win;
    AXError result = AXUIElementCopyAttributeValue(app, (CFStringRef)NSAccessibilityFocusedWindowAttribute, &win);
    CFRelease(app);
    
    if (result == kAXErrorSuccess) {
        SDWindowProxy* window = [[SDWindowProxy alloc] init];
        window.window = win;
        return window;
    }
    
    return nil;
}

- (NSDictionary*) frame {
    CGRect r;
    r.origin = SDPointFromDict([self topLeft]);
    r.size = SDSizeFromDict([self size]);
    return SDDictFromRect(r);
}

- (void) setFrame:(NSDictionary*)frameDict {
    [self setSize: frameDict];
    [self setTopLeft: frameDict];
    [self setSize: frameDict];
}

- (NSDictionary*) topLeft {
    CFTypeRef positionStorage;
    AXError result = AXUIElementCopyAttributeValue(self.window, (CFStringRef)NSAccessibilityPositionAttribute, &positionStorage);
    
    CGPoint topLeft;
    if (result == kAXErrorSuccess) {
        if (!AXValueGetValue(positionStorage, kAXValueCGPointType, (void *)&topLeft)) {
            NSLog(@"could not decode topLeft");
            topLeft = CGPointZero;
        }
    }
    else {
        NSLog(@"could not get window topLeft");
        topLeft = CGPointZero;
    }
    
    if (positionStorage)
        CFRelease(positionStorage);
    
    return SDDictFromPoint(topLeft);
}

- (NSDictionary*) size {
    CFTypeRef sizeStorage;
    AXError result = AXUIElementCopyAttributeValue(self.window, (CFStringRef)NSAccessibilitySizeAttribute, &sizeStorage);
    
    CGSize size;
    if (result == kAXErrorSuccess) {
        if (!AXValueGetValue(sizeStorage, kAXValueCGSizeType, (void *)&size)) {
            NSLog(@"could not decode topLeft");
            size = CGSizeZero;
        }
    }
    else {
        NSLog(@"could not get window size");
        size = CGSizeZero;
    }
    
    if (sizeStorage)
        CFRelease(sizeStorage);
    
    return SDDictFromSize(size);
}

- (void) setTopLeft:(NSDictionary*)thePointDict {
    CGPoint thePoint = SDPointFromDict(thePointDict);
    CFTypeRef positionStorage = (CFTypeRef)(AXValueCreate(kAXValueCGPointType, (const void *)&thePoint));
    AXUIElementSetAttributeValue(self.window, (CFStringRef)NSAccessibilityPositionAttribute, positionStorage);
    if (positionStorage)
        CFRelease(positionStorage);
}

- (void) setSize:(NSDictionary*)theSizeDict {
    CGSize theSize = SDSizeFromDict(theSizeDict);
    CFTypeRef sizeStorage = (CFTypeRef)(AXValueCreate(kAXValueCGSizeType, (const void *)&theSize));
    AXUIElementSetAttributeValue(self.window, (CFStringRef)NSAccessibilitySizeAttribute, sizeStorage);
    if (sizeStorage)
        CFRelease(sizeStorage);
}

- (SDScreenProxy*) screen {
    CGRect windowFrame = SDRectFromDict([self frame]);
    
    CGFloat lastVolume = 0;
    SDScreenProxy* lastScreen = nil;
    
    for (SDScreenProxy* screen in [SDScreenProxy allScreens]) {
        CGRect screenFrame = SDRectFromDict([screen frameIncludingDockAndMenu]);
        CGRect intersection = CGRectIntersection(windowFrame, screenFrame);
        CGFloat volume = intersection.size.width * intersection.size.height;
        
        if (volume > lastVolume) {
            lastVolume = volume;
            lastScreen = screen;
        }
    }
    
    return lastScreen;
}

- (void) maximize {
    CGRect screenRect = SDRectFromDict([[self screen] frameWithoutDockOrMenu]);
    [self setFrame: SDDictFromRect(screenRect)];
}

- (void) minimize {
    [self setWindowMinimized:YES];
}

- (void) unMinimize {
    [self setWindowMinimized:NO];
}

- (NSNumber*) focusWindow {
    AXError changedMainWindowResult = AXUIElementSetAttributeValue(self.window, (CFStringRef)NSAccessibilityMainAttribute, kCFBooleanTrue);
    if (changedMainWindowResult != kAXErrorSuccess) {
        NSLog(@"ERROR: Could not change focus to window");
        return @NO;
    }
    
    ProcessSerialNumber psn;
    GetProcessForPID([self processIdentifier], &psn);
    OSStatus focusAppResult = SetFrontProcessWithOptions(&psn, kSetFrontProcessFrontWindowOnly);
    return @(focusAppResult == 0);
}

- (pid_t) processIdentifier {
    pid_t pid = 0;
    AXError result = AXUIElementGetPid(self.window, &pid);
    if (result == kAXErrorSuccess)
        return pid;
    else
        return 0;
}

- (SDAppProxy*) app {
    return [[SDAppProxy alloc] initWithPID:[self processIdentifier]];
}

- (id) getWindowProperty:(NSString*)propType withDefaultValue:(id)defaultValue {
    CFTypeRef _someProperty;
    if (AXUIElementCopyAttributeValue(self.window, (__bridge CFStringRef)propType, &_someProperty) == kAXErrorSuccess)
        return CFBridgingRelease(_someProperty);
    
    return defaultValue;
}

- (BOOL) setWindowProperty:(NSString*)propType withValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        AXError result = AXUIElementSetAttributeValue(self.window, (__bridge CFStringRef)(propType), (__bridge CFTypeRef)(value));
        if (result == kAXErrorSuccess)
            return YES;
    }
    return NO;
}

- (NSString *) title {
    return [self getWindowProperty:NSAccessibilityTitleAttribute withDefaultValue:@""];
}

- (NSString *) role {
    return [self getWindowProperty:NSAccessibilityRoleAttribute withDefaultValue:@""];
}

- (NSString *) subrole {
    return [self getWindowProperty:NSAccessibilitySubroleAttribute withDefaultValue:@""];
}

- (BOOL) isWindowMinimized {
    return [[self getWindowProperty:NSAccessibilityMinimizedAttribute withDefaultValue:@(NO)] boolValue];
}

- (void) setWindowMinimized:(BOOL)flag
{
    [self setWindowProperty:NSAccessibilityMinimizedAttribute withValue:[NSNumber numberWithLong:flag]];
}

// focus


NSPoint SDMidpoint(NSRect r) {
    return NSMakePoint(NSMidX(r), NSMidY(r));
}

- (NSArray*) windowsInDirectionFn:(double(^)(double angle))whichDirectionFn
                shouldDisregardFn:(BOOL(^)(double deltaX, double deltaY))shouldDisregardFn
{
    SDWindowProxy* thisWindow = [SDWindowProxy focusedWindow];
    NSPoint startingPoint = SDMidpoint(SDRectFromDict([thisWindow frame]));
    
    NSArray* otherWindows = [thisWindow otherWindowsOnAllScreens];
    NSMutableArray* closestOtherWindows = [NSMutableArray arrayWithCapacity:[otherWindows count]];
    
    for (SDWindowProxy* win in otherWindows) {
        NSPoint otherPoint = SDMidpoint(SDRectFromDict([win frame]));
        
        double deltaX = otherPoint.x - startingPoint.x;
        double deltaY = otherPoint.y - startingPoint.y;
        
        if (shouldDisregardFn(deltaX, deltaY))
            continue;
        
        double angle = atan2(deltaY, deltaX);
        double distance = hypot(deltaX, deltaY);
        
        double angleDifference = whichDirectionFn(angle);
        
        double score = distance / cos(angleDifference / 2.0);
        
        [closestOtherWindows addObject:@{
         @"score": @(score),
         @"win": win,
         }];
    }
    
    NSArray* sortedOtherWindows = [closestOtherWindows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* pair1, NSDictionary* pair2) {
        return [[pair1 objectForKey:@"score"] compare: [pair2 objectForKey:@"score"]];
    }];
    
    return sortedOtherWindows;
}

- (void) focusFirstValidWindowIn:(NSArray*)closestWindows {
    for (SDWindowProxy* win in closestWindows) {
        if ([win focusWindow])
            break;
    }
}

- (NSArray*) windowsToWest {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI - abs(angle); }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray*) windowsToEast {
    return [[self windowsInDirectionFn:^double(double angle) { return 0.0 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX <= 0); }] valueForKeyPath:@"win"];
}

- (NSArray*) windowsToNorth {
    return [[self windowsInDirectionFn:^double(double angle) { return -M_PI_2 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray*) windowsToSouth {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI_2 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY <= 0); }] valueForKeyPath:@"win"];
}

- (void) focusWindowLeft {
    [self focusFirstValidWindowIn:[self windowsToWest]];
}

- (void) focusWindowRight {
    [self focusFirstValidWindowIn:[self windowsToEast]];
}

- (void) focusWindowUp {
    [self focusFirstValidWindowIn:[self windowsToNorth]];
}

- (void) focusWindowDown {
    [self focusFirstValidWindowIn:[self windowsToSouth]];
}

@end
