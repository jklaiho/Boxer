/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXAppController.h"
#import "BXSession+BXDragDrop.h"
#import "BXSession+BXFileManager.h"
#import "BXEmulator+BXDOSFileSystem.h"
#import "BXEmulator+BXPaste.h"
#import "BXEmulatorErrors.h"
#import "NSWorkspace+BXFileTypes.h"
#import "NSWorkspace+BXMountedVolumes.h"


//Private methods
@interface BXSession ()

- (NSDragOperation) _responseToDroppedFile: (NSString *)filePath;
- (BOOL) _handleDroppedFile: (NSString *)filePath withLaunching: (BOOL)launch;

@end


@implementation BXSession (BXDragDrop)

//Return an array of all filetypes we will accept by drag-drop
+ (NSSet *) droppableFileTypes
{
	return [[BXAppController mountableTypes] setByAddingObjectsFromSet: [BXAppController executableTypes]];
}


//Called by BXDOSWindowController draggingEntered: to figure out what we'd do with dropped files.
- (NSDragOperation) responseToDroppedFiles: (NSArray *)filePaths
{
	NSDragOperation response = NSDragOperationNone;
	for (NSString *filePath in filePaths)
	{
		//Decide what we'd do with this specific file
		response = [self _responseToDroppedFile: filePath];
		//If any files in the pasteboard would be rejected then reject them all, as per the HIG
		if (response == NSDragOperationNone) return response;
	}
	//Otherwise, return whatever we'd do with the last item in the pasteboard
	return response;
}

//Called by BXDOSWindowController draggingEntered: to figure out what we'd do with a dropped string.
- (NSDragOperation) responseToDroppedString: (NSString *)droppedString
{
	if ([[self emulator] canAcceptPastedString: droppedString]) return NSDragOperationCopy;
	else return NSDragOperationNone;
}


//Called by BXDOSWindowController performDragOperation: when files have been drag-dropped onto Boxer.
- (BOOL) handleDroppedFiles: (NSArray *)filePaths withLaunching: (BOOL)launch
{
	BOOL returnValue = NO;
	
	for (NSString *filePath in filePaths)
		returnValue = [self _handleDroppedFile: filePath withLaunching: launch] || returnValue;
	
	//If any dropped files were successfully handled, reactivate Boxer and return focus to the DOS window
    //so that the user can get on with using them.
	if (returnValue)
    {
        [NSApp activateIgnoringOtherApps: YES];
        [[[self DOSWindowController] window] makeKeyAndOrderFront: self];
    }
	return returnValue;
}

//Called by BXDOSWindowController performDragOperation: when a string has been drag-dropped onto Boxer.
- (BOOL) handleDroppedString: (NSString *)droppedString
{
	BOOL returnValue = [[self emulator] handlePastedString: droppedString];
    
	//If the dragged string was successfully handled, reactivate Boxer and return focus to the DOS window.
    if (returnValue)
    {
        [NSApp activateIgnoringOtherApps: YES];
        [[[self DOSWindowController] window] makeKeyAndOrderFront: self];
    }
    return returnValue;
}


#pragma mark -
#pragma mark Private methods

//This method indicates what we'll do with the dropped file, before we handle any actual drop.
- (NSDragOperation) _responseToDroppedFile: (NSString *)filePath
{
	BXEmulator *theEmulator = [self emulator];
	NSWorkspace *workspace	= [NSWorkspace sharedWorkspace];
	
	BOOL isInProcess = [theEmulator isRunningProcess];
	
	//We wouldn't accept any files that aren't on our accepted formats list.
	if (![workspace file: filePath matchesTypes: [[self class] droppableFileTypes]]) return NSDragOperationNone;
	
	//We wouldn't accept any executables if the emulator is running a process already.
	if (isInProcess && [[self class] isExecutable: filePath]) return NSDragOperationNone;
	
	//If the path is already accessible in DOS, and doesn't deserve its own mount point...
	if (![self shouldMountNewDriveForPath: filePath])
	{
		//...then we'd change the working directory to it, if we're not already busy; otherwise we'd reject it.
		return (isInProcess) ? NSDragOperationNone : NSDragOperationLink;
	}
	//If we get this far, it means we'd mount the dropped file as a new drive.
	return NSDragOperationCopy;
}


- (BOOL) _handleDroppedFile: (NSString *)filePath withLaunching: (BOOL)launch
{	
	//First check if we ought to do anything with this file, to be safe
	if ([self _responseToDroppedFile: filePath] == NSDragOperationNone) return NO;
	
	//Keep track of whether we've done anything with the dropped file yet
	BOOL performedAction = NO;
	
	//Make a new mount for the path if we need
	if ([self shouldMountNewDriveForPath: filePath])
	{
        NSError *mountError = nil;
		BXDrive *drive = [self mountDriveForPath: filePath
                                        ifExists: BXDriveReplace
                                         options: BXDefaultDriveMountOptions
                                           error: &mountError];
		if (!drive)
        {
            if (mountError)
            {
                [self presentError: mountError
                    modalForWindow: [self windowForSheet]
                          delegate: nil
                didPresentSelector: NULL
                       contextInfo: NULL];
            }
            return NO; //mount failed, don't continue further
        }
		performedAction = YES;
	}
	
	//Launch the path in the emulator
	if (launch) performedAction = [self openFileAtPath: filePath] || performedAction;
	
	//Report whether or not anything actually happened as a result of the drop
	return performedAction;
}

@end
