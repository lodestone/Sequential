/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGDocument.h"

// Models
#import "PGNode.h"
#import "PGGenericImageAdapter.h"
#import "PGResourceIdentifier.h"
#import "PGSubscription.h"
#import "PGBookmark.h"

// Views
#import "PGImageView.h"

// Controllers
#import "PGDocumentController.h"
#import "PGBookmarkController.h"
#import "PGDisplayController.h"

// Other
#import "PGGeometry.h"

// Categories
#import "PGFoundationAdditions.h"

NSString *const PGDocumentWillRemoveNodesNotification          = @"PGDocumentWillRemoveNodes";
NSString *const PGDocumentSortedNodesDidChangeNotification     = @"PGDocumentSortedNodesDidChange";
NSString *const PGDocumentNodeIsViewableDidChangeNotification  = @"PGDocumentNodeIsViewableDidChange";
NSString *const PGDocumentNodeThumbnailDidChangeNotification   = @"PGDocumentNodeThumbnailDidChange";
NSString *const PGDocumentNodeDisplayNameDidChangeNotification = @"PGDocumentNodeDisplayNameDidChange";
NSString *const PGDocumentBaseOrientationDidChangeNotification = @"PGDocumentBaseOrientationDidChange";

NSString *const PGDocumentNodeKey = @"PGDocumentNode";
NSString *const PGDocumentRemovedChildrenKey = @"PGDocumentRemovedChildren";
NSString *const PGDocumentUpdateRecursivelyKey = @"PGDocumentUpdateRecursively";

#define PGDocumentMaxCachedNodes 3

@interface PGDocument(Private)

- (PGNode *)_initialNode;
- (void)_setInitialIdentifier:(PGResourceIdentifier *)ident;

@end

@implementation PGDocument

#pragma mark -PGDocument

- (id)initWithIdentifier:(PGDisplayableIdentifier *)ident
{
	if((self = [self init])) {
		_originalIdentifier = [ident retain];
		[_originalIdentifier updateNaturalDisplayName]; // It may be old.
		_node = [[PGNode alloc] initWithParentAdapter:nil document:self identifier:ident dataSource:nil];
		[_node startLoadWithInfo:nil];
		PGDisplayableIdentifier *rootIdentifier = ident;
		if([_originalIdentifier isFileIdentifier] && [[_node resourceAdapter] isKindOfClass:[PGGenericImageAdapter class]]) {
			[_node release];
			_node = nil; // Nodes check to see if they already exist, so make sure it doesn't.
			rootIdentifier = [[[[[ident URL] path] stringByDeletingLastPathComponent] PG_fileURL] PG_displayableIdentifier];
			_node = [[PGNode alloc] initWithParentAdapter:nil document:self identifier:rootIdentifier dataSource:nil];
			[_node startLoadWithInfo:nil];
			[self _setInitialIdentifier:ident];
		}
		[_originalIdentifier PG_addObserver:self selector:@selector(identifierIconDidChange:) name:PGDisplayableIdentifierIconDidChangeNotification];
		_subscription = [[rootIdentifier subscriptionWithDescendents:YES] retain];
		[_subscription PG_addObserver:self selector:@selector(subscriptionEventDidOccur:) name:PGSubscriptionEventDidOccurNotification];
		[self noteSortedChildrenDidChange];
	}
	return self;
}
- (id)initWithURL:(NSURL *)aURL
{
	return [self initWithIdentifier:[aURL PG_displayableIdentifier]];
}
- (id)initWithBookmark:(PGBookmark *)aBookmark
{
	if((self = [self initWithIdentifier:[aBookmark documentIdentifier]])) {
		[self openBookmark:aBookmark];
	}
	return self;
}

#pragma mark -

