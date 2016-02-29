//
//  NSManagedObject+WTADataImport.m
//  WTAData
//
//  Copyright (c) 2014 WillowTree, Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "NSManagedObject+WTADataImport.h"

#import "NSEntityDescription+WTAData.h"
#import "NSManagedObject+WTAData.h"
#import <objc/runtime.h>


@implementation NSManagedObject (WTADataImport)

+ (NSArray *)importEntitiesFromArray:(NSArray *)array context:(NSManagedObjectContext *)context
{
    // Create array to contain results
    NSMutableArray *result = [NSMutableArray new];
    
    if ([array isKindOfClass:[NSArray class]] && [array count])
    {
        // Get entity description and primary attribute for self
        NSEntityDescription *description = [self entityDescriptionInContext:context];
        NSAttributeDescription *primaryAttribute = [description primaryAttribute];
        
        // If we have a primaryAttribute, we'll be able to check for existing entities
        // representing the objects in the array.
        if (primaryAttribute)
        {
            // Get the key that uniquely identifies instances of this entity
            NSString *primaryAttributeString = [description primaryAttributeString];
            NSString *importKey = primaryAttributeString;
            
            // If a custom key has been set, use that
            NSString *customImportKey = [primaryAttribute userInfo][WTAImportNameKey];
            if (customImportKey)
            {
                importKey = customImportKey;
            }
            
            
            // Create a dictionary representing our import objects like so
            // {"value of unique key": object}
            NSMutableDictionary *dictionary = [NSMutableDictionary new];
            for (NSDictionary *item in array)
            {
                id key = item[importKey];
                if (key && [key conformsToProtocol:@protocol(NSCopying)])
                {
                    dictionary[key] = item;
                }
                else
                {
                    // If any item in the array is missing the primary key, then bail early and
                    // remove any object so invalid objects are not imported.
                    [dictionary removeAllObjects];
                    break;
                }
            }
            
            if (dictionary.count > 0)
            {
                // Temporary dictionay to mark which objects have been imported
                NSMutableDictionary *tempDictionary = [dictionary mutableCopy];
            
                // Find all existing entities
                NSPredicate *existingEntitiesPredicate = [NSPredicate predicateWithFormat:@"%K in %@",
                                                          primaryAttributeString, [dictionary allKeys]];
                NSArray *existingEntities = [self fetchInContext:context predicate:existingEntitiesPredicate error:nil];
                
                // Iterate through entites that exist so we can update them
                for (NSManagedObject *entity in existingEntities)
                {
                    // Update values for keys in existing entity
                    NSString *key = [entity valueForKey:primaryAttributeString];
                    NSDictionary *importDictionary = tempDictionary[key];
                    [entity importValuesForKeyWithDictionary:importDictionary];
                    
                    // Remove entity from tempDictionary to mark it as imported
                    [tempDictionary removeObjectForKey:key];
                    
                    // Append entity to results
                    [result addObject:entity];
                }
            
                // For all objects that weren't already existing, create new ones
                for (NSDictionary *item in [tempDictionary allValues])
                {
                    NSManagedObject *entity = [self importEntityFromObject:item context:context checkExisting:NO];
                    [result addObject:entity];
                }
            }
        }
        else
        {
            // Because we had no way to uniquely identify entites, creates new ones for them all
            for (NSDictionary *item in array)
            {
                NSManagedObject *entity = [self importEntityFromObject:item context:context checkExisting:NO];
                [result addObject:entity];
            }
        }
    }
    
    return result;
}

