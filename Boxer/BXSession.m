/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXSessionPrivate.h"

#import "BXPackage.h"
#import "BXGameProfile.h"
#import "BXBootlegCoverArt.h"
#import "BXDrive.h"
#import "BXAppController.h"
#import "BXDOSWindowControllerLion.h"
#import "BXDOSWindow.h"
#import "BXEmulatorConfiguration.h"
#import "BXCloseAlert.h"

#import "BXEmulator+BXDOSFileSystem.h"
#import "BXEmulator+BXShell.h"
#import "NSWorkspace+BXFileTypes.h"
#import "NSString+BXPaths.h"
#import "UKFNSubscribeFileWatcher.h"
#import "NSWorkspace+BXExecutableTypes.h"
#import "BXInputController.h"

#import "BXAppKitVersionHelpers.h"


#pragma mark -
#pragma mark Constants

//How we will store our gamebox-specific settings in user defaults.
//%@ is the unique identifier for the gamebox.
NSString * const BXGameboxSettingsKeyFormat     = @"BXGameSettings: %@";
NSString * const BXGameboxSettingsNameKey       = @"BXGameName";
NSString * const BXGameboxSettingsProfileKey    = @"BXGameProfile";
NSString * const BXGameboxSettingsProfileVersionKey = @"BXGameProfileVersion";


//The length of time in seconds after which we figure that if the program was
//Windows-only, it would have failed by now. If a program exits before this time,
//then we check if it's a Windows-only program and warn the user.
#define BXWindowsOnlyProgramFailTimeThreshold 0.2

//The length of time in seconds after which we count a program as having run successfully,
//and allow it to auto-quit. If a program exits before this time, we count it as
//a probable startup crash and leave the user at the DOS prompt to diagnose it.
#define BXSuccessfulProgramRunningTimeThreshold 10

//How soon after the program to enter fullscreen, if the run-programs-in-fullscreen toggle
//is enabled. The delay gives the program time to crash andour program panel time to hide.
#define BXAutoSwitchToFullScreenDelay 0.5

//How soon after launching a program to auto-hide the program panel.
//This gives the program time to fail miserably.
#define BXHideProgramPanelDelay 0.1

//How soon after returning to the DOS prompt to display the program panel.
//The delay gives the window time to resize or return from windowed mode.
#define BXShowProgramPanelDelay 0.25


#pragma mark -
#pragma mark Notifications

NSString * const BXSessionWillEnterFullScreenNotification	= @"BXSessionWillEnterFullScreen";
NSString * const BXSessionDidEnterFullScreenNotification	= @"BXSessionDidEnterFullScreen";
NSString * const BXSessionWillExitFullScreenNotification	= @"BXSessionWillExitFullScreen";
NSString * const BXSessionDidExitFullScreenNotification		= @"BXSessionDidExitFullScreen";

NSString * const BXSessionDidLockMouseNotification		= @"BXSessionDidLockMouse";
NSString * const BXSessionDidUnlockMouseNotification	= @"BXSessionDidUnlockMouse";

NSString * const BXWillBeginInterruptionNotification = @"BXWillBeginInterruptionNotification";
NSString * const BXDidFinishInterruptionNotification = @"BXDidFinishInterruptionNotification";


#pragma mark -
#pragma mark Implementation

@implementation BXSession

@synthesize DOSWindowController;
@synthesize gamePackage;
@synthesize emulator;
@synthesize targetPath;
@synthesize lastExecutedProgramPath, lastLaunchedProgramPath;
@synthesize gameProfile;
@synthesize gameSettings;
@synthesize drives, executables, documentation;
@synthesize emulating;
@synthesize paused, autoPaused, interrupted, suspended;
@synthesize userToggledProgramPanel;

#pragma mark -
#pragma mark Helper class methods

+ (BXGameProfile *) profileForPath: (NSString *)path
{
	//Which folder to look in to detect the game we’re running.
	//This will choose any gamebox, Boxer drive folder or floppy/CD volume in the
	//file's path (setting shouldRecurse to YES) if found, falling back on the file's
	//containing folder otherwise (setting shouldRecurse to NO).
	BOOL shouldRecurse = NO;
	NSString *profileDetectionPath = [self gameDetectionPointForPath: path 
											  shouldSearchSubfolders: &shouldRecurse];
	
	//Detect any appropriate game profile for this session
	if (profileDetectionPath)
	{
		//IMPLEMENTATION NOTE: we only scan subfolders of the detection path if it's a gamebox,
		//mountable folder or CD/floppy disk, since these will have a finite and manageable file
		//heirarchy to scan.
		//Otherwise, we restrict our search to just the base folder to avoids massive blowouts
		//if the user opens something big like their home folder or startup disk, and to avoid
		//false positives when opening the DOS Games folder.
		return [BXGameProfile detectedProfileForPath: profileDetectionPath
									searchSubfolders: shouldRecurse];	
	}
	return nil;
}

+ (NSImage *) bootlegCoverArtForGamePackage: (BXPackage *)package withMedium: (BXReleaseMedium)medium
{
	Class <BXBootlegCoverArt> coverArtClass;
	if (medium == BXUnknownMedium)
        medium = [BXGameProfile mediumOfGameAtPath: [package bundlePath]];
    
	switch (medium)
	{
		case BXCDROMMedium:         coverArtClass = [BXJewelCase class];	break;
		case BX525DisketteMedium:	coverArtClass = [BX525Diskette class];	break;
		default:                    coverArtClass = [BX35Diskette class];	break;
	}
	NSString *iconTitle = [package gameName];
	NSImage *icon = [coverArtClass coverArtWithTitle: iconTitle];
	return icon;
}


#pragma mark -
#pragma mark Initialization and cleanup

- (id) init
{
	if ((self = [super init]))
	{
		NSString *defaultsPath = [[NSBundle mainBundle] pathForResource: @"GameDefaults" ofType: @"plist"];
		NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithContentsOfFile: defaultsPath];
		
		[self setDrives: [NSMutableDictionary dictionaryWithCapacity: 10]];
		[self setExecutables: [NSMutableDictionary dictionaryWithCapacity: 10]];
		
		[self setEmulator: [[[BXEmulator alloc] init] autorelease]];
		[self setGameSettings: defaults];
		
		importQueue = [[NSOperationQueue alloc] init];
		scanQueue = [[NSOperationQueue alloc] init];
		watcher = [[UKFNSubscribeFileWatcher alloc] init];
	}
	return self;
}

//Called when opening an existing file
- (id) initWithContentsOfURL: (NSURL *)absoluteURL
                      ofType: (NSString *)typeName
                       error: (NSError **)outError
{
    if ((self = [super initWithContentsOfURL: absoluteURL
                                      ofType: typeName
                                       error: outError]))
    {
        //Start up the emulator as soon as we're ready
        //(Super will call readFromURL:, setFileURL: et. al., fully preparing the session for starting)
        if ([self _shouldStartImmediately]) [self start];
    }
    return self;
}

