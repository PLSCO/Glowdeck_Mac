//
//  NSString+NSStringHexToBytes.m
//  Glowdeck
//
//  Created by Justin Kaufman on 8/24/17.
//  Copyright © 2017 Justin Kaufman. All rights reserved.
//

#import "NSString+NSStringHexToBytes.h"

@implementation NSString (NSStringHexToBytes)

+ (NSData *)dataWithString:(NSString *)string
{
    //string = [string stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    
    //NSCharacterSet *notAllowedCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefABCDEF1234567890"] invertedSet];
    //string = [[string componentsSeparatedByCharactersInSet:notAllowedCharacters] componentsJoinedByString:@""];
    
    const char *cString = [string cStringUsingEncoding:NSASCIIStringEncoding];
    const char *idx = cString;
    unsigned char result[[string length] / 2];
    size_t count = 0;
    
    for(count = 0; count < sizeof(result)/sizeof(result[0]); count++)
    {
        sscanf(idx, "%2hhx", &result[count]);
        idx += 2 * sizeof(char);
    }
    
    return [[NSData alloc] initWithBytes:result length:sizeof(result)];
}

@end
