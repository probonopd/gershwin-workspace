#import "TopPanel.h"
#import "GWDesktopManager.h"

@implementation TopPanel

- (instancetype)initForManager:(GWDesktopManager *)manager {
    self = [super initWithFrame:NSMakeRect(0, 0, 100, 28)];
    if (self) {
        _manager = manager;
        [self setAutoresizingMask:NSViewWidthSizable];
        [self setNeedsDisplay:YES];
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    [[NSColor controlBackgroundColor] set];
    NSRectFill(rect);
}

- (void)tile {
    NSRect screen = [[NSScreen mainScreen] frame];
    CGFloat height = 28.0;
    [self setFrame:NSMakeRect(0, screen.size.height - height, screen.size.width, height)];
    [self setNeedsDisplay:YES];
}

@end
