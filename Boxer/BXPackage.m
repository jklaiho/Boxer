/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXPackage.h"
#import "NSString+BXPaths.h"
#import "NSWorkspace+BXFileTypes.h"
#import "NSWorkspace+BXIcons.h"
#import "BXAppController.h"
#import "RegexKitLite.h"
#import "BXDigest.h"
#import "NSData+HexStrings.h"
#import "BXPathEnumerator.h"

#pragma mark -
#pragma mark Constants

//Application-wide constants.
NSString * const BXGameIdentifierKey        = @"BXGameIdentifier";
NSString * const BXGameIdentifierTypeKey    = @"BXGameIdentifierType";
NSString * const BXTargetProgramKey         = @"BXDefaultProgramPath";

NSString * const BXTargetSymlinkName			= @"DOSBox Target";
NSString * const BXConfigurationFileName		= @"DOSBox Preferences";
NSString * const BXConfigurationFileExtension	= @"conf";
NSString * const BXGameInfoFileName				= @"Game Info";
NSString * const BXGameInfoFileExtension		= @"plist";
NSString * const BXDocumentationFolderName		= @"Documentation";

NSString * const BXGameboxErrorDomain = @"BXGameboxErrorDomain";


//When calculating a digest from the gamebox's EXEs, read only the first 64kb of each EXE.
#define BXGameIdentifierEXEDigestStubLength 65536


#pragma mark -
#pragma mark Private method declarations

@interface BXPackage ()
@property (readwrite, retain, nonatomic) NSDictionary *gameInfo;

//Arrays of paths to discovered files of particular types within the gamebox.
//BXPackage's documentation and executables accessors call these internal methods and cache the results.
- (NSArray *) _foundDocumentation;
- (NSArray *) _foundExecutables;
- (NSArray *) _foundResourcesOfTypes: (NSSet *)fileTypes startingIn: (NSString *)basePath;

//Returns a new auto-generated identifier based on this gamebox's name.
//On return, type will be the type of identifier generated.
- (NSString *) _generatedIdentifierOfType: (BXGameIdentifierType *)type;

//Save the game info back to the gamebox.
- (void) _persistGameInfo;
@end


@implementation BXPackage
@synthesize gameInfo;

+ (NSSet *) documentationTypes
{
	static NSSet *types = nil;
	if (!types) types = [[NSSet alloc] initWithObjects:
		@"public.jpeg",
		@"public.plain-text",
		@"public.png",
		@"com.compuserve.gif",
		@"com.adobe.pdf",
		@"public.rtf",
		@"com.microsoft.bmp",
		@"com.microsoft.word.doc",
		@"public.html",
	nil];
	return types;
}

//We ignore files with these names when considering which documentation files are likely to be worth showing
//TODO: read this data from a configuration plist instead
+ (NSSet *) documentationExclusions
{
	static NSSet *exclusions = nil;
	if (!exclusions) exclusions = [[NSSet alloc] initWithObjects:
		@"install.gif",
		@"install.txt",
		@"interp.txt",
		@"order.txt",
		@"orderfrm.txt",
		@"license.txt",
	nil];
	return exclusions;
}

//We ignore files with these names when considering which programs are important enough to list
//TODO: read this data from a configuration plist instead
+ (NSSet *) executableExclusions
{
	static NSSet *exclusions = nil;
	if (!exclusions) exclusions = [[NSSet alloc] initWithObjects:
		@"dos4gw.exe",
		@"pkunzip.exe",
		@"lha.com",
		@"arj.exe",
		@"deice.exe",
		@"pkunzjr.exe",
	nil];
	return exclusions;
}

+ (BXPackage *)bundleWithPath: (NSString *)path
{
	return [[[self alloc] initWithPath: path] autorelease];
}

- (void) dealloc
{
	[self setGameInfo: nil], [gameInfo release];
	[super dealloc];
}

