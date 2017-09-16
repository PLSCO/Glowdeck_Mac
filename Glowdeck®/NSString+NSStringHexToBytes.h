//
//  NSString+NSStringHexToBytes.h
//  Glowdeck
//
//  Created by Justin Kaufman on 8/24/17.
//  Copyright © 2017 Justin Kaufman. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (NSStringHexToBytes)
+ (NSData *)dataWithString:(NSString *)string;
@end

