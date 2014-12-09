//
//  NSManagedObject+WTADataImport.m
//  WTAData
//
//  Copyright (c) 2014 WillowTreeApps. All rights reserved.
//

#import "NSManagedObject+WTADataImport.h"

#import "NSEntityDescription+WTAData.h"
#import "NSManagedObject+WTAData.h"

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
            NSString *customImportKey = [primaryAttribute userInfo][@"ImportName"];
            if (customImportKey)
            {
                importKey = customImportKey;
            }
            
            // Create a dictionary representing our import objects like so
            // {"value of unique key": object}
            NSMutableDictionary *dictionary = [NSMutableDictionary new];
            for (NSDictionary *item in array)
            {
                NSString *key = item[importKey];
                dictionary[key] = item;
            }
            
            // Temporary dictionay to mark which objects have been imported
            NSMutableDictionary *tempDictionary = [dictionary mutableCopy];
            
            // Find all existing entities
            NSString *formatString = [NSString stringWithFormat:@"%@ in %%@", primaryAttributeString];
            NSPredicate *existingEntitiesPredicate = [NSPredicate predicateWithFormat:formatString, [dictionary allKeys]];
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
    //TODO: Finish creation of relationship entitys that don't exist
    
    // Create date formatter to be used during import
    NSDateFormatter *dateFormater = [NSDateFormatter new];
    [dateFormater setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    
    [[[self entity] relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        NSRelationshipDescription *relationshipDescription = obj;
        NSString *importKey = key;
        
        // If there's a custom one, we'll use that instaed
        NSString *customImportKey = [relationshipDescription userInfo][@"ImportName"];
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
            NSEntityDescription *relationshipEntityDescription = [relationshipDescription destinationEntity];
            
            if ([relationshipDescription isToMany])
            {
                // TODO Add userinfo key for merge policy
                for (NSManagedObject *existingEntity in [self valueForKey:key])
                {
                    [[self managedObjectContext] deleteObject:existingEntity];
                }
                
                Class class = NSClassFromString([relationshipEntityDescription managedObjectClassName]);
                NSArray *objects = [class importEntitiesFromArray:value context:[self managedObjectContext]];
                [self setValue:[NSSet setWithArray:objects] forKey:key];
            }
            else
            {
                // TODO Add userinfo key for merge policy
                if ([self valueForKey:key])
                {
                    [[self managedObjectContext] deleteObject:[self valueForKey:key]];
                }
                Class class = NSClassFromString([relationshipEntityDescription managedObjectClassName]);
                NSManagedObject *object = [class importEntityFromObject:value context:[self managedObjectContext]];
                [self setValue:object forKey:key];
            }
        }
        
    }];
    
    // For every attribute in the entity
    [[[self entity] attributesByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        // Get the importKey for the attribute
        NSAttributeDescription *description = obj;
        NSString *importKey = key;
        
        // If there's a custom one, we'll use that instaed
        NSString *customImportKey = [description userInfo][@"ImportName"];
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
                    date = [dateFormater dateFromString:value];
                }
                [self importValue:date forKey:key];
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
            NSString *customImportKey = [primaryAttribute userInfo][@"ImportName"];
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
                NSString *predicateFormat = [NSString stringWithFormat:@"%@ = %%@", [primaryAttribute name]];
                [request setPredicate:[NSPredicate predicateWithFormat:predicateFormat, value]];
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