//Called when opening a new document
- (id) initWithType: (NSString *)typeName
              error: (NSError **)outError
{
    if ((self = [super initWithType: typeName
                              error: outError]))
    {
        //Start up the emulator as soon as we're ready
        //See note above
        if ([self _shouldStartImmediately]) [self start];
    }
    return self;
}

- (void) dealloc
{ 	
	[self setDOSWindowController: nil],	[DOSWindowController release];
	[self setEmulator: nil],			[emulator release];
	[self setGamePackage: nil],			[gamePackage release];
	[self setGameProfile: nil],			[gameProfile release];
	[self setGameSettings: nil],		[gameSettings release];
	[self setTargetPath: nil],			[targetPath release];
	[self setLastExecutedProgramPath: nil],	[lastExecutedProgramPath release];
	[self setLastLaunchedProgramPath: nil],	[lastLaunchedProgramPath release];
	
	[self setDrives: nil],				[drives release];
	[self setExecutables: nil],			[executables release];
	[self setDocumentation: nil],		[documentation release];
		
	[temporaryFolderPath release], temporaryFolderPath = nil;
	
	[scanQueue release], scanQueue = nil;
	[importQueue release], importQueue = nil;
	[watcher release], watcher = nil;
    [MT32MessagesReceived release], MT32MessagesReceived = nil;
	
    [self setSuppressesDisplaySleep: NO];
    
	[super dealloc];
}

- (BOOL) readFromURL: (NSURL *)absoluteURL
			  ofType: (NSString *)typeName
			   error: (NSError **)outError
{
	NSWorkspace *workspace	= [NSWorkspace sharedWorkspace];
	NSString *filePath		= [absoluteURL path];
	
	//Set our target launch path to point to this file, if we don't have a target already
	if (![self targetPath]) [self setTargetPath: filePath];
	
	//Check if the chosen file is located inside a gamebox
	NSString *packagePath	= [workspace parentOfFile: filePath
										matchingTypes: [NSSet setWithObject: @"net.washboardabs.boxer-game-package"]];
	
	//If the fileURL is located inside a gamebox, load the gamebox and use the gamebox itself as the fileURL.
	//This way, the DOS window will show the gamebox as the represented file, and our Recent Documents
	//list will likewise show the gamebox instead.
	if (packagePath)
	{
		BXPackage *package = [[BXPackage alloc] initWithPath: packagePath];
		[self setGamePackage: package];
		
		//If we opened the package directly, check if it has a target of its own;
		//if so, use that as our target path instead.
		if ([[self targetPath] isEqualToString: packagePath])
		{
			NSString *packageTarget = [package targetPath];
			if (packageTarget) [self setTargetPath: packageTarget];
		}
		[package release];
		
		//FIXME: move the fileURL reset out of here and into a later step: we can't rely on the order
		//in which NSDocument's setFileURL/readFromURL methods are called.
		[self setFileURL: [NSURL fileURLWithPath: packagePath]];
	}
    
	return YES;
}

- (void) setGamePackage: (BXPackage *)package
{	
	if (package != gamePackage)
	{
		[gamePackage release];
		gamePackage = [package retain];
		
		//Also load up the settings and game profile for this gamebox
		if (gamePackage)
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSString *defaultsKey = [NSString stringWithFormat: BXGameboxSettingsKeyFormat, [gamePackage gameIdentifier], nil];
			
			NSDictionary *gameboxSettings = [defaults objectForKey: defaultsKey];
			
			//Merge the loaded values in, rather than replacing the default settings altogether.
			[gameSettings addEntriesFromDictionary: gameboxSettings];
            
            //If we don't already have a game profile assigned,
            //then load any previously detected game profile for this game
            if (![self gameProfile])
            {
                NSString *identifier        = [gameSettings objectForKey: BXGameboxSettingsProfileKey];
                NSString *profileVersion    = [gameSettings objectForKey: BXGameboxSettingsProfileVersionKey];
                
                if (identifier && profileVersion)
                {
                    //Check if the profile catalogue version under which the detected profile was saved
                    //is older than the current catalogue version. If it is, then we'll redetect rather
                    //than use a profile detected from a previous version.
                    BOOL profileOutdated = [profileVersion compare: [BXGameProfile catalogueVersion]
                                                           options: NSNumericSearch] == NSOrderedAscending;

                    if (!profileOutdated)
                    {
                        //Tweak: don't use saved profiles in debug mode, as this interferes with development
                        //of detection rules.
#ifndef BOXER_DEBUG
                        BXGameProfile *profile = [BXGameProfile profileWithIdentifier: identifier];
                        //NSLog(@"Reusing existing profile with identifier: %@, %@", identifier, profile);
                        [self setGameProfile: profile];
#endif
                    }
                }
            }
		}
	}
}

- (void) setGameProfile: (BXGameProfile *)profile
{
    if (![[self gameProfile] isEqual: profile])
    {
        [gameProfile release];
        gameProfile = [profile retain];
        
        //Save the profile into our game settings so that we can retrieve it quicker later
        if (gameProfile && [self _shouldPersistGameProfile: gameProfile])
        {
            NSString *identifier = [gameProfile identifier];
            if (identifier)
            {
                [gameSettings setObject: identifier forKey: BXGameboxSettingsProfileKey];
                
                //Also store the catalogue version under which the game profile was decided,
                //so that we can invalidate old detections whenever the catalogue is updated.
                [gameSettings setObject: [BXGameProfile catalogueVersion] forKey: BXGameboxSettingsProfileVersionKey];
            }
        }
    }
}

- (void) setEmulator: (BXEmulator *)newEmulator
{
	if (newEmulator != emulator)
	{
		if (emulator)
		{
			emulator.delegate = nil;
			[emulator.videoHandler unbind: @"aspectCorrected"];
			[emulator.videoHandler unbind: @"filterType"];
			
            [emulator unbind: @"masterVolume"];
            
			[self _deregisterForPauseNotifications];
			[self _deregisterForFilesystemNotifications];
		}
		
		[emulator release];
		emulator = [newEmulator retain];
		
		if (newEmulator)
		{	
			newEmulator.delegate = (id)self;
			
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            
            [newEmulator bind: @"masterVolume" toObject: [NSApp delegate] withKeyPath: @"effectiveVolume" options: nil];
            
			[newEmulator.videoHandler bind: @"aspectCorrected" toObject: defaults withKeyPath: @"aspectCorrected" options: nil];
			[newEmulator.videoHandler bind: @"filterType" toObject: defaults withKeyPath: @"filterType" options: nil];
			
			[self _registerForFilesystemNotifications];
			[self _registerForPauseNotifications];
		}
	}
}

- (NSString *) activeProgramPath
{
    if ([self lastExecutedProgramPath]) return [self lastExecutedProgramPath];
    else return [self lastLaunchedProgramPath];
}

- (NSString *) currentPath
{
	if ([self activeProgramPath]) return [self activeProgramPath];
	else return [[self emulator] pathOfCurrentDirectory];
}

#pragma mark -
#pragma mark Window management