- (void)importValuesForKeyWithDictionary:(NSDictionary *)dictionary
{
    // Create date formatter to be used during import
    NSDateFormatter *defaultDateFormatter = [NSDateFormatter new];
    [defaultDateFormatter setDateFormat:[NSDateFormatter defaultImportDateFormat]];
    
    [[[self entity] relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self importRelationship:obj forKey:key fromDictionary:dictionary];
    }];
    
    // For every attribute in the entity
    [[[self entity] attributesByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        // Get the importKey for the attribute
        NSAttributeDescription *description = obj;
        NSString *importKey = key;
        
        // If there's a custom one, we'll use that instaed
        NSString *customImportKey = [description userInfo][WTAImportNameKey];
        id value;
        if ([customImportKey containsString:@","])
        {
            for (NSString *importKeyTest in [customImportKey componentsSeparatedByString:@","])
            {
                value = [dictionary valueForKeyPath:importKeyTest];
                if (value)
                {
                    break;
                }
            }
        }
        else if (customImportKey)
        {
            importKey = customImportKey;
            value = [dictionary valueForKeyPath:importKey];
        }
        else
        {
            value = [dictionary valueForKey:importKey];
        }
        
        if (value)
        {
            // If it's a date, convert it to a date and set it
            if ([description attributeType] == NSDateAttributeType)
            {
                NSDate *date;
                if ([value isKindOfClass:[NSString class]])
                {
                    NSDateFormatter *dateFormatter = defaultDateFormatter;

                    NSString *customFormat = [description userInfo][WTAImportDateFormatKey];
                    if (customFormat)
                    {
                        dateFormatter = [NSDateFormatter new];
                        [dateFormatter setDateFormat:customFormat];
                    }
                    date = [dateFormatter dateFromString:value];
                }
                else if ([value isKindOfClass:[NSNumber class]])
                {
                    date = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
                }
                else if ([value isKindOfClass:[NSDate class]])
                {
                    date = (NSDate*)value;
                }
                [self importValue:date forKey:key];
            } else if ([description attributeType] == NSStringAttributeType) {
                [self importValue:[value description] forKey:key];
            } else if (![value isKindOfClass:[NSNumber class]]
                       && ([description attributeType] == NSFloatAttributeType
                           || [description attributeType] == NSDoubleAttributeType
                           || [description attributeType] == NSDecimalAttributeType
                           || [description attributeType] == NSInteger64AttributeType
                           || [description attributeType] == NSInteger32AttributeType
                           || [description attributeType] == NSInteger16AttributeType))
            {
                           [self importValue:@(0) forKey:key];
            }
            else
            {
                // If it's already in the right type, we'll go ahead and set the value
                [self importValue:value forKey:key];
            }
        }
        
    }];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([self respondsToSelector:@selector(didImportValuesForKeysWithDictionary:)])
    {
        [self performSelector:@selector(didImportValuesForKeysWithDictionary:) withObject:dictionary];
    }
#pragma clang diagnostic pop
}

- (WTARelationshipMergePolicy)mergePolicyFromString:(NSString*)string
{
    WTARelationshipMergePolicy mergePolicy = WTAMergePolicyReplace;
    
    if ([string isEqualToString:WTAImportMergePolicyMerge])
    {
        mergePolicy = WTAMergePolicyMerge;
    }
    else if ([string isEqualToString:WTAImportMergePolicyMergeAndPrune])
    {
        mergePolicy = WTAMergePolicyMergeAndPrune;
    }
    
    return mergePolicy;
}

- (void)importRelationship:(NSRelationshipDescription*)relationshipDescription
                    forKey:(NSString*)key
            fromDictionary:(NSDictionary*)dictionary
{
    NSString *importKey = key;
    
    // If there's a custom one, we'll use that instaed
    NSString *customImportKey = [relationshipDescription userInfo][WTAImportNameKey];
    id value;
    if ([customImportKey containsString:@","])
    {
        for (NSString *importKeyTest in [customImportKey componentsSeparatedByString:@","])
        {
            value = [dictionary valueForKeyPath:importKeyTest];
            if (value)
            {
                break;
            }
        }
    }
    else if (customImportKey)
    {
        importKey = customImportKey;
        value = [dictionary valueForKeyPath:importKey];
    }
    else
    {
        value = [dictionary valueForKey:importKey];
    }
    
    // If there's a value to be imported for that key
    if (value)
    {
        WTARelationshipMergePolicy mergePolicy = [self mergePolicyFromString:relationshipDescription.userInfo[WTAImportRelationshipMergePolicyKey]];
        [self importRelationship:relationshipDescription
                       withValue:value
                          forKey:key
                  fromDictionary:dictionary
                 withMergePolicy:mergePolicy];
    }
}