- (PGDisplayableIdentifier *)originalIdentifier
{
	return [[_originalIdentifier retain] autorelease];
}
- (PGDisplayableIdentifier *)rootIdentifier
{
	return [[self node] identifier];
}
- (PGNode *)node
{
	return [[_node retain] autorelease];
}
- (PGDisplayController *)displayController
{
	return [[_displayController retain] autorelease];
}
- (void)setDisplayController:(PGDisplayController *)controller
{
	if(controller == _displayController) return;
	[_displayController setActiveDocument:nil closeIfAppropriate:YES];
	[_displayController release];
	_displayController = [controller retain];
	[_displayController setActiveDocument:self closeIfAppropriate:NO];
	[_displayController synchronizeWindowTitleWithDocumentName];
}
- (BOOL)displayControllerIsModal
{
	return [[self displayController] activeDocument] == self && [[[self displayController] window] attachedSheet];
}
- (BOOL)isOnline
{
	return ![[self rootIdentifier] isFileIdentifier];
}
- (NSMenu *)pageMenu
{
	return _pageMenu;
}
- (PGOrientation)baseOrientation
{
	return _baseOrientation;
}
- (void)setBaseOrientation:(PGOrientation)anOrientation
{
	if(anOrientation == _baseOrientation) return;
	_baseOrientation = anOrientation;
	[self PG_postNotificationName:PGDocumentBaseOrientationDidChangeNotification];
}
- (BOOL)isProcessingNodes
{
	return _processingNodeCount > 0;
}
- (void)setProcessingNodes:(BOOL)flag
{
	NSParameterAssert(flag || _processingNodeCount);
	_processingNodeCount += flag ? 1 : -1;
	if(!_processingNodeCount && _sortedChildrenChanged) [self noteSortedChildrenDidChange];
}

#pragma mark -

- (void)getStoredNode:(out PGNode **)outNode imageView:(out PGImageView **)outImageView offset:(out NSSize *)outOffset query:(out NSString **)outQuery
{
	if(_storedNode) {
		*outNode = [_storedNode autorelease];
		_storedNode = nil;
		*outImageView = [_storedImageView autorelease];
		_storedImageView = nil;
		*outOffset = _storedOffset;
		*outQuery = [_storedQuery autorelease];
		_storedQuery = nil;
	} else {
		*outNode = [self _initialNode];
		*outImageView = [[[PGImageView alloc] init] autorelease];
		*outQuery = @"";
	}
}
- (void)storeNode:(PGNode *)node imageView:(PGImageView *)imageView offset:(NSSize)offset query:(NSString *)query
{
	[_storedNode autorelease];
	_storedNode = [node retain];
	[_storedImageView autorelease];
	_storedImageView = [imageView retain];
	_storedOffset = offset;
	[_storedQuery autorelease];
	_storedQuery = [query copy];
}

- (BOOL)getStoredWindowFrame:(out NSRect *)outFrame
{
	if(NSEqualRects(_storedFrame, NSZeroRect)) return NO;
	if(outFrame) *outFrame = _storedFrame;
	_storedFrame = NSZeroRect;
	return YES;
}
- (void)storeWindowFrame:(NSRect)frame
{
	NSParameterAssert(!NSEqualRects(frame, NSZeroRect));
	_storedFrame = frame;
}

#pragma mark -

- (void)createUI
{
	BOOL const new = ![self displayController];
	if(new) [self setDisplayController:[[PGDocumentController sharedDocumentController] displayControllerForNewDocument]];
	[[PGDocumentController sharedDocumentController] noteNewRecentDocument:self];
	[[self displayController] showWindow:self];
	if(new && !_openedBookmark) {
		PGBookmark *const bookmark = [[PGBookmarkController sharedBookmarkController] bookmarkForIdentifier:[self originalIdentifier]];
		if(bookmark && [[self node] nodeForIdentifier:[bookmark fileIdentifier]]) [[self displayController] offerToOpenBookmark:bookmark];
	}
}
- (void)close
{
	[[PGDocumentController sharedDocumentController] noteNewRecentDocument:self];
	[self setDisplayController:nil];
	[[PGDocumentController sharedDocumentController] removeDocument:self];
}
- (void)openBookmark:(PGBookmark *)aBookmark
{
	[self _setInitialIdentifier:[aBookmark fileIdentifier]];
	PGNode *const initialNode = [self _initialNode];
	if([[initialNode identifier] isEqual:[aBookmark fileIdentifier]]) {
		_openedBookmark = YES;
		[[self displayController] activateNode:initialNode];
		[[PGBookmarkController sharedBookmarkController] removeBookmark:aBookmark];
	} else NSBeep();
}