- (void) makeWindowControllers
{
	BXDOSWindowController *controller;
	if (isRunningOnLionOrAbove())
	{
		controller = [[BXDOSWindowControllerLion alloc] initWithWindowNibName: @"DOSWindow"];
	}
	else
	{
		controller = [[BXDOSWindowController alloc] initWithWindowNibName: @"DOSWindow"];
	}
	
	[self addWindowController:		controller];
	[self setDOSWindowController:	controller];
	
	[controller setShouldCloseDocument: YES];
	
	[controller release];
}

- (void) removeWindowController: (NSWindowController *)windowController
{
	if (windowController == [self DOSWindowController])
	{
		[self setDOSWindowController: nil];
	}
	[super removeWindowController: windowController];
}

- (void) setUserToggledProgramPanel: (BOOL)flag
{
	//Finesse: ignore program toggles while a program is running, only pay attention
	//when the user hides the program panel at the DOS prompt. This makes the behaviour
	//feel more 'natural', in that the panel will stay hidden while the user is mucking
	//around at the prompt but will return as soon as the user exits.
	if ([emulator isAtPrompt]) userToggledProgramPanel = flag;
}

#pragma mark -
#pragma mark Flow control

- (void) start
{
	//We schedule our internal _startEmulator method to be called separately on the main thread,
	//so that it doesn't block completion of whatever UI event led to this being called.
	//This prevents menu highlights from getting 'stuck' because of DOSBox's main loop blocking
	//the thread.
	
	if (!hasStarted) [self performSelector: @selector(_startEmulator)
								withObject: nil
								afterDelay: 0.1];
	
	//So we don't try to restart the emulator
	hasStarted = YES;
}

//Cancel the DOSBox emulator
- (void) cancel
{
    [[self emulator] cancel];
    //Flag ourselves early as no longer emulating: this
    //disables certain parts of our behaviour to prevent
    //interference while the emulator is shutting down.
    [self setEmulating: NO];
}


#pragma mark -
#pragma mark Handling document closing

//Tell the emulator to close itself down when the document closes
- (void) close
{
	//Ensure that the document close procedure only happens once, no matter how many times we close
	if (!isClosing)
	{
		isClosing = YES;
		[self cancel];
		
		[self synchronizeSettings];
		[self _cleanup];
		
		[super close];
	}
}

//Overridden solely so that NSDocumentController will call canCloseDocumentWithDelegate:
//in the first place. This otherwise should have no effect and should not show up in the UI.
- (BOOL) isDocumentEdited
{
    return [[self emulator] isRunningProcess] || [self isImportingDrives];
}

//Overridden to display our own custom confirmation alert instead of the standard NSDocument one.
- (void) canCloseDocumentWithDelegate: (id)delegate
				  shouldCloseSelector: (SEL)shouldCloseSelector
						  contextInfo: (void *)contextInfo
{
	//Define an invocation for the callback, which has the signature:
	//- (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
	NSMethodSignature *signature = [delegate methodSignatureForSelector: shouldCloseSelector];
	NSInvocation *callback = [NSInvocation invocationWithMethodSignature: signature];
	[callback setSelector: shouldCloseSelector];
	[callback setTarget: delegate];
	[callback setArgument: &self atIndex: 2];
	[callback setArgument: &contextInfo atIndex: 4];
	
	BOOL hasActiveImports = [self isImportingDrives];
	
	
	//We confirm the close if a process is running and if we're not already shutting down
	BOOL shouldConfirm = hasActiveImports ||
						(![[NSUserDefaults standardUserDefaults] boolForKey: @"suppressCloseAlert"]
						  && [emulator isRunningProcess]
						  && ![emulator isCancelled]);
	
	if (shouldConfirm)
	{
		//Show our custom close alert, passing it the callback so we can complete
		//our response down in _closeAlertDidEnd:returnCode:contextInfo:
		
		BXCloseAlert *alert;
		if (hasActiveImports) 
			alert = [BXCloseAlert closeAlertWhileImportingDrives: self];
		else
			alert = [BXCloseAlert closeAlertWhileSessionIsEmulating: self];
		
		[alert beginSheetModalForWindow: [self windowForSheet]
						  modalDelegate: self
						 didEndSelector: @selector(_closeAlertDidEnd:returnCode:contextInfo:)
							contextInfo: [callback retain]];
	}
	else
	{
		BOOL shouldClose = YES;
		//Otherwise we can respond directly: call the callback straight away with YES for shouldClose:
		[callback setArgument: &shouldClose atIndex: 3];
		[callback invoke];
	}
}

- (void) _closeAlertDidEnd: (BXCloseAlert *)alert
				returnCode: (int)returnCode
			   contextInfo: (NSInvocation *)callback
{
	if ([alert showsSuppressionButton] && [[alert suppressionButton] state] == NSOnState)
		[[NSUserDefaults standardUserDefaults] setBool: YES forKey: @"suppressCloseAlert"];
	
	BOOL shouldClose = (returnCode == NSAlertFirstButtonReturn);
	[callback setArgument: &shouldClose atIndex: 3];
	[callback invoke];
	
	//Release the previously-retained callback
	[callback release];
}

- (void) _windowsOnlyProgramCloseAlertDidEnd: (BXCloseAlert *)alert
								  returnCode: (int)returnCode
								 contextInfo: (void *)contextInfo
{
	if (returnCode == NSAlertFirstButtonReturn)
	{
		[self close];
	}
}

//Save our configuration changes to disk before exiting
- (void) synchronizeSettings
{
	if ([self isGamePackage])
	{
		//Go through the settings working out which ones we should store in user defaults,
		//and which ones we should store in the gamebox's configuration file.
		BXEmulatorConfiguration *runtimeConf = [BXEmulatorConfiguration configuration];
		
		//These are the settings we want to keep in the configuration file
		NSNumber *CPUSpeed      = [gameSettings objectForKey: @"CPUSpeed"];
		NSNumber *coreMode		= [gameSettings objectForKey: @"coreMode"];
		NSNumber *strictGameportTiming = [gameSettings objectForKey: @"strictGameportTiming"];
		
		if (coreMode)
		{
			NSString *coreString = [BXEmulator configStringForCoreMode: [coreMode integerValue]];
			[runtimeConf setValue: coreString forKey: @"core" inSection: @"cpu"];
		}
		
		if (strictGameportTiming)
		{
			NSString *timingString = [BXEmulator configStringForGameportTimingMode: [strictGameportTiming integerValue]];
			[runtimeConf setValue: timingString forKey: @"timed" inSection: @"joystick"];
		}
		
		if (CPUSpeed)
		{
            NSInteger speed = [CPUSpeed integerValue];
            BOOL isAutoSpeed = (speed == BXAutoSpeed);
			NSString *cyclesString = [BXEmulator configStringForFixedSpeed: speed
																	isAuto: isAutoSpeed];
			
			[runtimeConf setValue: cyclesString forKey: @"cycles" inSection: @"cpu"];
		}
		
		//Strip out these settings once we're done, so we won't preserve them in user defaults
		NSArray *confSettings = [NSArray arrayWithObjects: @"CPUSpeed", @"coreMode", @"strictGameportTiming", nil];
		[gameSettings removeObjectsForKeys: confSettings];

		
		//Persist the gamebox-specific configuration into the gamebox's configuration file.
		NSString *configPath = [[self gamePackage] configurationFilePath];
		[self _saveConfiguration: runtimeConf toFile: configPath];
		
		//Save whatever's left into user defaults.
		if ([gameSettings count])
		{
			//Add the gamebox name into the settings, to make it easier to identify to which gamebox the record belongs
			[gameSettings setObject: [gamePackage gameName] forKey: BXGameboxSettingsNameKey];
			
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSString *defaultsKey = [NSString stringWithFormat: BXGameboxSettingsKeyFormat, [[self gamePackage] gameIdentifier], nil];
			[defaults setObject: gameSettings forKey: defaultsKey];			
		}
	}
}
 