- (void)importRelationship:(NSRelationshipDescription*)relationshipDescription
                 withValue:(id)value
                    forKey:(NSString*)key
            fromDictionary:(NSDictionary*)dictionary
           withMergePolicy:(WTARelationshipMergePolicy)mergePolicy
{
    NSEntityDescription *relationshipEntityDescription = [relationshipDescription destinationEntity];
    
    if ([relationshipDescription isToMany])
    {
        // If we are going to replace the items, remove the existing objects.
        if (mergePolicy == WTAMergePolicyReplace)
        {
            for (NSManagedObject *existingEntity in [self valueForKey:key])
            {
                [[self managedObjectContext] deleteObject:existingEntity];
            }
        }
        
        Class class = NSClassFromString([relationshipEntityDescription managedObjectClassName]);
        NSArray *importedObjects = [class importEntitiesFromArray:value context:[self managedObjectContext]];
        
        id set;
        
        if ([relationshipDescription isOrdered])
        {
            // Merge
            if (mergePolicy == WTAMergePolicyMerge || mergePolicy == WTAMergePolicyMergeAndPrune)
            {
                NSMutableOrderedSet *existingSet = [[self valueForKey:key] mutableCopy];
                
                if (mergePolicy == WTAMergePolicyMergeAndPrune)
                {
                    for (NSManagedObject *existingObject in existingSet)
                    {
                        if (![importedObjects containsObject:existingObject])
                        {
                            [existingSet removeObject:existingObject];
                        }
                    }
                }
                
                for (NSManagedObject *importedObject in importedObjects)
                {
                    if (![existingSet containsObject:importedObject])
                    {
                        [existingSet addObject:importedObject];
                    }
                }
                
                set = existingSet;
            }
            else
            {
                set = [[NSOrderedSet alloc] initWithArray:importedObjects];
            }
        }
        else
        {
            if (mergePolicy == WTAMergePolicyMerge || mergePolicy == WTAMergePolicyMergeAndPrune)
            {
                NSMutableSet *existingSet = [[self valueForKey:key] mutableCopy];
                
                if (mergePolicy == WTAMergePolicyMergeAndPrune)
                {
                    [existingSet intersectSet:[NSSet setWithArray:importedObjects]];
                }

                for (NSManagedObject *importedObject in importedObjects)
                {
                    if (![existingSet containsObject:importedObject])
                    {
                        [existingSet addObject:importedObject];
                    }
                }
                
                set = existingSet;
            }
            else
            {
                set = [NSSet setWithArray:importedObjects];
            }
        }
        
        [self setValue:set forKey:key];
    }
    else
    {
        if ([self valueForKey:key] && mergePolicy == WTAMergePolicyReplace)
        {
            [[self managedObjectContext] deleteObject:[self valueForKey:key]];
        }
        Class class = NSClassFromString([relationshipEntityDescription managedObjectClassName]);
        NSManagedObject *object = [class importEntityFromObject:value context:[self managedObjectContext]];
        [self setValue:object forKey:key];
    }
}


- (void)importValue:(id)value forKey:(NSString *)key
{
    NSString *selectorString = [NSString stringWithFormat:@"import%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
    SEL selector = NSSelectorFromString(selectorString);
    if ([self respondsToSelector:selector])
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:selector withObject:value];
#pragma clang diagnostic pop
    }
    else if (![value isEqual:[NSNull null]])
    {
        [self setValue:value forKey:key];
    }
    else if ([value isEqual:[NSNull null]])
    {
        [self setValue:nil forKey:key];
    }

}

+ (instancetype)importEntityFromObject:(NSDictionary *)object context:(NSManagedObjectContext *)context checkExisting:(BOOL)checkExisting
{
    
    NSManagedObject *entity = nil;
    if ([object isKindOfClass:[NSDictionary class]])
    {
        // If we need to check for an existing entity to update
        if (checkExisting)
        {
            // Get the primary attribute that uniquely identifies entity
            NSEntityDescription *description = [self entityDescriptionInContext:context];
            NSAttributeDescription *primaryAttribute = [description primaryAttribute];
            
            NSString *importKey = [primaryAttribute name];
            NSString *customImportKey = [primaryAttribute userInfo][WTAImportNameKey];
            if (customImportKey)
            {
                importKey = customImportKey;
            }
            
            id value = object[importKey];
            
            // If we were able to get it
            if (value)
            {
                // See if the entity already exists
                NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[description name]];
                [request setFetchLimit:1];
                [request setPredicate:[NSPredicate predicateWithFormat:@"%K = %@", [primaryAttribute name], value]];
                NSArray *results = [context executeFetchRequest:request error:nil];
                entity = [results firstObject];
            }
        }
        
        // If the entity did not already exist, create it
        if (!entity)
        {
            entity = [self createEntityInContext:context];
        }
        
        // Update values for keys in the entity
        [entity importValuesForKeyWithDictionary:object];
    }
    return entity;
}

+ (instancetype)importEntityFromObject:(NSDictionary *)object context:(NSManagedObjectContext *)context
{
    return [self importEntityFromObject:object context:context checkExisting:YES];
}

@end

@implementation NSDateFormatter (WTADataImport)

+ (NSString *)defaultImportDateFormat
{
    NSString *format = objc_getAssociatedObject(self, @selector(defaultImportDateFormat));
    if (!format)
    {
        format = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        [self setDefaultImportDateFormat:format];
    }
    return format;
}

+ (void)setDefaultImportDateFormat:(NSString *)defaultImportDateFormat
{
    objc_setAssociatedObject(self, @selector(defaultImportDateFormat), defaultImportDateFormat, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end