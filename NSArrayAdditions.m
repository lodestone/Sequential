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
#import "NSArrayAdditions.h"

// Categories
#import "NSObjectAdditions.h"

@implementation NSArray (AEAdditions)

#pragma mark +NSArray(AEAdditions)

+ (id)AE_arrayWithContentsOfArrays:(NSArray *)first, ...
{
	if(!first) return [self array];
	NSMutableArray *const result = [[first mutableCopy] autorelease];
	NSArray *array;
	va_list list;
	va_start(list, first);
	while((array = va_arg(list, NSArray *))) [result addObjectsFromArray:array];
	va_end(list);
	return result;
}

#pragma mark -NSArray(AEAdditions)

- (NSArray *)AE_arrayWithUniqueObjects
{
	NSMutableArray *const array = [[self mutableCopy] autorelease];
	unsigned i = 0, count;
	for(; i < (count = [array count]); i++) [array removeObject:[array objectAtIndex:i] inRange:NSMakeRange(i + 1, count - i - 1)];
	return array;
}
- (void)AE_addObjectObserver:(id)observer
        selector:(SEL)aSelector
        name:(NSString *)aName
{
	id obj;
	NSEnumerator *const objEnum = [self objectEnumerator];
	while((obj = [objEnum nextObject])) [obj AE_addObserver:observer selector:aSelector name:aName];
}
- (void)AE_removeObjectObserver:(id)observer
        name:(NSString *)aName
{
	id obj;
	NSEnumerator *const objEnum = [self objectEnumerator];
	while((obj = [objEnum nextObject])) [obj AE_removeObserver:observer name:aName];
}

@end