- (NSArray *) hddVolumes	{ return [self volumesOfTypes: [BXAppController hddVolumeTypes]]; }
- (NSArray *) cdVolumes		{ return [self volumesOfTypes: [BXAppController cdVolumeTypes]]; }
- (NSArray *) floppyVolumes	{ return [self volumesOfTypes: [BXAppController floppyVolumeTypes]]; }

- (NSArray *) volumesOfTypes: (NSSet *)acceptedTypes
{
	BXPathEnumerator *enumerator = [BXPathEnumerator enumeratorAtPath: [self resourcePath]];
	[enumerator setSkipSubdirectories: YES];
	[enumerator setFileTypes: acceptedTypes];
	return [enumerator allObjects];
}

- (NSString *) gamePath { return [self bundlePath]; }

- (NSString *) targetPath
{
    NSString *targetPath = [self gameInfoForKey: BXTargetProgramKey];
    
	//Resolve the path from a gamebox-relative path into an absolute path
    if (targetPath)
    {
        targetPath = [[self resourcePath] stringByAppendingPathComponent: targetPath];
    }
    //If there's no target path stored in game info, check for an old-style symlink
    else
	{
		NSString *symlinkPath = [self pathForResource: BXTargetSymlinkName ofType: nil];
        targetPath = [symlinkPath stringByResolvingSymlinksInPath];
        
        if (targetPath)
        {
            //If the resolved symlink path is the same as the path to the symlink itself,
            //this indicates it was a broken link that could not be resolved
            if ([targetPath isEqualToString: symlinkPath]) targetPath = nil;
            else
            {
                //Once we've resolved the symlink, store it in the game info for future use
                [self setTargetPath: targetPath];
            }
        }
	}
    
	return targetPath;
}

- (void) setTargetPath: (NSString *)path
{
    if (path)
    {
        //Make the path relative to the game package
        NSString *basePath		= [self resourcePath];
        NSString *relativePath	= [path pathRelativeToPath: basePath];
    
        [self setGameInfo: relativePath forKey: BXTargetProgramKey];
    }
    else
    {
        [self setGameInfo: nil forKey: BXTargetProgramKey];
        
        //Delete any leftover symlink
		NSString *symlinkPath = [self pathForResource: BXTargetSymlinkName ofType: nil];
        [[NSFileManager defaultManager] removeItemAtPath: symlinkPath error: nil];
    }
}

- (BOOL) validateTargetPath: (id *)ioValue error: (NSError **)outError
{
	NSString *filePath = *ioValue;
    
    //Nil values will clear the target path
    if (filePath == nil) return YES;
    
	NSFileManager *manager = [NSFileManager defaultManager];
	
	//If the destination file does not exist, show an error
    //TWEAK: this condition is disabled for now, to allow links to files within
    //disk images.
    /*
	if (![manager fileExistsAtPath: filePath])
	{
		if (outError)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  filePath, NSFilePathErrorKey,
									  nil];
			*outError = [NSError errorWithDomain: NSCocoaErrorDomain
											code: NSFileNoSuchFileError
										userInfo: userInfo];
		}
		return NO;
	}
     */
	
	//Reject target paths that are not located inside the gamebox
	if (![filePath isRootedInPath: [self gamePath]])
	{
		if (outError)
		{
			NSString *format = NSLocalizedString(@"The file “%@” was not located inside this gamebox.",
												 @"Error message shown when trying to set the target path of a gamebox to a file outside the gamebox. %@ is the display filename of the file in question.");
			
			NSString *displayName = [manager displayNameAtPath: filePath];
			NSString *description = [NSString stringWithFormat: format, displayName, nil];
			
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									  filePath, NSFilePathErrorKey,
									  description, NSLocalizedDescriptionKey,
									  nil];
			
			*outError = [NSError errorWithDomain: BXGameboxErrorDomain
											code: BXTargetPathOutsideGameboxError
										userInfo: userInfo];
		}
		return NO;
	}
    
	return YES;
}


