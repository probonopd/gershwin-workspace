/* fswatcher-kqueue.m
 *  
 * Copyright (C) 2025 Free Software Foundation, Inc.
 *
 * Author: Simon Peter
 * Date: July 2025
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

#import "fswatcher-kqueue.h"
#include "config.h"
#include <unistd.h>
#include <dirent.h>

#define GWDebugLog(format, args...) \
  do { if (GW_DEBUG_LOG) \
    NSLog(format , ## args); } while (0)

// Notification names
static NSString *GWFileDeletedInWatchedDirectory = @"GWFileDeletedInWatchedDirectory";
static NSString *GWFileCreatedInWatchedDirectory = @"GWFileCreatedInWatchedDirectory";
static NSString *GWWatchedFileModified = @"GWWatchedFileModified";
static NSString *GWMountPointsChanged = @"GWMountPointsChanged";


@implementation	FSWClientInfo

- (void)dealloc
{
  RELEASE (conn);
  RELEASE (client);
  RELEASE (wpaths);
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self)
    {
      client = nil;
      conn = nil;
      wpaths = [[NSCountedSet alloc] initWithCapacity: 1];
      global = NO;
    }
  
  return self;
}

- (void)setConnection:(NSConnection *)connection
{
	ASSIGN (conn, connection);
}

- (NSConnection *)connection
{
	return conn;
}

- (void)setClient:(id <FSWClientProtocol>)clnt
{
	ASSIGN (client, clnt);
}

- (id <FSWClientProtocol>)client
{
	return client;
}

- (void)addWatchedPath:(NSString *)path
{
  [wpaths addObject: path];
}

- (void)removeWatchedPath:(NSString *)path
{
  [wpaths removeObject: path];
}

- (BOOL)isWatchingPath:(NSString *)path
{
  return [wpaths containsObject: path];
}

- (NSSet *)watchedPaths
{
  return wpaths;
}

- (void)setGlobal:(BOOL)value
{
  global = value;
}

- (BOOL)isGlobal
{
  return global;
}

@end


@implementation	FSWatcher

- (void)dealloc
{
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++)
    {
      NSConnection *connection = [[clientsInfo objectAtIndex: i] connection];

      if (connection)
	{
	  [nc removeObserver: self
			name: NSConnectionDidDieNotification
		      object: connection];
	}
    }
  
  if (conn) {
    [nc removeObserver: self
		              name: NSConnectionDidDieNotification
		            object: conn];
  }

  [dnc removeObserver: self];
  
  [mountWatcher stopWatching];
  RELEASE (mountWatcher);
  
  RELEASE (clientsInfo);
  NSZoneFree (NSDefaultMallocZone(), (void *)watchers);
  NSZoneFree (NSDefaultMallocZone(), (void *)fdToWatcherMap);
  freeTree(includePathsTree);
  freeTree(excludePathsTree);
  RELEASE (excludedSuffixes);
  
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self)
    {    
      fm = [NSFileManager defaultManager];	
      nc = [NSNotificationCenter defaultCenter];
      dnc = [NSDistributedNotificationCenter defaultCenter];
      
      conn = [NSConnection defaultConnection];
      [conn setRootObject: self];
      [conn setDelegate: self];
    
      if ([conn registerName: @"fswatcher"] == NO)
	{
	  NSLog(@"unable to register with name server.");
	  DESTROY (self);
	  return self;
	}

      clientsInfo = [NSMutableArray new];    
      watchers = NSCreateMapTable(NSObjectMapKeyCallBacks,
                                  NSObjectMapValueCallBacks, 0);
      fdToWatcherMap = NSCreateMapTable(NSIntMapKeyCallBacks,
                                        NSNonOwnedPointerMapValueCallBacks, 0);
                                          
      includePathsTree = newTreeWithIdentifier(@"incl_paths");
      excludePathsTree = newTreeWithIdentifier(@"excl_paths");
      excludedSuffixes = [[NSMutableSet alloc] initWithCapacity: 1];
      
      [self setDefaultGlobalPaths];

      [nc addObserver: self
           selector: @selector(connectionBecameInvalid:)
	             name: NSConnectionDidDieNotification
	           object: conn];

      [dnc addObserver: self
            selector: @selector(globalPathsChanged:)
	              name: @"GSMetadataIndexedDirectoriesChanged"
	            object: nil];

      // Initialize mount watcher
      mountWatcher = [[MountWatcher alloc] initWithFSWatcher: self];
      [mountWatcher startWatching];
      
      [nc addObserver: self
           selector: @selector(mountPointsChanged:)
               name: GWMountPointsChanged
             object: nil];
    }
  
  return self;    
}

- (BOOL)connection:(NSConnection *)ancestor
            shouldMakeNewConnection:(NSConnection *)newConn;
{
  FSWClientInfo *info = [FSWClientInfo new];
	      
  [info setConnection: newConn];
  [clientsInfo addObject: info];
  RELEASE (info);

  [nc addObserver: self
         selector: @selector(connectionBecameInvalid:)
		           name: NSConnectionDidDieNotification
		         object: newConn];

  return YES;
}

- (void)connectionBecameInvalid:(NSNotification *)notification
{
  id connection = [notification object];
  NSUInteger i;
  
  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *info = [clientsInfo objectAtIndex: i];
    
    if ([info connection] == connection) {
      NSSet *paths = [info watchedPaths];
      NSEnumerator *enumerator = [paths objectEnumerator];
      NSString *path;
      
      while ((path = [enumerator nextObject])) {
        KQueueWatcher *watcher = (KQueueWatcher *)NSMapGet(watchers, path);
        if (watcher) {
          [watcher removeListener];
          if ([watcher listeners] == 0) {
            [self removeWatcher: watcher];
          }
        }
      }
      
      [clientsInfo removeObjectAtIndex: i];
      break;
    }
  }
}

- (void)setDefaultGlobalPaths
{
  NSMutableArray *paths = [NSMutableArray array];
  
  // Add common system paths that should be monitored globally
  [paths addObject: @"/"];
  [paths addObject: @"/usr"];
  [paths addObject: @"/var"];
  [paths addObject: @"/tmp"];
  [paths addObject: @"/home"];
  [paths addObject: @"/mnt"];
  [paths addObject: @"/media"];
  [paths addObject: @"/Volumes"];
  
  for (NSString *path in paths) {
    if ([fm fileExistsAtPath: path]) {
      insertComponentsOfPath(path, includePathsTree);
    }
  }
}

- (void)globalPathsChanged:(NSNotification *)notification
{
  // Handle global path changes if needed
  GWDebugLog(@"[FSWatcher] Global paths changed");
}

- (oneway void)registerClient:(id <FSWClientProtocol>)client
              isGlobalWatcher:(BOOL)global
{
  FSWClientInfo *info = [self clientInfoWithRemote: client];
  
  if (info) {
    [info setClient: client];
    [info setGlobal: global];
    
    GWDebugLog(@"[FSWatcher] Registered client (global: %d)", global);
  }
}

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client
{
  FSWClientInfo *info = [self clientInfoWithRemote: client];
  
  if (info) {
    NSSet *paths = [info watchedPaths];
    NSEnumerator *enumerator = [paths objectEnumerator];
    NSString *path;
    
    while ((path = [enumerator nextObject])) {
      KQueueWatcher *watcher = (KQueueWatcher *)NSMapGet(watchers, path);
      if (watcher) {
        [watcher removeListener];
        if ([watcher listeners] == 0) {
          [self removeWatcher: watcher];
        }
      }
    }
    
    [clientsInfo removeObject: info];
    GWDebugLog(@"[FSWatcher] Unregistered client");
  }
}

- (FSWClientInfo *)clientInfoWithConnection:(NSConnection *)connection
{
  NSUInteger i;
  
  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *info = [clientsInfo objectAtIndex: i];
    
    if ([info connection] == connection) {
      return info;
    }
  }
  
  return nil;
}

- (FSWClientInfo *)clientInfoWithRemote:(id)remote
{
  NSUInteger i;
  
  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *info = [clientsInfo objectAtIndex: i];
    
    if ([info client] == remote) {
      return info;
    }
  }
  
  return nil;
}

- (oneway void)client:(id <FSWClientProtocol>)client
                                addWatcherForPath:(NSString *)path
{
  FSWClientInfo *info = [self clientInfoWithRemote: client];
  
  if (info) {
    KQueueWatcher *watcher = [self watcherForPath: path];
    
    if (watcher == nil) {
      watcher = [[KQueueWatcher alloc] initWithWatchedPath: path
                                                 fswatcher: self];
      NSMapInsert(watchers, path, watcher);
      NSMapInsert(fdToWatcherMap, (void *)(uintptr_t)[watcher fileDescriptor], watcher);
      [watcher startWatching];
      RELEASE (watcher);
    }
    
    [watcher addListener];
    [info addWatchedPath: path];
    
    GWDebugLog(@"[FSWatcher] Added watcher for path: %@", path);
  }
}

- (oneway void)client:(id <FSWClientProtocol>)client
                                removeWatcherForPath:(NSString *)path
{
  FSWClientInfo *info = [self clientInfoWithRemote: client];
  
  if (info) {
    KQueueWatcher *watcher = [self watcherForPath: path];
    
    if (watcher) {
      [watcher removeListener];
      [info removeWatchedPath: path];
      
      if ([watcher listeners] == 0) {
        [self removeWatcher: watcher];
      }
      
      GWDebugLog(@"[FSWatcher] Removed watcher for path: %@", path);
    }
  }
}

- (KQueueWatcher *)watcherForPath:(NSString *)path
{
  return (KQueueWatcher *)NSMapGet(watchers, path);
}

- (void)removeWatcher:(KQueueWatcher *)awatcher
{
  NSString *path = [awatcher watchedPath];
  int fd = [awatcher fileDescriptor];
  
  [awatcher stopWatching];
  
  NSMapRemove(watchers, path);
  if (fd >= 0) {
    NSMapRemove(fdToWatcherMap, (void *)(uintptr_t)fd);
  }
  
  GWDebugLog(@"[FSWatcher] Removed watcher for path: %@", path);
}

- (pcomp *)includePathsTree
{
  return includePathsTree;
}

- (pcomp *)excludePathsTree
{
  return excludePathsTree;
}

- (NSSet *)excludedSuffixes
{
  return excludedSuffixes;
}

- (BOOL)isGlobalValidPath:(NSString *)path
{
  return inTreeFirstPartOfPath(path, includePathsTree);
}

- (void)notifyClients:(NSDictionary *)info
{
  NSString *path = [info objectForKey: @"path"];
  NSData *data = [NSArchiver archivedDataWithRootObject: info];
  NSUInteger i;
  
  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *clientInfo = [clientsInfo objectAtIndex: i];
    
    if ([clientInfo isWatchingPath: path]) {
      NS_DURING
        [[clientInfo client] watchedPathDidChange: data];
      NS_HANDLER
        GWDebugLog(@"[FSWatcher] Exception notifying client: %@", [localException reason]);
      NS_ENDHANDLER
    }
  }
}

- (void)notifyGlobalWatchingClients:(NSDictionary *)info
{
  NSString *path = [info objectForKey: @"path"];
  NSUInteger i;
  
  if ([self isGlobalValidPath: path] == NO) {
    return;
  }
  
  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *clientInfo = [clientsInfo objectAtIndex: i];
    
    if ([clientInfo isGlobal]) {
      NS_DURING
        [[clientInfo client] globalWatchedPathDidChange: info];
      NS_HANDLER
        GWDebugLog(@"[FSWatcher] Exception notifying global client: %@", [localException reason]);
      NS_ENDHANDLER
    }
  }
}

- (void)mountPointsChanged:(NSNotification *)notification
{
  NSDictionary *info = [notification userInfo];
  NSString *action = [info objectForKey: @"action"];
  NSString *path = [info objectForKey: @"path"];
  
  GWDebugLog(@"[FSWatcher] Mount point %@: %@", action, path);
  
  // Create notification info
  NSMutableDictionary *notifyInfo = [NSMutableDictionary dictionary];
  [notifyInfo setObject: path forKey: @"path"];
  [notifyInfo setObject: action forKey: @"event"];
  [notifyInfo setObject: @"mount" forKey: @"type"];
  
  [self notifyGlobalWatchingClients: notifyInfo];
}

@end


@implementation KQueueWatcher

- (void)dealloc
{
  [self stopWatching];
  RELEASE (watchedPath);
  RELEASE (pathContents);
  RELEASE (date);
  RELEASE (timer);
  [super dealloc];
}

- (id)initWithWatchedPath:(NSString *)path
                fswatcher:(FSWatcher *)fsw
{
  self = [super init];
  
  if (self) {
    watchedPath = [path copy];
    fswatcher = fsw;
    fm = [NSFileManager defaultManager];
    
    fd = -1;
    kq = -1;
    listeners = 0;
    isOld = NO;
    watchThread = nil;
    
    BOOL isDirectory;
    if ([fm fileExistsAtPath: watchedPath isDirectory: &isDirectory]) {
      isdir = isDirectory;
    } else {
      isdir = NO;
    }
    
    if (isdir) {
      NSError *error = nil;
      pathContents = [[fm contentsOfDirectoryAtPath: watchedPath error: &error] retain];
      if (error) {
        GWDebugLog(@"[KQueueWatcher] Error reading directory contents: %@", [error localizedDescription]);
        pathContents = [[NSArray alloc] init];
      }
    } else {
      pathContents = [[NSArray alloc] init];
    }
    
    date = [[NSDate alloc] init];
  }
  
  return self;
}

- (void)startWatching
{
  if (fd >= 0) {
    return; // Already watching
  }
  
  fd = open([watchedPath fileSystemRepresentation], O_EVTONLY);
  if (fd < 0) {
    GWDebugLog(@"[KQueueWatcher] Failed to open file descriptor for: %@", watchedPath);
    return;
  }

  kq = kqueue();
  if (kq == -1) {
    GWDebugLog(@"[KQueueWatcher] Failed to create kqueue");
    close(fd);
    fd = -1;
    return;
  }

  struct kevent event;
  EV_SET(&event, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_CLEAR,
         NOTE_WRITE | NOTE_DELETE | NOTE_LINK | NOTE_RENAME, 0, NULL);

  if (kevent(kq, &event, 1, NULL, 0, NULL) == -1) {
    GWDebugLog(@"[KQueueWatcher] Failed to setup kevent for: %@", watchedPath);
    close(kq);
    close(fd);
    fd = -1;
    kq = -1;
    return;
  }

  watchThread = [[NSThread alloc] initWithTarget: self
                                         selector: @selector(watchForChanges)
                                           object: nil];
  [watchThread start];
  
  GWDebugLog(@"[KQueueWatcher] Started watching: %@", watchedPath);
}

- (void)stopWatching
{
  if (watchThread) {
    [watchThread cancel];
    RELEASE (watchThread);
    watchThread = nil;
  }
  
  if (kq >= 0) {
    close(kq);
    kq = -1;
  }
  
  if (fd >= 0) {
    close(fd);
    fd = -1;
  }
  
  if (timer) {
    [timer invalidate];
    RELEASE (timer);
    timer = nil;
  }
}

- (void)watchForChanges
{
  @autoreleasepool {
    struct kevent ev;
    
    while (![watchThread isCancelled]) {
      int nev = kevent(kq, NULL, 0, &ev, 1, NULL);
      
      if (nev > 0 && ev.filter == EVFILT_VNODE) {
        GWDebugLog(@"[KQueueWatcher] Directory changed: %@", watchedPath);
        [self performSelectorOnMainThread: @selector(scanDirectory)
                               withObject: nil
                            waitUntilDone: NO];
      }
    }
  }
}

- (void)scanDirectory
{
  if (isdir) {
    NSError *error = nil;
    NSArray *newContents = [fm contentsOfDirectoryAtPath: watchedPath error: &error];
    
    if (error) {
      GWDebugLog(@"[KQueueWatcher] Error scanning directory: %@", [error localizedDescription]);
      return;
    }
    
    NSMutableSet *oldSet = [NSMutableSet setWithArray: pathContents];
    NSMutableSet *newSet = [NSMutableSet setWithArray: newContents];
    
    // Find added files
    NSMutableSet *added = [newSet mutableCopy];
    [added minusSet: oldSet];
    
    // Find removed files
    NSMutableSet *removed = [oldSet mutableCopy];
    [removed minusSet: newSet];
    
    // Notify about changes
    for (NSString *file in added) {
      NSMutableDictionary *info = [NSMutableDictionary dictionary];
      [info setObject: watchedPath forKey: @"path"];
      [info setObject: file forKey: @"filename"];
      [info setObject: GWFileCreatedInWatchedDirectory forKey: @"event"];
      [fswatcher notifyClients: info];
    }
    
    for (NSString *file in removed) {
      NSMutableDictionary *info = [NSMutableDictionary dictionary];
      [info setObject: watchedPath forKey: @"path"];
      [info setObject: file forKey: @"filename"];
      [info setObject: GWFileDeletedInWatchedDirectory forKey: @"event"];
      [fswatcher notifyClients: info];
    }
    
    [removed release];
    [added release];
    
    // Update cached contents
    RELEASE (pathContents);
    pathContents = [newContents retain];
  } else {
    // File was modified
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject: watchedPath forKey: @"path"];
    [info setObject: GWWatchedFileModified forKey: @"event"];
    [fswatcher notifyClients: info];
  }
}

- (void)addListener
{
  listeners++;
}

- (void)removeListener
{
  listeners--;
  if (listeners < 0) {
    listeners = 0;
  }
}

- (BOOL)isWatchingPath:(NSString *)apath
{
  return [watchedPath isEqualToString: apath];
}

- (NSString *)watchedPath
{
  return watchedPath;
}

- (BOOL)isOld
{
  return isOld;
}

- (NSTimer *)timer
{
  return timer;
}

- (int)fileDescriptor
{
  return fd;
}

- (int)listeners
{
  return listeners;
}

@end


@implementation MountWatcher

- (void)dealloc
{
  [self stopWatching];
  RELEASE (lastMounts);
  [super dealloc];
}

- (id)initWithFSWatcher:(FSWatcher *)fsw
{
  self = [super init];
  
  if (self) {
    fswatcher = fsw;
    lastMounts = [[self currentMountPoints] retain];
    shouldStop = NO;
    watchThread = nil;
  }
  
  return self;
}

- (void)startWatching
{
  if (watchThread) {
    return; // Already watching
  }
  
  shouldStop = NO;
  watchThread = [[NSThread alloc] initWithTarget: self
                                         selector: @selector(pollForMountChanges)
                                           object: nil];
  [watchThread start];
  
  GWDebugLog(@"[MountWatcher] Started watching mount points");
}

- (void)stopWatching
{
  shouldStop = YES;
  
  if (watchThread) {
    [watchThread cancel];
    RELEASE (watchThread);
    watchThread = nil;
  }
}

- (void)pollForMountChanges
{
  @autoreleasepool {
    while (!shouldStop && ![watchThread isCancelled]) {
      [NSThread sleepForTimeInterval: 2.0];
      
      if (shouldStop || [watchThread isCancelled]) {
        break;
      }
      
      [self checkMountChanges];
    }
  }
}

- (void)checkMountChanges
{
  NSArray *current = [self currentMountPoints];
  NSSet *prevSet = [NSSet setWithArray: lastMounts];
  NSSet *currSet = [NSSet setWithArray: current];

  NSMutableSet *added = [currSet mutableCopy];
  [added minusSet: prevSet];

  NSMutableSet *removed = [prevSet mutableCopy];
  [removed minusSet: currSet];

  for (NSString *mnt in added) {
    GWDebugLog(@"[MountWatcher] Mounted: %@", mnt);
    
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"mounted", @"action",
                         mnt, @"path",
                         nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName: GWMountPointsChanged
                                                        object: self
                                                      userInfo: info];
  }

  for (NSString *mnt in removed) {
    GWDebugLog(@"[MountWatcher] Unmounted: %@", mnt);
    
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"unmounted", @"action",
                         mnt, @"path",
                         nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName: GWMountPointsChanged
                                                        object: self
                                                      userInfo: info];
  }

  [removed release];
  [added release];
  
  RELEASE (lastMounts);
  lastMounts = [current retain];
}

- (NSArray *)currentMountPoints
{
  struct statfs *mntbuf;
  int count = getmntinfo(&mntbuf, MNT_WAIT);
  NSMutableArray *mounts = [NSMutableArray array];
  
  for (int i = 0; i < count; ++i) {
    NSString *mountPoint = [NSString stringWithUTF8String: mntbuf[i].f_mntonname];
    [mounts addObject: mountPoint];
  }
  
  return mounts;
}

@end


int main(int argc, char** argv)
{
  NSAutoreleasePool *pool;
  FSWatcher *fswatcher;
  NSRunLoop *runLoop;
  BOOL shouldKeepRunning = YES;
  
  pool = [[NSAutoreleasePool alloc] init];
  
  fswatcher = [[FSWatcher alloc] init];
  if (fswatcher == nil) {
    [pool release];
    exit(EXIT_FAILURE);
  }
  
  runLoop = [NSRunLoop currentRunLoop];
  
  while (shouldKeepRunning && [runLoop runMode: NSDefaultRunLoopMode 
                                    beforeDate: [NSDate distantFuture]]) {
    // Keep the run loop running
  }
  
  RELEASE (fswatcher);
  [pool release];
  
  return 0;
}
