/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXSessionPrivate declares protected methods for BXSession and its subclasses.

#import "BXSession.h"
#import "BXSession+BXEmulatorControls.h"
#import "BXSession+BXAudioControls.h"
#import "BXSession+BXFileManager.h"
#import "BXSessionError.h"


@class BXEmulatorConfiguration;
@class BXCloseAlert;
@class BXDrive;

@interface BXSession ()

#pragma mark -
#pragma mark Properties

//These have been overridden to make them internally writeable
@property (readwrite, retain, nonatomic) NSMutableDictionary *gameSettings;
@property (readwrite, copy, nonatomic) NSString *lastExecutedProgramPath;
@property (readwrite, copy, nonatomic) NSString *lastLaunchedProgramPath;
@property (readwrite, retain, nonatomic) NSDictionary *drives;
@property (readwrite, retain, nonatomic) NSDictionary *executables;
@property (readwrite, retain, nonatomic) NSArray *documentation;

@property (readwrite, assign, getter=isEmulating)	BOOL emulating;
@property (readwrite, nonatomic, assign, getter=isSuspended)	BOOL suspended;
@property (readwrite, nonatomic, assign, getter=isAutoPaused)	BOOL autoPaused;
@property (readwrite, nonatomic, assign, getter=isInterrupted)	BOOL interrupted;


#pragma mark -
#pragma mark Protected methods

//Whether to leave the program panel open after launching a program, so they can decide what to do with it.
//Used by programWillStart and didStartGraphicalContext.
- (BOOL) _leaveProgramPanelOpenAfterLaunch;

//Whether we should close the session (and the application) after returning to the DOS prompt.
- (BOOL) _shouldCloseOnProgramExit;

//Whether we should start the emulator as soon as the document is created.
- (BOOL) _shouldStartImmediately;

//Whether the document should be closed when the emulator process finishes.
//Normally YES, may be overridden by BXSession subclasses. 
- (BOOL) _shouldCloseOnEmulatorExit;


//Create our BXEmulator instance and starts its main loop.
//Called internally by [BXSession start], deferred to the end of the main thread's event loop to prevent
//DOSBox blocking cleanup code.
- (void) _startEmulator;

//Set up the emulator context with drive mounts and drive-related configuration settings. Called in
//runPreflightCommands at the start of AUTOEXEC.BAT, before any other commands or settings are run.
- (void) _mountDrivesForSession;



//Called once the session has exited to save any DOSBox settings we have changed to the gamebox conf.
- (void) _saveConfiguration: (BXEmulatorConfiguration *)configuration toFile: (NSString *)filePath;

//Returns whether we should cache the specified game profile in our game settings, to avoid needing
//to redetect it later. Base implementation returns YES in all cases.
- (BOOL) _shouldPersistGameProfile: (BXGameProfile *)profile;


//Cleans up temporary files after the session is closed.
- (void) _cleanup;



//Callback for close alert. Confirms document close when window is closed or application is shut down. 
- (void) _closeAlertDidEnd: (BXCloseAlert *)alert
				returnCode: (int)returnCode
			   contextInfo: (NSInvocation *)callback;

//Callback for close alert after a windows-only program is failed.
- (void) _windowsOnlyProgramCloseAlertDidEnd: (BXCloseAlert *)alert
								  returnCode: (int)returnCode
								 contextInfo: (void *)contextInfo;
@end


@interface BXSession (BXSuspensionBehaviour)

//When YES, the session will try to prevent the Mac's display from going to sleep.
@property (assign, nonatomic) BOOL suppressesDisplaySleep;

- (void) _syncSuspendedState;
- (void) _syncAutoPausedState;
- (BOOL) _shouldAutoPause;
- (void) _registerForPauseNotifications;
- (void) _deregisterForPauseNotifications;
- (void) _interruptionWillBegin: (NSNotification *)notification;
- (void) _interruptionDidFinish: (NSNotification *)notification;

- (BOOL) _shouldSuppressDisplaySleep;
- (void) _syncSuppressesDisplaySleep;

//Run the application's event loop until the specified date.
//Pass nil as the date to process pending events and then return immediately.
//(Note that execution will stay in this method while emulation is suspended,
//exiting only once the suspension is over and the requested date has past.)
- (void) _processEventsUntilDate: (NSDate *)date;
@end

@interface BXSession (BXFileManagerInternals)

- (void) _registerForFilesystemNotifications;
- (void) _deregisterForFilesystemNotifications;
- (void) _hasActiveImports;

//Used by mountNextDrivesInQueues and mountPreviousDrivesInQueues
//to centralise mounting logic.
- (void) _mountQueuedSiblingsAtOffset: (NSInteger)offset;

@end
