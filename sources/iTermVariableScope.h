//
//  iTermVariableScope.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Foundation/Foundation.h>

#import "iTermTuple.h"
#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableRecordingScope;
@class iTermVariables;
@class iTermVariableReference;

// This has a tuple of (iTermVariables, terminal path name). It compares equal to other designators
// that refer to the same variable. The variable must be set to be designated.
@interface iTermVariableDesignator : NSObject<NSCopying>
@end

// Provides access to  the variables that are visible from a particular callsite. Each
// set of variables except one (that of the most local scope) must have a name.
// Variables are searched for one matching the name. You could get and set variables through
// this object. If you want to get called back when a value changes, use iTermVariableReference.
@interface iTermVariableScope : NSObject<NSCopying, iTermVariableVendor>

@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *dictionaryWithStringValues;
@property (nonatomic) BOOL neverReturnNil;
@property (nonatomic, readonly) BOOL usePlaceholders;
@property (nonatomic, readonly) NSArray<iTermTuple<NSString *, iTermVariables *> *> *frames;

- (iTermVariableRecordingScope *)recordingCopy;

- (void)addVariables:(iTermVariables *)variables toScopeNamed:(nullable NSString *)scopeName;
- (id)valueForVariableName:(NSString *)name;
- (id)valueForPath:(NSString *)firstName, ... NS_REQUIRES_NIL_TERMINATION;

- (NSString *)stringValueForVariableName:(NSString *)name;
// Values of NSNull get unset
- (void)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict;

// nil or NSNull value means unset it.
// Returns whether it was set. If the value is unchanged, it does not get set.
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name;
- (BOOL)setValue:(nullable id)value forPath:(NSString *)firstName, ... NS_REQUIRES_NIL_TERMINATION;

// Set weak to YES when a strong reference to value should not be kept.
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name weak:(BOOL)weak;

// Freaking KVO crap keeps autocompleting and causing havoc
- (void)setValue:(nullable id)value forKey:(NSString *)key NS_UNAVAILABLE;
- (void)setValuesForKeysWithDictionary:(NSDictionary<NSString *, id> *)keyedValues NS_UNAVAILABLE;
- (void)addLinksToReference:(iTermVariableReference *)reference;
- (BOOL)variableNamed:(NSString *)name isReferencedBy:(iTermVariableReference *)reference;

// Don't use this unless you know what you're doing.
// It does not attempt to resolve dangling references and should not be long-lived.
- (iTermVariableScope *)unsafeCheapCopy;
- (NSArray<iTermVariables *> *)variablesInScopeNamed:(nullable NSString *)scopeName;

- (iTermVariableDesignator *)designatorForPath:(NSString *)path;

@end

// A scope that remembers which variables were referred to.
@interface iTermVariableRecordingScope : iTermVariableScope
@property (nonatomic, readonly) NSArray<iTermVariableReference *> *recordedReferences;

- (instancetype)initWithScope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// A scope that causes parsed expressions to record variable references rather than expand them to
// values.
@interface iTermVariablePlaceholderScope : iTermVariableScope
@end

NS_ASSUME_NONNULL_END
