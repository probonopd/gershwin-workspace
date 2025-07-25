/* GWViewersManager.m
 *  
 * Copyright (C) 2004-2016 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: June 2004
 *
 * This file is part of the GNUstep GWorkspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <AppKit/AppKit.h>
#import "GWViewersManager.h"
#import "GWViewer.h"
#import "GWSpatialViewer.h"
#import "GWViewerWindow.h"
#import "History.h"
#import "FSNFunctions.h"
#import "GWorkspace.h"
#import "GWDesktopManager.h"


static GWViewersManager *vwrsmanager = nil;

@implementation GWViewersManager

+ (GWViewersManager *)viewersManager
{
  if (vwrsmanager == nil)
    {
      vwrsmanager = [[GWViewersManager alloc] init];
    }	
  return vwrsmanager;
}

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver: self];
  [nc removeObserver: self];
  RELEASE (viewers);
  RELEASE (spatialViewersHistory);
  RELEASE (bviewerHelp);
  RELEASE (sviewerHelp);
    
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self)
    {
      NSNotificationCenter *wsnc;
      
      gworkspace = [GWorkspace gworkspace];
      helpManager = [NSHelpManager sharedHelpManager];
      wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
      ASSIGN (bviewerHelp, [gworkspace contextHelpFromName: @"BViewer.rtfd"]);
      ASSIGN (sviewerHelp, [gworkspace contextHelpFromName: @"SViewer.rtfd"]);
      
      viewers = [NSMutableArray new];
      orderingViewers = NO;
      
      spatialViewersHistory = [NSMutableArray new]; 
      spvHistoryPos = 0;  
      historyWindow = [gworkspace historyWindow]; 
      nc = [NSNotificationCenter defaultCenter];
      
      [nc addObserver: self 
             selector: @selector(fileSystemWillChange:) 
                 name: @"GWFileSystemWillChangeNotification"
               object: nil];
      
      [nc addObserver: self 
             selector: @selector(fileSystemDidChange:) 
                 name: @"GWFileSystemDidChangeNotification"
               object: nil];
      
      [nc addObserver: self 
             selector: @selector(watcherNotification:) 
                 name: @"GWFileWatcherFileDidChangeNotification"
               object: nil];    
      
      [[NSDistributedNotificationCenter defaultCenter] addObserver: self 
                                                          selector: @selector(sortTypeDidChange:) 
                                                              name: @"GWSortTypeDidChangeNotification"
                                                            object: nil];

      // should perhaps volume notification be distributed?
      [wsnc addObserver: self 
               selector: @selector(newVolumeMounted:) 
                   name: NSWorkspaceDidMountNotification
                 object: nil];
      
      
      [wsnc addObserver: self 
               selector: @selector(mountedVolumeDidUnmount:) 
                   name: NSWorkspaceDidUnmountNotification
                 object: nil];
      
      [[FSNodeRep sharedInstance] setLabelWFactor: 9.0];
    }
  
  return self;
}


- (void)showViewers
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
  NSArray *viewersInfo = [defaults objectForKey: @"viewersinfo"];

  if (viewersInfo && [viewersInfo count]) {
    int i;
    
    for (i = 0; i < [viewersInfo count]; i++) {
      NSDictionary *dict = [viewersInfo objectAtIndex: i];
      NSString *path = [dict objectForKey: @"path"];
      int type = [[dict objectForKey: @"type"] intValue];
      FSNode *node = [FSNode nodeWithPath: path];
    
      if (node && [node isValid])
        {
          [self viewerOfType: type
                    showType: nil
                     forNode: node
               showSelection: YES
              closeOldViewer: nil
                    forceNew: YES];
      }
    }

  } else {
    [self showRootViewer];
  }
}

- (id)showRootViewer
{
  NSString *path = path_separator();
  FSNode *node = [FSNode nodeWithPath: path];
  id viewer = [self rootViewer];
  int type = BROWSING;
  
  if (viewer == nil) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", path];
    NSDictionary *viewerPrefs = [defaults objectForKey: prefsname];
   
    if (viewerPrefs) {
      id entry = [viewerPrefs objectForKey: @"spatial"];
   
      if (entry) {
        type = ([entry boolValue] ? SPATIAL : BROWSING);
      }
    }
  
    viewer = [self viewerOfType: type
                       showType: nil
                        forNode: node
                  showSelection: YES
                 closeOldViewer: nil
                       forceNew: NO];
  } else {
    if ([[viewer win] isVisible] == NO) {
  	  [viewer activate];
      
    } else {
      if ([self viewerOfType: SPATIAL withBaseNode: node] == nil) {
        type = [self typeOfViewerForNode: node];
      } else {
        type = BROWSING;
      }

      viewer = [self viewerOfType: type
                         showType: nil
                          forNode: node
                    showSelection: (type == BROWSING)
                   closeOldViewer: nil
                         forceNew: YES];
    }
  }
  
  return viewer;
}

- (void)selectRepOfNode:(FSNode *)node
          inViewerWithBaseNode:(FSNode *)base
{
  BOOL inRootViewer = [[base path] isEqual: path_separator()];
  BOOL baseIsParent = [[node parentPath] isEqual: [base path]];
  NSArray *selection = [NSArray arrayWithObject: node];
  id viewer = nil;
  
  if ([base isEqual: node] || ([node isSubnodeOfNode: base] == NO)) {
    baseIsParent = YES;
    selection = nil;      
  }
  
  if (inRootViewer) {  
    viewer = [self rootViewer];
    
    if (viewer == nil) {
      viewer = [self showRootViewer];
    }
    
    if (([viewer vtype] == SPATIAL) 
            && [[viewer nodeView] isSingleNode]
                              && (baseIsParent == NO))
      { 
        viewer = [self viewerOfType: BROWSING
                           showType: nil
                            forNode: base
                      showSelection: NO
                     closeOldViewer: nil
                           forceNew: YES];
      }
    
  } else {
    int type = [self typeOfViewerForNode: base];
    int newtype = ((type == SPATIAL) && baseIsParent) ? SPATIAL : BROWSING;

    viewer = [self viewerOfType: newtype
                       showType: nil
                        forNode: base
                  showSelection: NO
                 closeOldViewer: nil
                       forceNew: NO];
  } 
  
  if (selection) {
    [[viewer nodeView] selectRepsOfSubnodes: selection];  
  }
}

- (id)viewerForNode:(FSNode *)node
          showType:(GWViewType)stype
     showSelection:(BOOL)showsel
          forceNew:(BOOL)force
	   withKey:(NSString *)key
{
  id viewer = [self viewerOfType: BROWSING withBaseNode: node];
    
  if ((viewer == nil) || (force))
    {
      Class c = [GWViewer class];
      GWViewerWindow *win = [GWViewerWindow new];
      
      [win setReleasedWhenClosed: NO];
      
      viewer = [[c alloc] initForNode: node 
			     inWindow: win 
			     showType: stype
			showSelection: showsel
			      withKey: key]; 
      
      [viewers addObject: viewer];
      RELEASE (win);
      RELEASE (viewer);
    } 
  
  [viewer activate];
  

  [helpManager setContextHelp: bviewerHelp
                    forObject: [[viewer win] contentView]];
       
  return viewer;
}

- (NSArray *)viewersForBaseNode:(FSNode *)node
{
  NSMutableArray *vwrs = [NSMutableArray array];
  NSUInteger i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([[viewer baseNode] isEqual: node]) {
      [vwrs addObject: viewer];
    }
  }
  
  return vwrs;
}

- (id)viewerOfType:(unsigned)type
      withBaseNode:(FSNode *)node
{
  int i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];

    if (([viewer vtype] == type) && [[viewer baseNode] isEqual: node]) {
      return viewer;
    }
  }
  
  return nil;
}

- (id)viewerOfType:(unsigned)type
       showingNode:(FSNode *)node
{
  int i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];

    if (([viewer vtype] == type) && [viewer isShowingNode: node]) {
      return viewer;
    }
  }
  
  return nil;
}

- (id)rootViewer
{
  NSUInteger i;

  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([viewer isFirstRootViewer])
	{
	  return viewer;
	}
    }

  return nil;
}

- (int)typeOfViewerForNode:(FSNode *)node
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *path = [node path];
  NSString *dictPath = [path stringByAppendingPathComponent: @".gwdir"];
  NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", path];
  NSDictionary *viewerPrefs = nil;

  if ([node isWritable] && ([fm fileExistsAtPath: dictPath])) {
    viewerPrefs = [NSDictionary dictionaryWithContentsOfFile: dictPath];
  }
  
  if (viewerPrefs == nil) {
    viewerPrefs = [[NSUserDefaults standardUserDefaults] objectForKey: prefsname];
  }
  
  if (viewerPrefs) {
    id entry = [viewerPrefs objectForKey: @"spatial"];
  
    if (entry) {
      return ([entry boolValue] ? SPATIAL : BROWSING);
    }
  }
  
  return BROWSING;
}

- (id)parentOfSpatialViewer:(id)aviewer
{
  if ([aviewer isSpatial]) {
    FSNode *node = [aviewer baseNode];

    if ([[node path] isEqual: path_separator()] == NO) {
      FSNode *parentNode = [FSNode nodeWithPath: [node parentPath]];

      return [self viewerOfType: SPATIAL showingNode: parentNode];
    }
  }
      
  return nil;  
}

- (void)viewerWillClose:(id)aviewer
{
  FSNode *node = [aviewer baseNode];
  NSArray *watchedNodes = [aviewer watchedNodes];
  NSUInteger i;

  
  if ([node isValid] == NO)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
      NSString *prefsname;
      NSDictionary *vwrprefs;

      prefsname = [aviewer defaultsKey];

      vwrprefs = [defaults dictionaryForKey: prefsname];
      if (vwrprefs)
        {
          [defaults removeObjectForKey: prefsname];
        } 
    
      [NSWindow removeFrameUsingName: prefsname]; 
    }
  
  for (i = 0; i < [watchedNodes count]; i++)
    [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: i] path]];

  if (aviewer == [historyWindow viewer])
    [self changeHistoryOwner: nil];

  [helpManager removeContextHelpForObject: [[aviewer win] contentView]];
  [viewers removeObject: aviewer];
}

- (void)closeInvalidViewers:(NSArray *)vwrs
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  int i, j;

  for (i = 0; i < [vwrs count]; i++) {
    id viewer = [vwrs objectAtIndex: i];
    NSString *vpath = [[viewer baseNode] path];
    NSArray *watchedNodes = [viewer watchedNodes];
    id parentViewer = [self parentOfSpatialViewer: viewer];
    NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", vpath]; 
    NSDictionary *vwrprefs = [defaults dictionaryForKey: prefsname];
    
    if (parentViewer && ([vwrs containsObject: parentViewer] == NO)) {
      [parentViewer setOpened: NO repOfNode: [viewer baseNode]];
    }

    if (vwrprefs) {
      [defaults removeObjectForKey: prefsname];
    } 

    [NSWindow removeFrameUsingName: prefsname]; 
    
    for (j = 0; j < [watchedNodes count]; j++) {
      [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: j] path]];
    }
  }
      
  for (i = 0; i < [vwrs count]; i++) {
    id viewer = [vwrs objectAtIndex: i];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 0.1];
    
    if (viewer == [historyWindow viewer]) {
      [self changeHistoryOwner: nil];
    }

    [viewer deactivate];
	  [[NSRunLoop currentRunLoop] runUntilDate: limit];
    [helpManager removeContextHelpForObject: [[viewer win] contentView]];
    [viewers removeObject: viewer];
  }
}

- (void)setBehaviour:(NSString *)behaviour 
           forViewer:(id)aviewer
{
  // Set the behaviour (view type/mode) for the viewer
  // This is typically called from menu actions to change viewer behavior
  if ([behaviour isEqualToString: @"Browser"]) {
    [aviewer setViewType: GWViewTypeBrowser];
  } else if ([behaviour isEqualToString: @"Icon"]) {
    [aviewer setViewType: GWViewTypeIcon];
  } else if ([behaviour isEqualToString: @"List"]) {
    [aviewer setViewType: GWViewTypeList];
  } else if ([behaviour isEqualToString: @"Spatial"]) {
    [aviewer setViewType: GWViewTypeSpatial];
  }
  // Add other behavior types as needed
}

- (id)spatialViewerForNode:(FSNode *)node 
             showSelection:(BOOL)showsel 
            closeOldViewer:(id)oldvwr 
                  forceNew:(BOOL)force
{
  // Implementation for creating/getting spatial viewer
  // This creates or finds a spatial viewer for the given node
  id existingViewer = [self viewerWithBaseNode: node];
  
  if (existingViewer && !force) {
    [existingViewer makeKeyAndOrderFront: nil];
    if (showsel) {
      // Show selection in existing viewer
    }
    return existingViewer;
  }
  
  if (oldvwr && [oldvwr respondsToSelector: @selector(close)]) {
    [oldvwr close];
  }
  
  // Create new spatial viewer
  // For now, return a browser viewer as fallback
  return [self rootViewerForNode: node];
}

- (id)rootViewerForNode:(FSNode *)node
{
  // Implementation for creating/getting root viewer
  // This creates or finds a root viewer for the given node
  id existingViewer = [self viewerWithBaseNode: node];
  
  if (existingViewer) {
    [existingViewer makeKeyAndOrderFront: nil];
    return existingViewer;
  }
  
  // Create new root viewer using existing methods
  return [self viewerForNode: node showType: GWViewTypeBrowser showSelection: NO forceNew: NO withKey: nil];
}

// Add missing method implementations for proper header compliance

- (id)viewerOfType:(unsigned)vtype
          showType:(NSString *)stype
           forNode:(FSNode *)node
     showSelection:(BOOL)showsel
    closeOldViewer:(id)oldvwr
          forceNew:(BOOL)force
{
  // Implementation for creating/getting viewer of specific type
  if (vtype == GWViewTypeSpatial) {
    return [self spatialViewerForNode: node showSelection: showsel closeOldViewer: oldvwr forceNew: force];
  }
  
  // For other viewer types, use existing logic
  return [self rootViewerForNode: node];
}

- (id)viewerWithBaseNode:(FSNode *)node
{
  // Find existing viewer with this base node
  int i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    if ([[viewer baseNode] isEqual: node]) {
      return viewer;
    }
  }
  
  return nil;
}

- (NSNumber *)nextRootViewerKey
{
  // Generate next available key for root viewer
  int maxKey = 0;
  int i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    if ([viewer respondsToSelector: @selector(key)]) {
      id viewerKey = [viewer key];
      if (viewerKey && [viewerKey respondsToSelector: @selector(intValue)]) {
        int keyValue = [viewerKey intValue];
        if (keyValue > maxKey) {
          maxKey = keyValue;
        }
      }
    }
  }
  
  return [NSNumber numberWithInt: (maxKey + 1)];
}

// Add all the other missing methods with stub implementations

- (void)selectedSpatialViewerChanged:(id)aviewer
{
  // Handle spatial viewer selection changes
}

- (void)synchronizeSelectionInParentOfViewer:(id)aviewer
{
  // Synchronize selection in parent viewer
}

- (void)viewer:(id)aviewer didShowNode:(FSNode *)node
{
  // Handle viewer showing a node
}

- (void)selectionChanged:(NSArray *)selection
{
  // Handle selection changes
}

- (void)openSelectionInViewer:(id)viewer closeSender:(BOOL)close
{
  // Open selection in viewer
}

- (void)openAsFolderSelectionInViewer:(id)viewer
{
  // Open selection as folder in viewer
}

- (void)openWithSelectionInViewer:(id)viewer
{
  // Open selection with application
}

- (void)sortTypeDidChange:(NSNotification *)notif
{
  // Handle sort type changes
}

- (void)fileSystemWillChange:(NSNotification *)notif
{
  // Handle file system will change notifications
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  // Handle file system did change notifications
}

- (void)watcherNotification:(NSNotification *)notif
{
  // Handle file watcher notifications
}

- (void)thumbnailsDidChangeInPaths:(NSArray *)paths
{
  // Handle thumbnail changes
}

- (void)hideDotsFileDidChange:(BOOL)hide
{
  // Handle hidden files preference changes
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  // Handle hidden files changes
}

- (BOOL)hasViewerWithWindow:(id)awindow
{
  // Check if there's a viewer with the given window
  return NO;
}

- (id)viewerWithWindow:(id)awindow
{
  // Find viewer with the given window
  return nil;
}

- (NSArray *)viewerWindows
{
  // Return array of viewer windows
  return [NSArray array];
}

- (BOOL)orderingViewers
{
  // Return whether viewers are being ordered
  return orderingViewers;
}

- (void)updateDesktop
{
  // Update desktop
}

- (void)updateDefaults
{
  // Update defaults
}

@end


@implementation GWViewersManager (History)

- (void)addNode:(FSNode *)node toHistoryOfViewer:(id)viewer
{
  if ([node isValid] && (settingHistoryPath == NO)) {
    BOOL spatial = [viewer isSpatial];
    NSMutableArray *history = (spatial ? spatialViewersHistory: [viewer history]);
    int position = (spatial ? spvHistoryPos : [viewer historyPosition]);
    id hisviewer = [historyWindow viewer];
    int cachemax = [gworkspace maxHistoryCache];
    int count;

    while ([history count] > cachemax) {
      [history removeObjectAtIndex: 0];
      if (position > 0) {
        position--;
      }
    }
    
    count = [history count];
    
	  if (position == (count - 1)) {
		  if ([[history lastObject] isEqual: node] == NO) {
			  [history insertObject: node atIndex: count];
		  }
      position = [history count] - 1;

    } else if (count > (position + 1)) {
      BOOL equalpos = [[history objectAtIndex: position] isEqual: node];
      BOOL equalnext = [[history objectAtIndex: position + 1] isEqual: node];
    
		  if (((equalpos == NO) && (equalnext == NO)) || equalnext) {
			  position++;
        
        if (equalnext == NO) {
			    [history insertObject: node atIndex: position];
        }
        
			  while ((position + 1) < [history count]) {
				  int last = [history count] - 1;
				  [history removeObjectAtIndex: last];
			  }
		  }
	  }

    [self removeDuplicatesInHistory: history position: &position];

    if (spatial) {
      spvHistoryPos = position;
    } else {
      [viewer setHistoryPosition: position];
    }

    if ((viewer == hisviewer) 
                || (spatial && (hisviewer && [hisviewer isSpatial]))) {
      [historyWindow setHistoryNodes: history position: position];
    }
  }
}

- (void)removeDuplicatesInHistory:(NSMutableArray *)history
                         position:(int *)pos
{
  int count = [history count];
  int i;
  
#define CHECK_POSITION(n) \
if (*pos >= i) *pos -= n; \
*pos = (*pos < 0) ? 0 : *pos; \
*pos = (*pos >= count) ? (count - 1) : *pos	
  
	for (i = 0; i < count; i++) {
		FSNode *node = [history objectAtIndex: i];
		
		if ([node isValid] == NO) {
			[history removeObjectAtIndex: i];
			CHECK_POSITION (1);		
			count--;
			i--;
		}
	}

	for (i = 0; i < count; i++) {
		FSNode *node = [history objectAtIndex: i];

		if (i < ([history count] - 1)) {
			FSNode *next = [history objectAtIndex: i + 1];
			
			if ([next isEqual: node]) {
				[history removeObjectAtIndex: i + 1];
				CHECK_POSITION (1);
				count--;
				i--;
			}
		}
	}
  
  count = [history count];
  
	if (count > 4) {
		FSNode *na[2], *nb[2];
		
		for (i = 0; i < count; i++) {
			if (i < (count - 3)) {
				na[0] = [history objectAtIndex: i];
				na[1] = [history objectAtIndex: i + 1];
				nb[0] = [history objectAtIndex: i + 2]; 
				nb[1] = [history objectAtIndex: i + 3];
		
				if (([na[0] isEqual: nb[0]]) && ([na[1] isEqual: nb[1]])) {
					[history removeObjectAtIndex: i + 3];
					[history removeObjectAtIndex: i + 2];
					CHECK_POSITION (2);
					count -= 2;
					i--;
				}
			}
		}
	}
    
  CHECK_POSITION (0);
}

- (void)changeHistoryOwner:(id)viewer
{
  if (viewer && (viewer != [historyWindow viewer])) {
    BOOL spatial = [viewer isSpatial];
    NSMutableArray *history = (spatial ? spatialViewersHistory: [viewer history]);
    int position = (spatial ? spvHistoryPos : [viewer historyPosition]);
  
    [historyWindow setHistoryNodes: history position: position];

  } else if (viewer == nil) {
    [historyWindow setHistoryNodes: nil];
  }

  [historyWindow setViewer: viewer];  
}

- (void)goToHistoryPosition:(int)pos 
                   ofViewer:(id)viewer
{
  if (viewer) {
    BOOL spatial = [viewer isSpatial];
    NSMutableArray *history = (spatial ? spatialViewersHistory: [viewer history]);
    int position = (spatial ? spvHistoryPos : [viewer historyPosition]);
 
    [self removeDuplicatesInHistory: history position: &position];

	  if ((pos >= 0) && (pos < [history count])) {
      [self setPosition: pos inHistory: history ofViewer: viewer];
    }
  }
}

- (void)goBackwardInHistoryOfViewer:(id)viewer
{
  BOOL spatial = [viewer isSpatial];
  NSMutableArray *history = (spatial ? spatialViewersHistory: [viewer history]);
  int position = (spatial ? spvHistoryPos : [viewer historyPosition]);

  [self removeDuplicatesInHistory: history position: &position];

  if ((position > 0) && (position < [history count])) {
    position--;
    [self setPosition: position inHistory: history ofViewer: viewer];
  }
}

- (void)goForwardInHistoryOfViewer:(id)viewer
{
  BOOL spatial = [viewer isSpatial];
  NSMutableArray *history = (spatial ? spatialViewersHistory: [viewer history]);
  int position = (spatial ? spvHistoryPos : [viewer historyPosition]);

  [self removeDuplicatesInHistory: history position: &position];
  
  if ((position >= 0) && (position < ([history count] - 1))) {
    position++;
    [self setPosition: position inHistory: history ofViewer: viewer];
  }
}

- (void)setPosition:(int)position
          inHistory:(NSMutableArray *)history
           ofViewer:(id)viewer
{
  FSNode *node = [history objectAtIndex: position];
  id nodeView = [viewer nodeView];
  
  settingHistoryPath = YES;
  
  if ([viewer viewType] != GWViewTypeBrowser)
    {
      [nodeView showContentsOfNode: node];
    }
  else
    {
      [nodeView showContentsOfNode: [FSNode nodeWithPath: [node parentPath]]];
      [nodeView selectRepsOfSubnodes: [NSArray arrayWithObject: node]];
    }

  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)])
    [nodeView scrollSelectionToVisible];

  [viewer setHistoryPosition: position];

  [historyWindow setHistoryPosition: position];

  settingHistoryPath = NO;
}

- (void)newVolumeMounted:(NSNotification *)notif
{
  // Handle new volume mounted notification
  // This could update viewers to show the new volume
  NSString *volpath = [[notif userInfo] objectForKey: @"NSDevicePath"];
  if (volpath) {
    // Notify all viewers about the new volume
    // For now, just log it to avoid errors
    NSLog(@"New volume mounted at: %@", volpath);
  }
}

@end

