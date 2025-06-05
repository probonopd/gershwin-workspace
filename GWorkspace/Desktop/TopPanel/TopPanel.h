#import <AppKit/AppKit.h>

@class GWDesktopManager;

@interface TopPanel : NSView
{
    GWDesktopManager *_manager;
}
- (instancetype)initForManager:(GWDesktopManager *)manager;
- (void)tile;
@end
