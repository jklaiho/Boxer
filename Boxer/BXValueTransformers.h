/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXValueTransformers defines various generic and not-so-generic value transformers for UI elements
//that use key-value binding.

#import <Cocoa/Cocoa.h>

#pragma mark -
#pragma mark Date transformers

//A simple value transformer that wraps an NSDateFormatter instance.
@interface BXDateTransformer : NSValueTransformer
{
    NSDateFormatter *_formatter;
}
@property (retain, nonatomic) NSDateFormatter *formatter;

- (id) initWithDateFormatter: (NSDateFormatter *)formatter;
@end

#pragma mark -
#pragma mark Numeric transformers

//Averages out the value of an NSNumber using the specified number of previous inputs as a 'window'.
//Note that this transformer stores state internally, which means it must not be shared between multiple
//input sources.
@interface BXRollingAverageTransformer : NSValueTransformer
{
	NSNumber *previousAverage;
	NSUInteger windowSize;
}
- (id) initWithWindowSize: (NSUInteger)size;
@end

//Returns the NSNumber equivalents of YES or NO based on whether an array's size is within the min and max range of the transformer.
//Registered as BXIsEmpty and BXIsNotEmpty by BXAppController, which are used for detecting whether an array is empty or not.
@interface BXArraySizeTransformer : NSValueTransformer
{
	NSUInteger minSize;
	NSUInteger maxSize;
}
- (id) initWithMinSize: (NSUInteger)min maxSize: (NSUInteger)max;
@end


//Simply inverts a number and returns it.
//Registered as BXFrameRateSliderTransformer by BXSession+BXEmulatorControls, which is used for flipping the values of the framerate slider.
@interface BXInvertNumberTransformer: NSValueTransformer
@end


//Maps sets of numeric ranges (0-1000, 1001-2000 etc.) onto a 0.0->1.0 scale, with equal weight for each range.
//Registered as BXSpeedSliderTransformer by BXSession+BXEmulatorControls, to maps our different CPU speed bands onto a single speed slider.
//NOTE: sliders using this transformer must have a range from 0.0 to 1.0.
#define MAX_BANDS 32
@interface BXBandedValueTransformer: NSValueTransformer
{
	double bandThresholds[MAX_BANDS];
    NSUInteger numBands;
}

- (id) initWithThresholds: (double *)thresholds count: (NSUInteger)count;
- (void) setThresholds: (double *)thresholds count: (NSUInteger)count;

@end


#pragma mark -
#pragma mark String transformers

//Capitalises the first letter of a string
@interface BXCapitalizer: NSValueTransformer
@end

//Converts a POSIX file path into a lowercase filename
@interface BXDOSFilenameTransformer: NSValueTransformer
@end

//Converts a POSIX file path into OS X's display filename
@interface BXDisplayNameTransformer: NSValueTransformer
@end


//Converts a POSIX file path into a representation suitable for display.
@interface BXDisplayPathTransformer: NSValueTransformer
{
	NSString *joiner;
	NSString *ellipsis;
	NSUInteger maxComponents;
	BOOL useFilesystemDisplayPath;
}
@property (copy, nonatomic) NSString *joiner;
@property (copy, nonatomic) NSString *ellipsis;
@property (assign, nonatomic) NSUInteger maxComponents;
@property (assign, nonatomic) BOOL useFilesystemDisplayPath;

- (id) initWithJoiner: (NSString *)joinString
			 ellipsis: (NSString *)ellipsisString
		maxComponents: (NSUInteger)components;

- (id) initWithJoiner: (NSString *)joinString
		maxComponents: (NSUInteger)components;
@end


//Converts a POSIX path into a breadcrumb-style representation with file icons
//for each part of the file path. Unlike BXDisplayPathTransformer, this returns
//an NSAttributedString rather than an NSString.
@interface BXIconifiedDisplayPathTransformer: BXDisplayPathTransformer
{
	NSImage *missingFileIcon;
	NSMutableDictionary *textAttributes;
	NSMutableDictionary *iconAttributes;
	NSSize iconSize;
	BOOL hideSystemRoots;
}
//The file icon to use for files/folders that don't yet exist.
//If left as nil, will use NSWorkspace's default icon for missing files.
@property (copy, nonatomic) NSImage *missingFileIcon;

//The NSAttributedString attributes to apply to the final text.
//Defaults to the standard system font.
@property (retain, nonatomic) NSMutableDictionary *textAttributes;

//The NSAttributedString attributes to apply to the icons within the text.
//Defaults to a baseline offset of -4.0.
@property (retain, nonatomic) NSMutableDictionary *iconAttributes;

//The pixel size at which to display icons. Defaults to 16x16.
@property (assign, nonatomic) NSSize iconSize;

//Whether to hide the / and /Users/ subpaths in displayed paths.
//This imitates the behaviour of NSPathControl et. al.
@property (assign, nonatomic) BOOL hideSystemRoots;

//Returns an icon-and-label attributed string for the specified path.
//defaultIcon specifies the icon to use if the path does not exist.
- (NSAttributedString *) componentForPath: (NSString *)path
						  withDefaultIcon: (NSImage *)defaultIcon;

@end


#pragma mark -
#pragma mark Image transformers

//Resizes an NSImage to the target size.
@interface BXImageSizeTransformer: NSValueTransformer
{
	NSSize size;
}
@property (assign, nonatomic) NSSize size;

- (id) initWithSize: (NSSize)targetSize;

- (NSImage *) transformedValue: (NSImage *)image;

@end
