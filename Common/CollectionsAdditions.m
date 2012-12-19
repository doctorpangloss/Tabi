// Contains code that is copyright Jens Alfke:
// https://bitbucket.org/snej/myutilities/src/tip/CollectionUtils.h
//
// Contains code created by Michael Ash
// http://www.mikeash.com/pyblog/friday-qa-2009-08-14-practical-blocks.html

#import "CollectionsAdditions.h"

NSDictionary* _dictof(const struct _dictpair* pairs, size_t count) {
    id objects[count];
    id keys[count];
    size_t n = 0;
    for (size_t i = 0; i < count; i++, pairs++) {
        if (pairs->value) {
            objects[n] = pairs->value;
            keys[n] = pairs->key;
            n++;
        }
    }
    return [NSDictionary dictionaryWithObjects:objects forKeys:keys count:n];
}


NSMutableDictionary* _mdictof(const struct _dictpair* pairs, size_t count) {
    id objects[count];
    id keys[count];
    size_t n = 0;
    for (size_t i = 0; i < count; i++, pairs++) {
        if (pairs->value) {
            objects[n] = pairs->value;
            keys[n] = pairs->key;
            n++;
        }
    }
    return [NSMutableDictionary dictionaryWithObjects:objects forKeys:keys count:n];
}


@implementation NSArray (CollectionsAdditions)

+ (NSArray *)arrayForRange:(NSRange)range {
    NSMutableArray *arr = [NSMutableArray array];
    for (int i = range.location; i <= range.length; i++) {
        [arr addObject:[NSNumber numberWithInt:i]];
    }
    return arr;
}

- (void)forEachDo:(void(^)(id obj, NSUInteger idx))block {
    for (int i = 0; i < [self count]; i++) {
        block([self objectAtIndex:i], i);
    }
}

- (id)first:(BOOL(^)(id obj))block {
    for (id obj in self) {
        if (block(obj)) {
            return obj;
        }
    }
    
    return nil;
}

- (NSArray *)grep:(BOOL(^)(id obj))block {
    NSMutableArray *arr = [NSMutableArray array];
    [self forEachDo:[[^(id obj) {
        if (block(obj)) {
            [arr addObject:obj];
        }
    } copy] autorelease]];
    
    return arr;
}

- (NSArray *)map:(id(^)(id obj))block {
    NSMutableArray *arr = [NSMutableArray array];
    [self forEachDo:[[^(id obj) {
        id mappedObj = block(obj);
//        [arr addObject:(nil != mappedObj ? mappedObj : [NSNull null])];
        if (nil != mappedObj) {
            [arr addObject:mappedObj];
        }
    } copy] autorelease]];
    return arr;
}

NSInteger sorterFunc(id left, id right, void *context) {
    return ((ComparatorBlock)context)(left, right);
}

- (NSArray *)sort:(ComparatorBlock)block {
    return [self sortedArrayUsingFunction:sorterFunc context:block];
}

- (NSDictionary *)dictionary:(void(^)(NSMutableDictionary *acc, id arrayElement))block {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self forEachDo:^(id el, NSUInteger idx) {
        block(dict, el);
    }];
    return dict;
}

@end

@implementation NSSet (CollectionsAdditions)

- (void)forEachDo:(void(^)(id obj))block {
    for (id obj in self) {
        block(obj);
    }
}

- (NSArray *)grep:(BOOL(^)(id obj))block {
    NSMutableArray *arr = [NSMutableArray array];
    [self forEachDo:[[^(id obj) {
        if (block(obj)) {
            [arr addObject:obj];
        }
    } copy] autorelease]];
    
    return arr;
}

- (NSArray *)map:(id(^)(id obj))block {
    NSMutableArray *arr = [NSMutableArray array];
    [self forEachDo:[[^(id obj) {
        id mappedObj = block(obj);
//        [arr addObject:(nil != mappedObj ? mappedObj : [NSNull null])];
        if (nil != mappedObj) {
            [arr addObject:mappedObj];
        }
    } copy] autorelease]];
    return arr;
}


@end