#pragma mark -
#pragma mark Describing the document/process

- (NSString *) displayName
{
	if ([self isGamePackage])	return [[self gamePackage] gameName];
	else if ([self fileURL])	return [super displayName];
	else						return [self processDisplayName];
}

- (NSString *) processDisplayName
{
	NSString *processName = nil;
	if ([emulator isRunningProcess])
	{
		//Use the active program name where possible;
		//Failing that, fall back on the original process name
		if ([self activeProgramPath]) processName = [[self activeProgramPath] lastPathComponent];
		else processName = [emulator processName];
	}
	return processName;
}


#pragma mark -
#pragma mark Introspecting the gamebox

- (BOOL) isGamePackage	{ return ([self gamePackage] != nil); }

- (NSImage *)representedIcon
{
	if ([self isGamePackage])
	{
		NSImage *icon = [[self gamePackage] coverArt];
		return icon;
	}
	else return nil;
}

- (void) setRepresentedIcon: (NSImage *)icon
{
	BXPackage *thePackage = [self gamePackage];
	if (thePackage)
	{
		[thePackage setCoverArt: icon];
				
		//Force our file URL to appear to change, which will update icons elsewhere in the app 
		[self setFileURL: [self fileURL]];
	}
}


- (NSArray *) documentation
{
	//Generate our documentation cache the first time it is needed
	if (!documentation)
	{
		NSWorkspace *workspace	= [NSWorkspace sharedWorkspace];
		
		NSArray *docPaths = [[[self gamePackage] documentation] sortedArrayUsingSelector: @selector(pathDepthCompare:)];
		
		NSMutableSet *docNames = [[NSMutableSet alloc] initWithCapacity: [docPaths count]];

		documentation = [[NSMutableArray alloc] initWithCapacity: [docPaths count]];
		
		for (NSString *path in docPaths)
		{
			path = [path stringByStandardizingPath];
			NSString *fileName = [path lastPathComponent];
			
			//If we already have a document with this name, skip it so we don't offer ambiguous choices
			//TODO: this filtering should be done downstream in the UI controller, it's not our call
			if (![docNames containsObject: fileName])
			{
				NSImage *icon		= [workspace iconForFile: path];
				NSDictionary *data	= [NSDictionary dictionaryWithObjectsAndKeys:
									   path,	@"path",
									   icon,	@"icon",
									   nil];
				
				[docNames addObject: fileName];
				[documentation addObject: data];
			}
		}
		[docNames release];
	}
	return documentation;
}

+ (NSSet *) keyPathsForValuesAffectingIsGamePackage		{ return [NSSet setWithObject: @"gamePackage"]; }
+ (NSSet *) keyPathsForValuesAffectingRepresentedIcon	{ return [NSSet setWithObject: @"gamePackage.coverArt"]; }
+ (NSSet *) keyPathsForValuesAffectingCurrentPath       { return [NSSet setWithObjects: @"activeProgramPath", @"emulator.pathOfCurrentDirectory", nil]; }
+ (NSSet *) keyPathsForValuesAffectingActiveProgramPath { return [NSSet setWithObjects: @"lastExecutedProgramPath", @"lastLaunchedProgramPath", nil]; }

#pragma mark -
#pragma mark Emulator delegate methods and notifications

- (void) emulatorDidInitialize: (NSNotification *)notification
{
	//Flag that we are now officially emulating.
	//We wait until now because at this point the emulator is in
	//a properly initialized state, and can respond properly to
	//commands and settings changes.
	//TODO: move this decision off to the emulator itself.
	self.emulating = YES;
    
    //Start preventing the display from going to sleep
    [self _syncSuppressesDisplaySleep];
}

- (void) emulatorDidFinish: (NSNotification *)notification
{
	//Flag that we're no longer emulating
	self.emulating = NO;
    //Turn off display-sleep suppression
    [self _syncSuppressesDisplaySleep];
	
	//Clear our drive and program caches
	self.lastExecutedProgramPath = nil;
    self.lastLaunchedProgramPath = nil;
	
	self.drives = nil;

	//Clear the final rendered frame
	[self.DOSWindowController updateWithFrame: nil];
	
	//Close the document once we're done, if desired
	if ([self _shouldCloseOnEmulatorExit]) [self close];
}

- (NSArray *) configurationPathsForEmulator: (BXEmulator *)emulator
{
    NSMutableArray *configPaths = [[NSMutableArray alloc] initWithCapacity: 4];
    
    //Load Boxer's baseline configuration first.
    NSBundle *appBundle = [NSBundle mainBundle];
    [configPaths addObject: [appBundle pathForResource: @"Preflight"
                                                ofType: @"conf"
                                           inDirectory: @"Configurations"]];

	//If we don't have a manually-defined game-profile already,
    //detect the game profile from our target path and set it now.
	if ([self targetPath] && ![self gameProfile])
	{
		BXGameProfile *profile = [[self class] profileForPath: [self targetPath]];
        
        //If no specific game can be found, then store it explicitly as an unknown game.
        if (!profile) profile = [BXGameProfile genericProfile];
		[self setGameProfile: profile];
	}
	
	//Load the appropriate configuration files from our game profile.
    for (NSString *confName in [[self gameProfile] configurations])
    {
        NSString *profileConf = [appBundle pathForResource: confName
                                                    ofType: @"conf"
                                               inDirectory: @"Configurations"];
        
        if (profileConf) [configPaths addObject: profileConf];
        else NSLog(@"Missing configuration profile: %@", confName);
    }
	
	//Next, load the gamebox's own configuration file if it has one.
    NSString *packageConf = [[self gamePackage] configurationFile];
    if (packageConf) [configPaths addObject: packageConf];
    
	
    //Last but not least, load Boxer's launch configuration.
    [configPaths addObject: [appBundle pathForResource: @"Launch"
                                                ofType: @"conf"
                                           inDirectory: @"Configurations"]];
    
    return [configPaths autorelease];
}