#pragma mark -

- (void)noteNode:(PGNode *)node willRemoveNodes:(NSArray *)anArray
{
	PGNode *newStoredNode = [_storedNode sortedViewableNodeNext:YES afterRemovalOfChildren:anArray fromNode:node];
	if(!newStoredNode) newStoredNode = [_storedNode sortedViewableNodeNext:NO afterRemovalOfChildren:anArray fromNode:node];
	if(_storedNode != newStoredNode) {
		[_storedNode release];
		_storedNode = [newStoredNode retain];
		_storedOffset = PGRectEdgeMaskToSizeWithMagnitude(PGReadingDirectionAndLocationToRectEdgeMask([self readingDirection], PGHomeLocation), CGFLOAT_MAX);
	}
	[self PG_postNotificationName:PGDocumentWillRemoveNodesNotification userInfo:[NSDictionary dictionaryWithObjectsAndKeys:node, PGDocumentNodeKey, anArray, PGDocumentRemovedChildrenKey, nil]];
}
- (void)noteSortedChildrenDidChange
{
	if([self isProcessingNodes]) {
		_sortedChildrenChanged = YES;
		return;
	}
	NSInteger const numberOfOtherItems = [[[PGDocumentController sharedDocumentController] defaultPageMenu] numberOfItems] + 1;
	if([_pageMenu numberOfItems] < numberOfOtherItems) [_pageMenu addItem:[NSMenuItem separatorItem]];
	while([_pageMenu numberOfItems] > numberOfOtherItems) [_pageMenu removeItemAtIndex:numberOfOtherItems];
	[[self node] addMenuItemsToMenu:_pageMenu];
	if([_pageMenu numberOfItems] == numberOfOtherItems) [_pageMenu removeItemAtIndex:numberOfOtherItems - 1];
	[self PG_postNotificationName:PGDocumentSortedNodesDidChangeNotification];
}
- (void)noteNodeIsViewableDidChange:(PGNode *)node
{
	if(_node) [self PG_postNotificationName:PGDocumentNodeIsViewableDidChangeNotification userInfo:[NSDictionary dictionaryWithObject:node forKey:PGDocumentNodeKey]];
}
- (void)noteNodeThumbnailDidChange:(PGNode *)node recursively:(BOOL)flag
{
	if(node) [self PG_postNotificationName:PGDocumentNodeThumbnailDidChangeNotification userInfo:[NSDictionary dictionaryWithObjectsAndKeys:node, PGDocumentNodeKey, [NSNumber numberWithBool:flag], PGDocumentUpdateRecursivelyKey, nil]];
}
- (void)noteNodeDisplayNameDidChange:(PGNode *)node
{
	if(!_node) return;
	if([self node] == node) [[self displayController] synchronizeWindowTitleWithDocumentName];
	[self PG_postNotificationName:PGDocumentNodeDisplayNameDidChangeNotification userInfo:[NSDictionary dictionaryWithObject:node forKey:PGDocumentNodeKey]];
}
- (void)noteNodeDidCache:(PGNode *)node
{
	if(!_node) return;
	[_cachedNodes removeObjectIdenticalTo:node];
	[_cachedNodes insertObject:node atIndex:0];
	while([_cachedNodes count] > PGDocumentMaxCachedNodes) {
		[[_cachedNodes lastObject] clearCache];
		[_cachedNodes removeLastObject];
	}
}

#pragma mark -

