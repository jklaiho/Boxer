/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXSimpleDriveImport.h"
#import "BXAppController.h"
#import "BXDrive.h"
#import "NSWorkspace+BXFileTypes.h"


@interface BXSimpleDriveImport ()
@property (copy, readwrite) NSString *importedDrivePath;
@end

@implementation BXSimpleDriveImport
@synthesize drive = _drive;
@synthesize destinationFolder = _destinationFolder;
@synthesize importedDrivePath = _importedDrivePath;


#pragma mark -
#pragma mark Helper class methods

+ (BOOL) isSuitableForDrive: (BXDrive *)drive
{
	return YES;
}

+ (BOOL) driveUnavailableDuringImport
{
    return NO;
}

+ (NSString *) nameForDrive: (BXDrive *)drive
{
	NSString *importedName = nil;
	NSString *drivePath = [drive path];
	
	NSFileManager *manager = [NSFileManager defaultManager];
	BOOL isDir, exists = [manager fileExistsAtPath: drivePath isDirectory: &isDir];
	
	if (exists)
	{
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		
		NSSet *readyTypes = [[BXAppController mountableFolderTypes] setByAddingObjectsFromSet: [BXAppController mountableImageTypes]];
		
		//Files and folders of the above types don't need additional renaming before import:
        //we can just use their filename directly.
		if ([workspace file: drivePath matchesTypes: readyTypes])
		{
			importedName = [drivePath lastPathComponent];
		}
		//Otherwise: if it's a directory, it will need to be renamed as a mountable folder.
		else if (isDir)
		{
			importedName = [drive volumeLabel];
			
			NSString *extension	= nil;
			
			//Give the mountable folder the proper file extension for its drive type
			switch ([drive type])
			{
				case BXDriveCDROM:
					extension = @"cdrom";
					break;
				case BXDriveFloppyDisk:
					extension = @"floppy";
					break;
				case BXDriveHardDisk:
				default:
					extension = @"harddisk";
					break;
			}
			importedName = [importedName stringByAppendingPathExtension: extension];
		}
        //Otherwise: if it's a file, then it's *presumably* an ISO disc image
        //that's been given a dumb file extension (hello GOG!) and should be
        //renamed to something sensible.
        //TODO: validate that it is in fact an ISO image, once we have ISO parsing ready.
        else
        {
            NSString *baseName = [[drivePath lastPathComponent] stringByDeletingPathExtension];
            importedName = [baseName stringByAppendingPathExtension: @"iso"];
        }
		
		//If the drive has a letter, then prepend it in our standard format
		if ([drive letter]) importedName = [NSString stringWithFormat: @"%@ %@", [drive letter], importedName];
	}
	return importedName;
}

#pragma mark -
#pragma mark Initialization and deallocation

- (id <BXDriveImport>) initForDrive: (BXDrive *)drive
					  toDestination: (NSString *)destinationFolder
						  copyFiles: (BOOL)copy;
{
	if ((self = [super init]))
	{
		[self setDrive: drive];
		[self setDestinationFolder: destinationFolder];
		[self setCopyFiles: copy];
	}
	return self;
}

- (void) dealloc
{
	[self setDrive: nil], [_drive release];
	[self setDestinationFolder: nil], [_destinationFolder release];
	[self setImportedDrivePath: nil], [_importedDrivePath release];
	[super dealloc];
}


#pragma mark -
#pragma mark The actual operation, finally

- (void) setDrive: (BXDrive *)newDrive
{
    if (![_drive isEqual: newDrive])
    {
        [_drive release];
        _drive = [newDrive retain];
        
        [self setSourcePath: [newDrive path]];
    }
}

//Automatically populate the destination path the first time we need it,
//based on the drive and destination folder.
- (NSString *) destinationPath
{
    if (![super destinationPath] && [self drive] && [self destinationFolder])
    {
        NSString *driveName		= [[self class] nameForDrive: [self drive]];
        NSString *destination	= [[self destinationFolder] stringByAppendingPathComponent: driveName];
        
        [self setDestinationPath: destination];
    }
    return [super destinationPath];
}

- (void) didPerformOperation
{
    //If nothing went wrong, then populate the imported drive path once we're done.
    if (![self error])
    {
        [self setImportedDrivePath: [self destinationPath]];
    }
    //If the import failed for any reason (including cancellation),
    //then clean up the partial files.
    else
    {
        [self undoTransfer];
    }
}

- (BOOL) succeeded
{
    return [super succeeded] && [self importedDrivePath];
}

- (BOOL) undoTransfer
{
	return [super undoTransfer];
}

@end