- (void) runPreflightCommandsForEmulator: (BXEmulator *)theEmulator
{
	if (!hasConfigured)
	{
        //If the Option key is held down during the startup process, skip the default program.
		CGEventFlags currentModifiers = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
		userSkippedDefaultProgram = (currentModifiers & NSAlternateKeyMask) == NSAlternateKeyMask;
        
        //If we'll be starting up with a target program, clear the screen
        //at the start of the autoexec sequence.
        if (!userSkippedDefaultProgram && self.targetPath && [[self class] isExecutable: self.targetPath])
        {
            [theEmulator clearScreen];
        }
        
		[self _mountDrivesForSession];
		
		//Flag that we have completed our initial game configuration.
		hasConfigured = YES;
	}
}

- (void) runLaunchCommandsForEmulator: (BXEmulator *)theEmulator
{
	hasLaunched = YES;
    
    //Do any just-in-time configuration, which should override all previous startup stuff.
	NSNumber *frameskip = [self.gameSettings objectForKey: @"frameskip"];
	if (frameskip && [self validateValue: &frameskip forKey: @"frameskip" error: nil])
		[self setValue: frameskip forKey: @"frameskip"];
	
	
	//After all preflight configuration has finished, go ahead and open whatever
    //file or folder we're pointing at.
	NSString *target = self.targetPath;
	if (target)
	{
        //If the Option key is held down during the startup process, skip the default program.
        //(Repeated from runPreflightCommandsForEmulator: above, in case the user started
        //holding the key down in between.)
        if (!userSkippedDefaultProgram)
        {
            CGEventFlags currentModifiers = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
            userSkippedDefaultProgram = (currentModifiers & NSAlternateKeyMask) == NSAlternateKeyMask;
        }
        
		//If the Option key was held down, don't launch the gamebox's target;
		//Instead, just switch to its parent folder.
		if (userSkippedDefaultProgram && [[self class] isExecutable: target])
		{
			target = [target stringByDeletingLastPathComponent];
		}
		[self openFileAtPath: target];
	}
    
    //Clear the program-skipping flag for next launch.
    userSkippedDefaultProgram = NO;
}

- (void) emulator: (BXEmulator *)theEmulator didFinishFrame: (BXFrameBuffer *)frame
{
	[self.DOSWindowController updateWithFrame: frame];
}

- (NSSize) maxFrameSizeForEmulator: (BXEmulator *)theEmulator
{
	return self.DOSWindowController.maxFrameSize;
}

- (NSSize) viewportSizeForEmulator: (BXEmulator *)theEmulator
{
	return self.DOSWindowController.viewportSize;
}

- (void) processEventsForEmulator: (BXEmulator *)theEmulator
{
    //Only pump the event queue ourselves if the emulator has taken over the main thread.
    if (!theEmulator.isConcurrent)
        [self _processEventsUntilDate: nil];
}

- (void) emulatorWillStartRunLoop: (BXEmulator *)theEmulator {}
- (void) emulatorDidFinishRunLoop: (BXEmulator *)theEmulator {}

- (void) emulatorWillStartProgram: (NSNotification *)notification
{
    //Flag that the program the user launched is now executing.
    executingLaunchedProgram = YES;
    
	//Don't set the active program if we already have one: this way, we keep
	//track of when a user launches a batch file and don't immediately discard
	//it in favour of the next program the batch-file runs
	if (![self lastExecutedProgramPath])
	{
		NSString *programPath = [[notification userInfo] objectForKey: @"localPath"];
        
        if ([programPath length])
        {
            [self setLastExecutedProgramPath: programPath];
		}
        
		//If the user hasn't manually opened/closed the program panel themselves,
		//and we don't need to ask the user what to do with this program, then
		//automatically hide the program panel shortly after launching.
		if (![self userToggledProgramPanel] && ![self _leaveProgramPanelOpenAfterLaunch])
		{
			[NSObject cancelPreviousPerformRequestsWithTarget: [self DOSWindowController]
													 selector: @selector(showProgramPanel:)
													   object: self];
			
			[[self DOSWindowController] performSelector: @selector(hideProgramPanel:)
											 withObject: self
											 afterDelay: BXHideProgramPanelDelay];
		}
	}
	
	//Track how long this program has run for
	programStartTime = [NSDate timeIntervalSinceReferenceDate];
    
    //Enable/disable display-sleep suppression
    [self _syncSuppressesDisplaySleep];
}

- (void) emulatorDidFinishProgram: (NSNotification *)notification
{
	//Clear the last executed program when a startup program or 'non-defaultable'
    //program finishes. This way, programWillStart: won't hang onto programs
    //we can't use as the default, such as autoexec commands or dispatch batchfiles.
	//(Note that the last executed program is always cleared down in didReturnToShell:)
	NSString *executedPath = [self lastExecutedProgramPath];
    BOOL executedPathCanBeDefault = (executedPath && hasLaunched && [[self gamePackage] validateTargetPath: &executedPath error: nil]);
	if (!executedPathCanBeDefault)
	{
		[self setLastExecutedProgramPath: nil];
        //TODO: do we need to extend this to lastLaunchedProgramPath too?
        //The logic here is pretty damn fuzzy.
	}
	
	//Check the running time of the program. If it was suspiciously short,
	//then check for possible error conditions that we can inform the user about.
	NSTimeInterval programRunningTime = [NSDate timeIntervalSinceReferenceDate] - programStartTime; 
	if (programRunningTime < BXWindowsOnlyProgramFailTimeThreshold)
	{
		//If this was the target program for this launch, then
		//warn if the program is Windows-only.
		//(we only do this for the target program because we
		//don't want to bother the user if they're just trying
		//out programs at the DOS prompt)
		NSString *programPath = [[notification userInfo] objectForKey: @"localPath"];
		if ([programPath length] && [programPath isEqualToString: [self targetPath]])
		{
			BXExecutableType programType = [[NSWorkspace sharedWorkspace] executableTypeAtPath: programPath error: NULL];
			
			if (programType == BXExecutableTypeWindows)
			{
				BXCloseAlert *alert = [BXCloseAlert closeAlertAfterWindowsOnlyProgramExited: programPath];
				[alert beginSheetModalForWindow: [self windowForSheet]
								  modalDelegate: self
								 didEndSelector: @selector(_windowsOnlyProgramCloseAlertDidEnd:returnCode:contextInfo:)
									contextInfo: NULL];
			}
		}
	}
}

