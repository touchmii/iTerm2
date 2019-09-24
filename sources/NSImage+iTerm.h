//
//  NSImage+iTerm.h
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSImage (iTerm)

+ (NSImage *)imageOfSize:(NSSize)size color:(NSColor *)color;

// Creates an image context and runs block. Do drawing into the current
// graphics context in the block. Returns the resulting image.
+ (instancetype)imageOfSize:(NSSize)size drawBlock:(void (^)(void))block;

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                   bitsPerSample:(NSInteger)bitsPerSample  // e.g. 8 or 1
                 samplesPerPixel:(NSInteger)samplesPerPixel  // e.g. 4 (RGBA) or 1
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName;  // e.g., NSCalibratedRGBColorSpace

// Returns "gif", "png", etc., or nil.
+ (NSString *)extensionForUniformType:(NSString *)type;

+ (instancetype)it_imageNamed:(NSImageName)name forClass:(Class)theClass;

// Returns an image blurred by repeated box blurs with |radius| iterations.
- (NSImage *)blurredImageWithRadius:(int)radius;

// Recolor the image with the given color but preserve its alpha channel.
- (NSImage *)imageWithColor:(NSColor *)color;

// e.g., NSPNGFileType
- (NSData *)dataForFileOfType:(NSBitmapImageFileType)fileType;

- (NSData *)rawPixelsInRGBColorSpace;

- (NSBitmapImageRep *)bitmapImageRep;
- (NSImageRep *)bestRepresentationForScale:(CGFloat)scale;
- (void)saveAsPNGTo:(NSString *)filename;

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor;
- (NSImage *)it_flippedImage;
- (NSImage *)it_imageOfSize:(NSSize)size;

// Returns an image of size `size`, with the receiver zoomed and cropped so it at least fills the
// resulting image.
- (NSImage *)it_imageFillingSize:(NSSize)size;

@end