- (NSString *) configurationFile
{
    //LAZY ASS FIX: this used to use pathForResource:ofType: but this was incorrectly returning nil
    //in the case where a configuration file had just been written but NSBundle had checked before
    //for a file and found it missing. This will be fixed once we migrate this wretched class away
    //from NSBundle once and for all.
    NSFileManager *manager = [NSFileManager defaultManager];
    
    NSString *configPath = [self configurationFilePath];
    if ([manager fileExistsAtPath: configPath]) return configPath;
    else return nil;
}

- (NSString *) configurationFilePath
{
	NSString *fileName = [BXConfigurationFileName stringByAppendingPathExtension: BXConfigurationFileExtension];
	return [[self resourcePath] stringByAppendingPathComponent: fileName];
}

//Set/return the cover art associated with this game package (currently, the package file's icon)
- (NSImage *) coverArt
{
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	if ([workspace fileHasCustomIcon: [self bundlePath]])
	{
		return [workspace iconForFile: [self bundlePath]];
	}
	else return nil;
}

- (void) setCoverArt: (NSImage *)image
{
	[[NSWorkspace sharedWorkspace] setIcon: image forFile: [self bundlePath] options: 0];
}

- (NSArray *) executables
{
	return [self _foundExecutables];
}

- (NSArray *) documentation
{
	return [self _foundDocumentation];
}

- (NSDictionary *) gameInfo
{
	//Load the game info from the gamebox's plist file the first time we need it.
	if (gameInfo == nil)
	{
		NSMutableDictionary *info = nil;
		
		NSString *infoPath = [self pathForResource: BXGameInfoFileName ofType: BXGameInfoFileExtension];
		if (infoPath) info = [NSMutableDictionary dictionaryWithContentsOfFile: infoPath];
		
		//If there was no plist file in the gamebox, create an empty dictionary instead.
		if (!info) info = [NSMutableDictionary dictionaryWithCapacity: 10];
		
		[self setGameInfo: info];
	}
	
	return gameInfo;
}

- (id) gameInfoForKey: (NSString *)key
{
	return [[self gameInfo] objectForKey: key];
}

- (void) setGameInfo: (id)info forKey: (NSString *)key
{
	[self willChangeValueForKey: @"gameInfo"];
	
	if (![[self gameInfoForKey: key] isEqual: info])
	{
        if (info)
            [(NSMutableDictionary *)[self gameInfo] setObject: info forKey: key];
        else
            [(NSMutableDictionary *)[self gameInfo] removeObjectForKey: key];
        
		[self _persistGameInfo];		
	}
	[self didChangeValueForKey: @"gameInfo"];
}

- (NSString *) gameIdentifier
{
	NSString *identifier = [self gameInfoForKey: BXGameIdentifierKey];
	
	//If we don't have an identifier yet, generate a new one and add it to the game's metadata.
	if (!identifier)
	{
		BXGameIdentifierType generatedType = 0;
		identifier = [self _generatedIdentifierOfType: &generatedType];

		[gameInfo setObject: identifier forKey: BXGameIdentifierKey];
		[gameInfo setObject: [NSNumber numberWithUnsignedInteger: generatedType]
					 forKey: BXGameIdentifierTypeKey];
		[self _persistGameInfo];
	}
	
	return identifier;
}

- (void) setGameIdentifier: (NSString *)identifier
{
	[gameInfo setObject: identifier forKey: BXGameIdentifierKey];
	[gameInfo setObject: [NSNumber numberWithUnsignedInteger: BXGameIdentifierUserSpecified]
				 forKey: BXGameIdentifierTypeKey];
}

- (NSString *) gameName
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *displayName = [manager displayNameAtPath: [self bundlePath]];

	//Strip the extension if it's .boxer, otherwise leave path extension intact
	//(as it could be a version number component, e.g. the ".1" in "Windows 3.1")
	if ([[[displayName pathExtension] lowercaseString] isEqualToString: @"boxer"])
		displayName = [displayName stringByDeletingPathExtension];
	
	return displayName;
}

