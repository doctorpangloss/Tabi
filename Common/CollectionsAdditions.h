// Contains code that is copyright Jens Alfke:
// https://bitbucket.org/snej/myutilities/src/tip/CollectionUtils.h
//
// Contains code created by Michael Ash
// http://www.mikeash.com/pyblog/friday-qa-2009-08-14-practical-blocks.html

#import <Foundation/Foundation.h>

typedef NSComparisonResult(^ComparatorBlock)(id, id);

#define $arr(OBJS...) ({id objs[]={OBJS}; \
    [NSArray arrayWithObjects:objs count:sizeof(objs)/sizeof(id)];})
#define $marr(OBJS...) ({id objs[]={OBJS}; \
    [NSMutableArray arrayWithObjects:objs count:sizeof(objs)/sizeof(id)];})

#define $dict(PAIRS...) ({struct _dictpair pairs[] = {PAIRS}; \
    _dictof(pairs,sizeof(pairs)/sizeof(struct _dictpair));})
#define $mdict(PAIRS...) ({struct _dictpair pairs[] = {PAIRS}; \
    _mdictof(pairs,sizeof(pairs)/sizeof(struct _dictpair));}) 

struct _dictpair { id key; id value; };
NSDictionary* _dictof(const struct _dictpair*, size_t count);
NSMutableDictionary* _mdictof(const struct _dictpair*, size_t count);

@interface NSArray (CollectionsAdditions)

+ (NSArray *)arrayForRange:(NSRange)range;
- (void)forEachDo:(void(^)(id obj, NSUInteger idx))block;
- (NSArray *)grep:(BOOL(^)(id obj))block;
- (id)first:(BOOL(^)(id obj))block;
- (NSArray *)map:(id(^)(id obj))block;
- (NSArray *)sort:(ComparatorBlock)block;
- (NSDictionary *)dictionary:(void(^)(NSMutableDictionary *acc, id arrayElement))block;

@end

@interface NSSet (CollectionsAdditions)

- (void)forEachDo:(void(^)(id obj))block;
- (NSArray *)grep:(BOOL(^)(id obj))block;
- (NSArray *)map:(id(^)(id obj))block;

@end