- (void)identifierIconDidChange:(NSNotification *)aNotif
{
	[[self displayController] synchronizeWindowTitleWithDocumentName];
}
- (void)subscriptionEventDidOccur:(NSNotification *)aNotif
{
	NSParameterAssert(aNotif);
	NSUInteger const flags = [[[aNotif userInfo] objectForKey:PGSubscriptionRootFlagsKey] unsignedIntegerValue];
	if(flags & (NOTE_DELETE | NOTE_REVOKE)) return [self close];
	PGResourceIdentifier *const ident = [[[[aNotif userInfo] objectForKey:PGSubscriptionPathKey] PG_fileURL] PG_resourceIdentifier];
	[[[self node] nodeForIdentifier:ident] noteFileEventDidOccurDirect:YES];
}

#pragma mark -PGDocument(Private)

- (PGNode *)_initialNode
{
	PGNode *const node = [[self node] nodeForIdentifier:_initialIdentifier];
	return node ? node : [[self node] sortedViewableNodeFirst:YES];
}
- (void)_setInitialIdentifier:(PGResourceIdentifier *)ident
{
	if(ident == _initialIdentifier) return;
	[_initialIdentifier release];
	_initialIdentifier = [ident retain];
}

#pragma mark -PGPrefObject

- (void)setShowsInfo:(BOOL)flag
{
	[super setShowsInfo:flag];
	[[PGPrefObject globalPrefObject] setShowsInfo:flag];
}
- (void)setShowsThumbnails:(BOOL)flag
{
	[super setShowsThumbnails:flag];
	[[PGPrefObject globalPrefObject] setShowsThumbnails:flag];
}
- (void)setReadingDirection:(PGReadingDirection)aDirection
{
	[super setReadingDirection:aDirection];
	[[PGPrefObject globalPrefObject] setReadingDirection:aDirection];
}
- (void)setImageScaleMode:(PGImageScaleMode)aMode
{
	[super setImageScaleMode:aMode];
	[[PGPrefObject globalPrefObject] setImageScaleMode:aMode];
}
- (void)setImageScaleFactor:(CGFloat)factor animate:(BOOL)flag
{
	[super setImageScaleFactor:factor animate:flag];
	[[PGPrefObject globalPrefObject] setImageScaleFactor:factor animate:flag];
}
- (void)setImageScaleConstraint:(PGImageScaleConstraint)constraint
{
	[super setImageScaleConstraint:constraint];
	[[PGPrefObject globalPrefObject] setImageScaleConstraint:constraint];
}
- (void)setAnimatesImages:(BOOL)flag
{
	[super setAnimatesImages:flag];
	[[PGPrefObject globalPrefObject] setAnimatesImages:flag];
}
- (void)setSortOrder:(PGSortOrder)anOrder
{
	if([self sortOrder] != anOrder) {
		[super setSortOrder:anOrder];
		[[self node] noteSortOrderDidChange];
		[self noteSortedChildrenDidChange];
	}
	[[PGPrefObject globalPrefObject] setSortOrder:anOrder];
}
- (void)setTimerInterval:(NSTimeInterval)interval
{
	[super setTimerInterval:interval];
	[[PGPrefObject globalPrefObject] setTimerInterval:interval];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_pageMenu = [[[PGDocumentController sharedDocumentController] defaultPageMenu] copy];
		[_pageMenu addItem:[NSMenuItem separatorItem]];
		_cachedNodes = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[self PG_removeObserver];
	[_node cancelLoad];
	[_node detachFromTree];
	[_originalIdentifier release];
	[_node release];
	[_subscription release];
	[_cachedNodes release]; // Don't worry about sending -clearCache to each node because the ones that don't get deallocated with us are in active use by somebody else.
	[_storedNode release];
	[_storedImageView release];
	[_storedQuery release];
	[_initialIdentifier release];
	[_displayController release];
	[_pageMenu release];
	[super dealloc];
}

@end