- (void) refresh
{
	[self setGameInfo: nil];
}



#pragma mark -
#pragma mark Private methods

//Write the game info back to the plist file
- (void) _persistGameInfo
{
	if (gameInfo)
	{
		NSString *infoName = [BXGameInfoFileName stringByAppendingPathExtension: BXGameInfoFileExtension];
		NSString *infoPath = [[self resourcePath] stringByAppendingPathComponent: infoName];
		[gameInfo writeToFile: infoPath atomically: YES];
	}
}


//Trawl the package looking for DOS executables
//TODO: move filtering upstairs to BXSession, as we should not be determining application behaviour here.
- (NSArray *) _foundExecutables
{
	NSArray *foundExecutables	= [self _foundResourcesOfTypes: [BXAppController executableTypes] startingIn: [self gamePath]];
	NSPredicate *notExcluded	= [NSPredicate predicateWithFormat: @"NOT lastPathComponent.lowercaseString IN %@", [[self class] executableExclusions]];
	
	return [foundExecutables filteredArrayUsingPredicate: notExcluded];
}

- (NSArray *) _foundDocumentation
{
	//First, check if there is an explicitly-named documentation folder and use the contents of that if so
	NSArray *docsFolderContents = [self pathsForResourcesOfType: nil inDirectory: BXDocumentationFolderName];
	if ([docsFolderContents count])
	{
		NSPredicate *notHidden	= [NSPredicate predicateWithFormat: @"NOT lastPathComponent BEGINSWITH %@", @".", nil];
		return [docsFolderContents filteredArrayUsingPredicate: notHidden];
	}

	//Otherwise, go trawling through the entire game package looking for likely documentation
	NSArray *foundDocumentation	= [self _foundResourcesOfTypes: [[self class] documentationTypes] startingIn: [self gamePath]];
	NSPredicate *notExcluded	= [NSPredicate predicateWithFormat: @"NOT lastPathComponent.lowercaseString IN %@", [[self class] documentationExclusions]];

	return [foundDocumentation filteredArrayUsingPredicate: notExcluded];
}

- (NSArray *) _foundResourcesOfTypes: (NSSet *)fileTypes startingIn: (NSString *)basePath
{
	NSWorkspace *workspace	= [NSWorkspace sharedWorkspace];
	NSMutableArray *matches	= [NSMutableArray arrayWithCapacity: 10];
	
	for (NSString *path in [BXPathEnumerator enumeratorAtPath: basePath])
	{
		//Note that we don't use our own smarter file:matchesTypes: function for this,
		//because there are some inherited filetypes that we want to avoid matching.
		if ([fileTypes containsObject: [workspace typeOfFile: path error: nil]]) [matches addObject: path];
	}
	return matches;	
}

- (NSString *) _generatedIdentifierOfType: (BXGameIdentifierType *)type
{
	//If the gamebox contains executables, generate an identifier based on their hash.
	//TODO: move the choice of executables off to BXSession
	NSArray *foundExecutables = [self executables];
	if ([foundExecutables count])
	{
		NSData *digest = [BXDigest SHA1DigestForFiles: foundExecutables
										   upToLength: BXGameIdentifierEXEDigestStubLength];
		*type = BXGameIdentifierEXEDigest;
		
		return [digest stringWithHexBytes];
	}
	
	//Otherwise, generate a UUID.
	else
	{	
		CFUUIDRef     UUID;
		CFStringRef   UUIDString;
		
		UUID = CFUUIDCreate(kCFAllocatorDefault);
		UUIDString = CFUUIDCreateString(kCFAllocatorDefault, UUID);
		
		NSString *identifierWithUUID = [NSString stringWithString: (NSString *)UUIDString];
		
		CFRelease(UUID);
		CFRelease(UUIDString);
		
		*type = BXGameIdentifierUUID;

		return identifierWithUUID;
	}
}

@end
