/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXSessionError.h"


NSString * const BXSessionErrorDomain = @"BXSessionErrorDomain";

@implementation BXSessionError

//Helper method for getting human-readable names from paths.
+ (NSString *) displayNameForPath: (NSString *)path
{
	NSString *displayName			= [[NSFileManager defaultManager] displayNameAtPath: path];
	if (!displayName) displayName	= [path lastPathComponent];
	return displayName;
}

@end

@implementation BXImportError
@end


@implementation BXSessionCannotMountSystemFolderError

+ (id) errorWithPath: (NSString *)folderPath userInfo: (NSDictionary *)userInfo
{
    NSString *descriptionFormat = NSLocalizedString(@"MS-DOS is not permitted to access OS X system folders like “%@”.",
                                                    @"Error message shown when user tries to mount a system folder as a DOS drive. %@ is the requested folder path."
                                                    );
    
    NSString *suggestion = NSLocalizedString(@"Instead, choose one of your own folders, or a disc mounted in OS X.", @"Recovery suggestion shown when user tries to mount a system folder as a DOS drive.");
    
    NSString *description = [NSString stringWithFormat: descriptionFormat, [self displayNameForPath: folderPath], nil];
    NSMutableDictionary *defaultInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                        description,    NSLocalizedDescriptionKey,
                                        suggestion,     NSLocalizedRecoverySuggestionErrorKey,
                                        folderPath,     NSFilePathErrorKey,
                                        nil];
    
	if (userInfo) [defaultInfo addEntriesFromDictionary: userInfo];
    
	return [self errorWithDomain: BXSessionErrorDomain
							code: BXSessionCannotMountSystemFolder
						userInfo: defaultInfo];
}
@end


@implementation BXImportNoExecutablesError

+ (id) errorWithSourcePath: (NSString *)sourcePath userInfo: (NSDictionary *)userInfo
{
	NSString *descriptionFormat = NSLocalizedString(@"“%@” does not contain any MS-DOS programs.",
													@"Error message shown when importing a folder with no executables in it. %@ is the display filename of the imported path.");
	
	NSString *suggestion = NSLocalizedString(@"This folder may contain a game for another platform which is not supported by Boxer.",
											 @"Explanation text shown when importing a folder with no executables in it.");
	
	NSString *description = [NSString stringWithFormat: descriptionFormat, [self displayNameForPath: sourcePath], nil];
	
	
	NSMutableDictionary *defaultInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										description,	NSLocalizedDescriptionKey,
										suggestion,		NSLocalizedRecoverySuggestionErrorKey,
										sourcePath,		NSFilePathErrorKey,
										nil];
	
	if (userInfo) [defaultInfo addEntriesFromDictionary: userInfo];
	
	return [self errorWithDomain: BXSessionErrorDomain
							code: BXImportNoExecutablesInSourcePath
						userInfo: defaultInfo];
}

@end


@implementation BXImportWindowsOnlyError

+ (id) errorWithSourcePath: (NSString *)sourcePath userInfo: (NSDictionary *)userInfo
{
	NSString *descriptionFormat = NSLocalizedString(
		@"“%@” is a Windows game or has a Windows installer, which Boxer cannot import.",
		@"Error message shown when importing a folder that contains a Windows-only game or Windows installer. %@ is the display filename of the imported path."
	);
	
	NSString *suggestion = NSLocalizedString(
		@"You should install it with a Windows PC or emulator instead. If it installs an MS-DOS game, you can then import the installed game files into Boxer.",
		@"Informative text of warning sheet after importing a Windows-only game."
	);
	
	NSString *description = [NSString stringWithFormat: descriptionFormat, [self displayNameForPath: sourcePath], nil];
	
	NSMutableDictionary *defaultInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										description,	NSLocalizedDescriptionKey,
										suggestion,		NSLocalizedRecoverySuggestionErrorKey,
										sourcePath,		NSFilePathErrorKey,
										nil];
	
	if (userInfo) [defaultInfo addEntriesFromDictionary: userInfo];
	
	return [self errorWithDomain: BXSessionErrorDomain
							code: BXImportSourcePathIsWindowsOnly
						userInfo: defaultInfo];
}

- (NSString *) helpAnchor
{
	return @"windows-only-programs";
}
@end
