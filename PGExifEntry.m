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
#import "PGExifEntry.h"

// Categories
#import "PGFoundationAdditions.h"

// External
#import "exif.h"

enum {
	PGExifOrientationTag = 0x0112,
};

@implementation PGExifEntry

#pragma mark +PGExifEntry

+ (NSData *)exifDataWithImageData:(NSData *)data
{
	if([data length] < 2 || 0xFFD8 != CFSwapInt16BigToHost(*(uint16_t *)[data bytes])) return nil;
	NSUInteger offset = 2;
	while(offset + 18 < [data length]) {
		void const *const bytes = [data bytes] + offset;
		uint16_t const type = CFSwapInt16BigToHost(*(uint16_t *)(bytes + 0));
		if(0xFFDA == type) break;
		uint16_t const size = CFSwapInt16BigToHost(*(uint16_t *)(bytes + 2));
		if(0xFFE1 != type) {
			offset += 2 + size;
			continue;
		}
		if(size < 18) break;
		if(0x45786966 != CFSwapInt32BigToHost(*(uint32_t *)(bytes + 4))) break;
		if(0 != *(uint16_t *)(bytes + 8)) break;
		return [data subdataWithRange:NSMakeRange(offset + 4, size - 2)];
	}
	return nil;
}
+ (void)getEntries:(out NSArray **)outEntries orientation:(out PGOrientation *)outOrientation forImageData:(NSData *)data
{
	NSData *const exifData = [self exifDataWithImageData:data];
	struct exiftags *const tags = exifData ? exifparse((unsigned char *)[exifData bytes], [exifData length]) : NULL;
	if(!tags) {
		if(outEntries) *outEntries = [NSArray array];
		if(outOrientation) *outOrientation = PGUpright;
		return;
	}

	NSMutableArray *const entries = [NSMutableArray array];
	PGOrientation orientation = PGUpright;
	struct exifprop *entry = tags->props;
	for(; entry; entry = entry->next) {
		if(entry->lvl != ED_CAM && entry->lvl != ED_IMG) continue;
		if(PGExifOrientationTag == entry->tag && !PGIsSnowLeopardOrLater()) switch(entry->value) {
			case 2: orientation = PGFlippedHorz; break;
			case 3: orientation = PGUpsideDown; break;
			case 4: orientation = PGFlippedVert; break;
			case 5: orientation = PGRotated90CC | PGFlippedHorz; break;
			case 6: orientation = PGRotated270CC; break;
			case 7: orientation = PGRotated90CC | PGFlippedVert; break;
			case 8: orientation = PGRotated90CC; break;
		}
		[entries addObject:[[[self alloc] initWithLabel:[NSString stringWithUTF8String:entry->descr ? entry->descr : entry->name] value:entry->str ? [NSString stringWithUTF8String:entry->str] : [NSString stringWithFormat:@"%u", entry->value]] autorelease]];
	}

	exiffree(tags);
	if(outEntries) *outEntries = [entries sortedArrayUsingSelector:@selector(compare:)];
	if(outOrientation) *outOrientation = orientation;
}

#pragma mark -PGExifEntry

- (id)initWithLabel:(NSString *)label value:(NSString *)value
{
	if((self = [super init])) {
		_label = [label copy];
		_value = [value copy];
	}
	return self;
}

#pragma mark -

@synthesize label = _label;
@synthesize value = _value;

#pragma mark -

- (NSComparisonResult)compare:(PGExifEntry *)anEntry
{
	return [[self label] compare:[anEntry label] options:NSCaseInsensitiveSearch | NSNumericSearch];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_label release];
	[_value release];
	[super dealloc];
}

@end