- (void) emulatorDidReturnToShell: (NSNotification *)notification
{
	//If we should close after exiting, then close down the application now
	if ([self _shouldCloseOnProgramExit])
	{
		[self close];
	}
	
	//If a program has been properly launched, clear the active program.
    //(We don't want to clear it if we've nipped back to the DOS prompt
    //while we're still in the process of launching the program.)
    if (executingLaunchedProgram)
	{
        executingLaunchedProgram = NO;
        [self setLastExecutedProgramPath: nil];
        [self setLastLaunchedProgramPath: nil];
	}
    
    //Clear our cache of sent MT-32 messages on behalf of BXAudioControls.
    [MT32MessagesReceived removeAllObjects];
    
    //Explicitly disable numpad simulation upon returning to the DOS prompt.
    //Disabled for now until we can record that the user has toggled the option while at the DOS prompt,
    //and conditionally leave it on in that case, to prevent it switching off when executing commands. 
    //[[[self DOSWindowController] inputController] setSimulatedNumpadActive: NO];
    
        
	//Show the program chooser after returning to the DOS prompt, as long
	//as the program chooser hasn't been manually toggled from the DOS prompt
	if ([self isGamePackage] && ![self userToggledProgramPanel])
	{
		[NSObject cancelPreviousPerformRequestsWithTarget: [self DOSWindowController]
												 selector: @selector(hideProgramPanel:)
												   object: self];
		
		//Show only after a delay, so that the window has time to resize after quitting the game
		[[self DOSWindowController] performSelector: @selector(showProgramPanel:)
										 withObject: self
										 afterDelay: BXShowProgramPanelDelay];
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey: @"startUpInFullScreen"])
        {
            //If we automatically switched into fullscreen at startup, then drop out of
            //fullscreen mode when we return to the prompt in order to show the program panel.
            [[[self DOSWindowController] window] exitFullScreen: self];
        }
	}

    //Enable/disable display-sleep suppression
    [self _syncSuppressesDisplaySleep];
}

- (void) emulatorDidBeginGraphicalContext: (NSNotification *)notification
{
	//Tweak: only switch into fullscreen mode if we don't need to prompt
	//the user about choosing a default program.
	if ([[NSUserDefaults standardUserDefaults] boolForKey: @"startUpInFullScreen"] &&
		![self _leaveProgramPanelOpenAfterLaunch])
	{
		//Switch to fullscreen mode automatically after a brief delay:
		//This will be cancelled if the context exits within that time,
		//in case of a program that crashes early.
		[[[self DOSWindowController] window] performSelector: @selector(enterFullScreen:) 
                                                  withObject: self
                                                  afterDelay: BXAutoSwitchToFullScreenDelay];
	}
}

- (void) emulatorDidFinishGraphicalContext: (NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget: [[self DOSWindowController] window]
											 selector: @selector(enterFullScreen:)
											   object: self];
}

- (void) emulatorDidChangeEmulationState: (NSNotification *)notification
{
	//These reside in BXEmulatorControls, as should this function, but so be it
	[self willChangeValueForKey: @"sliderSpeed"];
	[self didChangeValueForKey: @"sliderSpeed"];
	
	[self willChangeValueForKey: @"frameskip"];
	[self didChangeValueForKey: @"frameskip"];
	
	[self willChangeValueForKey: @"dynamic"];
	[self didChangeValueForKey: @"dynamic"];	
}


#pragma mark -
#pragma mark Private methods

- (void) _processEventsUntilDate: (NSDate *)requestedDate
{
    //Implementation note: in a better world, this code wouldn't be here as event
	//dispatch is normally done automatically by NSApplication at opportune moments.
	//However, DOSBox's emulation loop takes over the application's main thread,
	//leaving no time for events to get processed and dispatched.
	//Hence in each iteration of DOSBox's run loop, we pump NSApplication's event
	//queue for all pending events and send them on their way.
    
    //Once BXEmulator is running in its own thread/process, this will be unnecessary
    //and we can ditch it altogether.
	
	//Bugfix: if we are in the process of shutting down, then don't dispatch events:
	//NSApp may not know yet that our window has closed, and will crash when trying
	//send events to it. This isn't a bug per se but an edge-case with the
	//NSWindow/NSDocument close flow.
	
    NSEvent *event;
    [requestedDate retain];
    
	NSDate *untilDate = [self isSuspended] ? [NSDate distantFuture] : requestedDate;
	
	while (!isClosing && (event = [NSApp nextEventMatchingMask: NSAnyEventMask
													 untilDate: untilDate
														inMode: NSDefaultRunLoopMode
													   dequeue: YES]))
	{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        //Listen for key-up events for our fast-forward key and handle them ourselves.
        //Swallow all key-down events while this is happening.
        //IMPLEMENTATION NOTE: this is essentially a standard Cocoa event-listening loop
        //turned inside out, so that the emulation will keep running 'around' our listening.
        if (waitingForFastForwardRelease)
        {
            if (event.type == NSKeyUp)
                [self releaseFastForward: self];
            else if (event.type == NSKeyDown)
                event = nil;
        }
        
        if (event)
            [NSApp sendEvent: event];
		
		//If we're suspended, keep dispatching events until we are unpaused;
        //otherwise, exit once our original requested date has passed (which
        //will be after the first batch of events has been processed,
        //if requestedDate was nil or in the past.)
		untilDate = [self isSuspended] ? [NSDate distantFuture] : requestedDate;
        
        [pool drain];
	}
    
    [requestedDate release];
}

#pragma mark -
#pragma mark Behavioural modifiers

- (BOOL) _shouldPersistGameProfile: (BXGameProfile *)profile
{
    return YES;
}

- (BOOL) _shouldCloseOnEmulatorExit { return YES; }
- (BOOL) _shouldStartImmediately { return YES; }

- (BOOL) _shouldCloseOnProgramExit
{
	//Don't close if the auto-close preference is disabled for this gamebox
	if (![[gameSettings objectForKey: @"closeOnExit"] boolValue]) return NO;
	
	//Don't close if the user skipped the startup program in order to start up at the DOS prompt
	if (userSkippedDefaultProgram) return NO;
	
	//Don't close if we've been running a program other than the default program for the gamebox
	if (![[self activeProgramPath] isEqualToString: [[self gamePackage] targetPath]]) return NO;
	
	//Don't close if there are drive imports in progress
	if ([self isImportingDrives]) return NO;
	
	//Don't close if the last program quit suspiciously early, since this may be a crash
	NSTimeInterval executionTime = [NSDate timeIntervalSinceReferenceDate] - programStartTime;
	if (executionTime < BXSuccessfulProgramRunningTimeThreshold) return NO;
	
	//Don't close if the user is currently holding down the Option key override
	CGEventFlags currentModifiers = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
	BOOL optionKeyDown = (currentModifiers & NSAlternateKeyMask) == NSAlternateKeyMask;
	if (optionKeyDown) return NO;
	
	//If we get this far then go right ahead and die
	return YES;
}

//We leave the panel open when we don't have a default program already,
//and can adopt the current program as the default program. This way
//we can ask the user what they want to do with the program.
- (BOOL) _leaveProgramPanelOpenAfterLaunch
{
	NSString *activePath = [[[self activeProgramPath] copy] autorelease];
	return ![gamePackage targetPath] && [gamePackage validateTargetPath: &activePath error: NULL];
}

- (void) _startEmulator
{	
	//Set the emulator's current working directory relative to whatever we're opening
	if ([self fileURL])
	{
		NSString *filePath = [[self fileURL] path];
		BOOL isFolder = NO;
		if ([[NSFileManager defaultManager] fileExistsAtPath: filePath isDirectory: &isFolder])
		{
			//If we're opening a folder/gamebox, use that as the base path; if we're opening
			//a program or disc image, use its containing folder as the base path instead.
			NSString *basePath = (isFolder) ? filePath : [filePath stringByDeletingLastPathComponent];
			[[self emulator] setBasePath: basePath];
		}
	}
	
	//Start up the emulator itself.
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"useMultithreadedEmulation"])
        [self.emulator performSelectorInBackground: @selector(start) withObject: nil];
    else
        [self.emulator start];
}

