/* fswatcher-kqueue.h
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

#ifndef FSWATCHER_KQUEUE_H
#define FSWATCHER_KQUEUE_H

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <unistd.h>
#import <Foundation/Foundation.h>
#include "DBKPathsTree.h"

#ifndef O_EVTONLY
#define O_EVTONLY O_RDONLY
#endif

@class KQueueWatcher;
@class MountWatcher;

@protocol	FSWClientProtocol <NSObject>

- (oneway void)watchedPathDidChange:(NSData *)dirinfo;

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo;

@end


@protocol	FSWatcherProtocol

- (oneway void)registerClient:(id <FSWClientProtocol>)client
              isGlobalWatcher:(BOOL)global;

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client;

- (oneway void)client:(id <FSWClientProtocol>)client
                          addWatcherForPath:(NSString *)path;

- (oneway void)client:(id <FSWClientProtocol>)client
                          removeWatcherForPath:(NSString *)path;

@end

@interface FSWClientInfo: NSObject 
{
  NSConnection *conn;
  id <FSWClientProtocol> client;
  NSCountedSet *wpaths;
  BOOL global;
}

- (void)setConnection:(NSConnection *)connection;

- (NSConnection *)connection;

- (void)setClient:(id <FSWClientProtocol>)clnt;

- (id <FSWClientProtocol>)client;

- (void)addWatchedPath:(NSString *)path;

- (void)removeWatchedPath:(NSString *)path;

- (BOOL)isWatchingPath:(NSString *)path;

- (NSSet *)watchedPaths;

- (void)setGlobal:(BOOL)value;

- (BOOL)isGlobal;

@end


@interface FSWatcher: NSObject 
{
  NSConnection *conn;
  NSMutableArray *clientsInfo;  
  NSMapTable *watchers;
  NSMapTable *fdToWatcherMap;
  
  MountWatcher *mountWatcher;
  
  pcomp *includePathsTree;
  pcomp *excludePathsTree;
  NSMutableSet *excludedSuffixes;
    
  NSFileManager *fm;
  NSNotificationCenter *nc; 
  NSNotificationCenter *dnc;
}

- (BOOL)connection:(NSConnection *)ancestor
            shouldMakeNewConnection:(NSConnection *)newConn;

- (void)connectionBecameInvalid:(NSNotification *)notification;

- (void)setDefaultGlobalPaths;

- (void)globalPathsChanged:(NSNotification *)notification;

- (oneway void)registerClient:(id <FSWClientProtocol>)client
              isGlobalWatcher:(BOOL)global;

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client;

- (FSWClientInfo *)clientInfoWithConnection:(NSConnection *)connection;

- (FSWClientInfo *)clientInfoWithRemote:(id)remote;

- (oneway void)client:(id <FSWClientProtocol>)client
                                addWatcherForPath:(NSString *)path;

- (oneway void)client:(id <FSWClientProtocol>)client
                                removeWatcherForPath:(NSString *)path;

- (KQueueWatcher *)watcherForPath:(NSString *)path;

- (void)removeWatcher:(KQueueWatcher *)awatcher;

- (pcomp *)includePathsTree;

- (pcomp *)excludePathsTree;

- (NSSet *)excludedSuffixes;

- (BOOL)isGlobalValidPath:(NSString *)path;

- (void)notifyClients:(NSDictionary *)info;

- (void)notifyGlobalWatchingClients:(NSDictionary *)info;

- (void)mountPointsChanged:(NSNotification *)notification;

@end


@interface KQueueWatcher: NSObject
{
  NSString *watchedPath;
  int fd;
  int kq;
  BOOL isdir;
  NSArray *pathContents;
  int listeners;
  NSDate *date;
  BOOL isOld;
  NSFileManager *fm;
  FSWatcher *fswatcher;
  NSTimer *timer;
  NSThread *watchThread;
}

- (id)initWithWatchedPath:(NSString *)path
                fswatcher:(FSWatcher *)fsw;

- (void)startWatching;

- (void)stopWatching;

- (void)watchForChanges;

- (void)addListener;

- (void)removeListener;

- (BOOL)isWatchingPath:(NSString *)apath;

- (NSString *)watchedPath;

- (BOOL)isOld;

- (NSTimer *)timer;

- (int)fileDescriptor;

- (int)listeners;

@end


@interface MountWatcher: NSObject
{
  NSArray *lastMounts;
  FSWatcher *fswatcher;
  NSThread *watchThread;
  BOOL shouldStop;
}

- (id)initWithFSWatcher:(FSWatcher *)fsw;

- (void)startWatching;

- (void)stopWatching;

- (void)pollForMountChanges;

- (NSArray *)currentMountPoints;

@end


#endif // FSWATCHER_KQUEUE_H
