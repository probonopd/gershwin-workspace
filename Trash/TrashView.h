/* TrashView.h
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: June 2004
 *
 * This file is part of the GNUstep Trash application
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

#import <AppKit/NSView.h>
#import "Trash.h"
#import "FSNodeRep.h"

@class NSImage;
@class TrashIcon;

@interface TrashWindow : NSWindow 
{
  id icon;
}

- (void)setTrashIcon:(id)icn;

@end

@interface TrashView : NSView
{
  TrashWindow *win;
  TrashIcon *icon;
  NSImage *tile;
  Trash *trash;  
}

- (id)initWithWindow;

- (void)activate;

- (TrashIcon *)trashIcon;

- (void)updateDefaults;

@end


@interface TrashView (NodeRepContainer)

- (void)nodeContentsDidChange:(NSDictionary *)info;

- (void)watchedPathChanged:(NSDictionary *)info;

- (FSNSelectionMask)selectionMask;

- (BOOL)validatePasteOfFilenames:(NSArray *)names
                       wasCut:(BOOL)cut;

- (NSColor *)backgroundColor;

- (NSColor *)textColor;

- (NSColor *)disabledTextColor;

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;

@end