- (void) _mountDrivesForSession
{
	BXPackage *package = [self gamePackage];
    
    if (package)
	{
        //TODO: deal with any mounting errors that occurred. Since all this happens automatically
        //during startup, we can't give errors straight to the user as they will seem cryptic.
        
		//Mount the game package as a new hard drive, at drive C.
		//(This may get replaced below by a custom bundled C volume;
        //we do it now to reserve drive C so that it doesn't get autoassigned.)
		BXDrive *packageDrive = [BXDrive hardDriveFromPath: [package gamePath] atLetter: @"C"];
        [packageDrive setTitle: NSLocalizedString(@"Game Drive", @"The display title for the gamebox’s C drive.")];
        
		packageDrive = [self mountDrive: packageDrive
                               ifExists: BXDriveReplace
                                options: BXBundledDriveMountOptions
                                  error: nil];
        		
		//Then, mount any extra volumes included in the game package
		NSMutableArray *packageVolumes = [NSMutableArray arrayWithCapacity: 10];
		[packageVolumes addObjectsFromArray: [package floppyVolumes]];
		[packageVolumes addObjectsFromArray: [package hddVolumes]];
		[packageVolumes addObjectsFromArray: [package cdVolumes]];
		
		BOOL hasProperDriveC = NO;
        for (NSString *volumePath in packageVolumes)
		{
			BXDrive *bundledDrive = [BXDrive driveFromPath: volumePath atLetter: nil];
            
			//If a bundled drive was explicitly set to use drive C,
            //then replace our original C package-drive with it
			if (!hasProperDriveC && [[bundledDrive letter] isEqualToString: [packageDrive letter]])
			{
                [bundledDrive setTitle: [packageDrive title]];
                
                BXDrive *mountedDrive = [self mountDrive: bundledDrive
                                                ifExists: BXDriveReplace
                                                 options: BXDriveForceUnmounting | BXDriveRemoveExistingFromQueue
                                                   error: nil];
                
                if (mountedDrive)
                {
				    //Rewrite our target to point to the new C drive, if it was pointing to the old one
                    if ([[self targetPath] isEqualToString: [packageDrive path]])
                        [self setTargetPath: volumePath];
                    
                    //Don't look any further for a C drive
                    hasProperDriveC = YES;
                    
                    //Aaand use this as our package drive from here on
                    packageDrive = bundledDrive;
				}
			}
            else
            {
                [self mountDrive: bundledDrive
                        ifExists: BXDriveQueue
                         options: BXBundledDriveMountOptions
                           error: nil];
            }
		}
	}
	
	//Automount all currently mounted floppy and CD-ROM volumes.
	[self mountFloppyVolumesWithError: nil];
	[self mountCDVolumesWithError: nil];
	
	//Mount our internal DOS toolkit and temporary drives
	[self mountToolkitDriveWithError: nil];
    if (!gameProfile || [gameProfile mountTempDrive])
        [self mountTempDriveWithError: nil];
    
    //If the game needs a CD-ROM to be present, then mount a dummy CD drive
    //if necessary.
    if ([gameProfile requiresCDROM])
        [self mountDummyCDROMWithError: nil];
    
	
	//Once all regular drives are in place, check if our target program/folder
    //is now accessible in DOS: if not, add another drive allowing access to it.
	if ([self targetPath])
	{
        if ([self shouldMountNewDriveForPath: targetPath])
        {
            //Unlike the drives built into the gamebox, we do actually
            //want to show errors if something goes wrong here.
		    NSError *mountError = nil;
            [self mountDriveForPath: targetPath
                           ifExists: BXDriveReplace
                            options: BXTargetMountOptions
                              error: &mountError];
            
            if (mountError)
            {
                [self presentError: mountError
                    modalForWindow: [self windowForSheet]
                          delegate: nil
                didPresentSelector: NULL
                       contextInfo: NULL];
            }
        }
	}
}

- (void) _saveConfiguration: (BXEmulatorConfiguration *)configuration toFile: (NSString *)filePath
{
	NSFileManager *manager = [NSFileManager defaultManager];
	BOOL fileExists = [manager fileExistsAtPath: filePath];
	
	//Save the configuration if any changes have been made, or if the file at that path does not exist.
	if (!fileExists || ![configuration isEmpty])
	{
		BXEmulatorConfiguration *gameboxConf = [BXEmulatorConfiguration configurationWithContentsOfFile: filePath error: nil];
		
		//If a configuration file exists at that path already, then merge
		//the changes with its existing settings.
		if (gameboxConf)
		{
			[gameboxConf addSettingsFromConfiguration: configuration];
		}
		//Otherwise, use the runtime configuration as our basis
		else gameboxConf = configuration;
		
		
		//Add comment preambles to saved configuration
		NSString *preamble = NSLocalizedStringFromTable(@"Configuration preamble", @"Configuration",
                                                        @"Used by generated configuration files as a commented header at the top of the file.");
        NSString *autoexecPreamble = NSLocalizedStringFromTable(@"Configuration preamble", @"Configuration",
                                                                @"Used in generated configuration files as a commented header underneath the [autoexec] section.");
        
		[gameboxConf setPreamble: preamble];
		[gameboxConf setStartupCommandsPreamble: autoexecPreamble];
		
		
		//Compare against the combined configuration we'll inherit from Boxer's base settings plus
        //the profile-specific configurations (if any), and eliminate any duplicate configuration
        //parameters from the gamebox conf. This way, we don't persist settings we don't need to.
        NSString *baseConfPath = [[NSBundle mainBundle] pathForResource: @"Preflight" ofType: @"conf"];
        BXEmulatorConfiguration *baseConf = [BXEmulatorConfiguration configurationWithContentsOfFile: baseConfPath error: nil];
        [baseConf removeStartupCommands];
        
        NSArray *profileConfs = [gameProfile configurations];
		for (NSString *profileConfName in profileConfs)
        {
			NSString *profileConfPath = [[NSBundle mainBundle] pathForResource: profileConfName
																		ofType: @"conf"
																   inDirectory: @"Configurations"];
			
			BXEmulatorConfiguration *profileConf = [BXEmulatorConfiguration configurationWithContentsOfFile: profileConfPath error: nil];
            if (profileConf) [baseConf addSettingsFromConfiguration: profileConf];
		}
        
        [gameboxConf excludeDuplicateSettingsFromConfiguration: baseConf];
		
		[gameboxConf writeToFile: filePath error: NULL];
	}
}

- (void) _cleanup
{
	//Delete the temporary folder, if one was created
	if (temporaryFolderPath)
	{
		NSFileManager *manager = [NSFileManager defaultManager];
		[manager removeItemAtPath: temporaryFolderPath error: NULL];
	}
	
	//Cancel any in-progress operations specific to this session
	[importQueue cancelAllOperations];
    [scanQueue cancelAllOperations];
    
	[importQueue waitUntilAllOperationsAreFinished];
	[scanQueue waitUntilAllOperationsAreFinished];
}


#pragma mark -
#pragma mark Pause-state handling

+ (NSSet *) keyPathsForValuesAffectingProgramIsActive
{
    return [NSSet setWithObjects: @"paused", @"autopaused", @"emulating", @"emulator.isAtPrompt", nil];
}

- (BOOL) programIsActive
{
    if (self.isPaused || self.isAutoPaused) return NO;
    if (!self.isEmulating) return NO;
    
    @synchronized(self.emulator)
    {
        if (self.emulator.isAtPrompt) return NO;
    }
    
    return YES;
}

- (void) setPaused: (BOOL)flag
{
	if (paused != flag)
	{
		paused = flag;
		[self _syncSuspendedState];
	}
}

- (void) setInterrupted: (BOOL)flag
{
	if (interrupted != flag)
	{
		interrupted = flag;
		[self _syncSuspendedState];
	}
}

- (void) setAutoPaused: (BOOL)flag
{
	if (autoPaused != flag)
	{
		autoPaused = flag;
		[self _syncSuspendedState];
	}
}

- (void) setSuspended: (BOOL)flag
{
	if (suspended != flag)
	{
        //Enable/disable display-sleep suppression
        [self _syncSuppressesDisplaySleep];
        
		suspended = flag;
        
		//Tell the emulator to prepare for being suspended, or to resume after we unpause.
        if (suspended)
        {
            [emulator pause];
        }
        else
        {
            [emulator resume];
        }
        
        if (!emulator.isConcurrent)
        { 
            //The suspended state is only checked inside the event loop
            //inside -emulatorDidBeginRunLoop:, which only processes when
            //there's any events in the queue. We post a dummy event to ensure
            //that the loop ticks over and recognises the pause state.
            NSEvent *dummyEvent = [NSEvent otherEventWithType: NSApplicationDefined
                                                     location: NSZeroPoint
                                                modifierFlags: 0
                                                    timestamp: CFAbsoluteTimeGetCurrent()
                                                 windowNumber: 0
                                                      context: nil
                                                      subtype: 0
                                                        data1: 0
                                                        data2: 0];
            
            [NSApp postEvent: dummyEvent atStart: NO];
        }
	}
}

- (void) _syncSuspendedState
{
	self.suspended = (paused || autoPaused || (interrupted && !emulator.isConcurrent));
}

- (void) _syncAutoPausedState
{
    self.autoPaused = [self _shouldAutoPause];
}

- (BOOL) _shouldAutoPause
{
	//Don't auto-pause if the emulator hasn't finished starting up yet.
	if (!self.isEmulating) return NO;
	
	//Only allow auto-pausing if the mode is enabled in the user's settings,
    //or if the emulator is waiting at the DOS prompt.
	if (self.emulator.isAtPrompt ||
        [[NSUserDefaults standardUserDefaults] boolForKey: @"pauseWhileInactive"])
    {
        //Auto-pause if Boxer is in the background.
        if (![NSApp isActive]) return YES;
        
        //Auto-pause if the DOS window is miniaturized.
        //IMPLEMENTATION NOTE: we used to toggle this when the DOS window was hidden (not visible),
        //but that gave rise to corner cases if shouldAutoPause was called just before the window
        //was to appear.
        if (self.DOSWindowController.window.isMiniaturized) return YES;
    }
	
    return NO;
}

- (void) _interruptionWillBegin: (NSNotification *)notification
{
	[self setInterrupted: YES];
}

- (void) _interruptionDidFinish: (NSNotification *)notification
{
	[self setInterrupted: NO];
}

- (void) _registerForPauseNotifications
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
	[center addObserver: self
			   selector: @selector(_syncAutoPausedState)
				   name: NSWindowDidMiniaturizeNotification
				 object: [DOSWindowController window]];
	
	[center addObserver: self
			   selector: @selector(_syncAutoPausedState)
				   name: NSWindowDidDeminiaturizeNotification
				 object: [DOSWindowController window]];
	
	[center addObserver: self
			   selector: @selector(_syncAutoPausedState)
				   name: NSApplicationDidResignActiveNotification
				 object: NSApp];
	
	[center addObserver: self
			   selector: @selector(_syncAutoPausedState)
				   name: NSApplicationDidBecomeActiveNotification
				 object: NSApp];
	
	
	[center addObserver: self
			   selector: @selector(_interruptionWillBegin:)
				   name: NSMenuDidBeginTrackingNotification
				 object: nil];
	
	[center addObserver: self
			   selector: @selector(_interruptionDidFinish:)
				   name: NSMenuDidEndTrackingNotification
				 object: nil];
	
	[center addObserver: self
			   selector: @selector(_interruptionWillBegin:)
				   name: BXWillBeginInterruptionNotification
				 object: nil];
	
	[center addObserver: self
			   selector: @selector(_interruptionDidFinish:)
				   name: BXDidFinishInterruptionNotification
				 object: nil];
}
	 
- (void) _deregisterForPauseNotifications
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
	[center removeObserver: self name: NSWindowWillMiniaturizeNotification object: nil];
	[center removeObserver: self name: NSWindowDidDeminiaturizeNotification object: nil];
	
	[center removeObserver: self name: NSApplicationWillResignActiveNotification object: nil];
	[center removeObserver: self name: NSApplicationDidBecomeActiveNotification object: nil];
	
	[center removeObserver: self name: BXWillBeginInterruptionNotification object: nil];
	[center removeObserver: self name: BXDidFinishInterruptionNotification object: nil];
}


#pragma mark -
#pragma mark Power management

- (BOOL) suppressesDisplaySleep
{
    return (displaySleepAssertionID != kIOPMNullAssertionID);
}

- (void) setSuppressesDisplaySleep: (BOOL)flag
{
    if (flag != [self suppressesDisplaySleep])
    {
        if (flag)
        {
            NSString *reason = NSLocalizedString(@"Emulating DOS application", @"A reason supplied to the power management system for why Boxer is preventing the Mac's display from sleeping. Must be 128 characters or less");
            
            IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, 
                                                           kIOPMAssertionLevelOn,
                                                           (CFStringRef)reason,
                                                           &displaySleepAssertionID);
            if (success != kIOReturnSuccess)
            {
                displaySleepAssertionID = kIOPMNullAssertionID;
            }
        }
        else
        {
            IOPMAssertionRelease(displaySleepAssertionID);
            displaySleepAssertionID = kIOPMNullAssertionID;
        }
    }
}

- (BOOL) _shouldSuppressDisplaySleep
{
    if (!self.isEmulating) return NO;
    if (self.isPaused || self.isAutoPaused) return NO;
    if (self.emulator.isAtPrompt) return NO;
    return YES;
}

- (void) _syncSuppressesDisplaySleep
{
    [self setSuppressesDisplaySleep: [self _shouldSuppressDisplaySleep]];
}

@end
