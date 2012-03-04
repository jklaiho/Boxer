/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXCoalface.h"
#import "BXEmulatorPrivate.h"
#import "setup.h"
#import "mapper.h"


#pragma mark -
#pragma mark Application state functions

//This is called in place of DOSBox's GFX_Events to allow us to process events when the DOSBox
//core runloop gives us time.
void boxer_processEvents()
{
	[[BXEmulator currentEmulator] _processEvents];
}

//Called at the start and end of every iteration of DOSBOX_RunMachine.
void boxer_runLoopWillStart()
{
	[[BXEmulator currentEmulator] _runLoopWillStart];
}

void boxer_runLoopDidFinish()
{
	[[BXEmulator currentEmulator] _runLoopDidFinish];
}

//This is called at the start of DOSBox_NormalLoop, and
///allows us to short-circuit the current run loop if needed.
bool boxer_runLoopShouldContinue()
{
	return [[BXEmulator currentEmulator] _runLoopShouldContinue];
}

//Notifies Boxer of changes to title and speed settings
void boxer_handleDOSBoxTitleChange(Bit32s newCycles, Bits newFrameskip, bool newPaused)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didChangeEmulationState];
}


#pragma mark -
#pragma mark Rendering functions

void boxer_applyRenderingStrategy()
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[[emulator videoHandler] applyRenderingStrategy];
}

Bitu boxer_prepareForFrameSize(Bitu width, Bitu height, Bitu gfx_flags, double scalex, double scaley, GFX_CallBack_t callback)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	
	NSSize outputSize	= NSMakeSize((CGFloat)width, (CGFloat)height);
	NSSize scale		= NSMakeSize((CGFloat)scalex, (CGFloat)scaley);
	[[emulator videoHandler] prepareForOutputSize: outputSize atScale: scale withCallback: callback];
	
	return GFX_CAN_32 | GFX_SCALING;
}

Bitu boxer_idealOutputMode(Bitu flags)
{
	//Originally this tested various bit depths to find the most appropriate mode for the chosen scaler.
	//Because OS X always uses a 32bpp context and Boxer always uses RGBA-capable scalers, we ignore the
	//original function's behaviour altogether and just return something that will keep DOSBox happy.
	return GFX_CAN_32 | GFX_SCALING;
}

bool boxer_startFrame(Bit8u **frameBuffer, Bitu *pitch)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [[emulator videoHandler] startFrameWithBuffer: (void **)frameBuffer pitch: (NSUInteger *)pitch];
}

void boxer_finishFrame(const uint16_t *dirtyBlocks)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[[emulator videoHandler] finishFrameWithChanges: dirtyBlocks];	
}

Bitu boxer_getRGBPaletteEntry(Bit8u red, Bit8u green, Bit8u blue)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [[emulator videoHandler] paletteEntryWithRed: red green: green blue: blue];
}

void boxer_setPalette(Bitu start,Bitu count,GFX_PalEntry * entries)
{
	//This replacement DOSBox function does nothing, as the original was intended only for SDL
	//surface palettes which are irrelevant to OpenGL.
	//Furthermore it should never be called: if it does, that means DOSBox thinks it's using
	//surface output and this is a bug.
	NSCAssert(NO, @"boxer_setPalette called. This is a bug and should never happen.");
}


#pragma mark -
#pragma mark Shell-related functions

//Catch shell input and send it to our own shell controller - returns YES if we've handled the command,
//NO if we want to let it go through
//This is called by DOS_Shell::DoCommand in DOSBox's shell/shell_cmds.cpp, to allow us to hook into what
//goes on in the shell
bool boxer_shouldRunShellCommand(char* cmd, char* args)
{
	NSString *command			= [NSString stringWithCString: cmd	encoding: BXDirectStringEncoding];
	NSString *argumentString	= [NSString stringWithCString: args	encoding: BXDirectStringEncoding];
	
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [emulator _handleCommand: command withArgumentString: argumentString];
}


//Return a localized string for the given DOSBox translation key
//This is called by MSG_Get in DOSBox's misc/messages.cpp, instead of retrieving strings from its own localisation system
const char * boxer_localizedStringForKey(char const *keyStr)
{
	NSString *theKey			= [NSString stringWithCString: keyStr encoding: BXDirectStringEncoding];
	NSString *localizedString	= [[NSBundle mainBundle]
								   localizedStringForKey: theKey
								   value: @"" //If the key isn't found, display nothing
								   table: @"DOSBox"];
	
	return [localizedString cStringUsingEncoding: BXDisplayStringEncoding];
}

bool boxer_handleCommandInput(char *cmd, Bitu *cursorPosition, bool *executeImmediately)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	NSString *oldCommandLine = [NSString stringWithCString: cmd encoding: BXDirectStringEncoding];
	NSString *newCommandLine = [emulator _handleCommandInput: oldCommandLine
											atCursorPosition: (NSUInteger *)cursorPosition
										  executeImmediately: (BOOL *)executeImmediately];
	if (newCommandLine)
	{
		const char *newcmd = [newCommandLine cStringUsingEncoding: BXDirectStringEncoding];
		if (newcmd)
		{
			strcpy(cmd, newcmd);
			return YES;
		}
		else return NO;
	}
	else return NO;
}

void boxer_didReturnToShell()
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didReturnToShell];
}

void boxer_autoexecDidStart()
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _willRunStartupCommands];
}

void boxer_autoexecDidFinish()
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didRunStartupCommands];
}

void boxer_willExecuteFileAtDOSPath(const char *path, DOS_Drive *dosboxDrive)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _willExecuteFileAtDOSPath: path onDOSBoxDrive: dosboxDrive];
}

void boxer_didExecuteFileAtDOSPath(const char *path, DOS_Drive *dosboxDrive)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didExecuteFileAtDOSPath: path onDOSBoxDrive: dosboxDrive];
}


#pragma mark -
#pragma mark Filesystem functions

//Whether or not to allow the specified path to be mounted.
//Called by MOUNT::Run in DOSBox's dos/dos_programs.cpp.
bool boxer_shouldMountPath(const char *path)
{
	NSString *localPath = [[NSFileManager defaultManager]
						   stringWithFileSystemRepresentation: path
						   length: strlen(path)];
	
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [emulator _shouldMountPath: localPath];
}

//Whether to include a file with the specified name in DOSBox directory listings
bool boxer_shouldShowFileWithName(const char *name)
{
	NSString *fileName = [NSString stringWithCString: name encoding: BXDirectStringEncoding];
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [emulator _shouldShowFileWithName: fileName];
}

//Whether to allow write access to the file at the specified path on the local filesystem
bool boxer_shouldAllowWriteAccessToPath(const char *path, DOS_Drive *dosboxDrive)
{
	NSString *localPath = [[NSFileManager defaultManager] 
						   stringWithFileSystemRepresentation: path
						   length: strlen(path)];
	
	BXEmulator *emulator = [BXEmulator currentEmulator];
	return [emulator _shouldAllowWriteAccessToPath: localPath onDOSBoxDrive: dosboxDrive];
}

//Tells Boxer to resync its cached drives - called by DOSBox functions that add/remove drives
void boxer_driveDidMount(Bit8u driveIndex)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _syncDriveCache];
}

void boxer_driveDidUnmount(Bit8u driveIndex)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _syncDriveCache];
}

void boxer_didCreateLocalFile(const char *path, DOS_Drive *dosboxDrive)
{
	NSString *localPath = [[NSFileManager defaultManager] 
						   stringWithFileSystemRepresentation: path
						   length: strlen(path)];	

	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didCreateFileAtPath: localPath onDOSBoxDrive: dosboxDrive];
}

void boxer_didRemoveLocalFile(const char *path, DOS_Drive *dosboxDrive)
{
	NSString *localPath = [[NSFileManager defaultManager] 
						   stringWithFileSystemRepresentation: path
						   length: strlen(path)];
	
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator _didRemoveFileAtPath: localPath onDOSBoxDrive: dosboxDrive];
}


#pragma mark -
#pragma mark Input-related functions

const char * boxer_preferredKeyboardLayout()
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	NSString *layoutCode = emulator.keyboard.preferredLayout;
    
    if (layoutCode)
        return [layoutCode cStringUsingEncoding: BXDirectStringEncoding];
    else return NULL;
}

void boxer_setMouseActive(bool mouseActive)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[[emulator mouse] setActive: mouseActive];
}

void boxer_setJoystickActive(bool joystickActive)
{
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[emulator setJoystickActive: joystickActive];
}

void boxer_mouseMovedToPoint(float x, float y)
{
	NSPoint point = NSMakePoint((CGFloat)x, (CGFloat)y);
	BXEmulator *emulator = [BXEmulator currentEmulator];
	[[emulator mouse] setPosition: point];
}

#pragma mark -
#pragma mark Helper functions

void boxer_log(char const* format,...)
{
#ifdef BOXER_DEBUG
	//Copypasta from sdlmain.cpp
	char buf[512];
	va_list msg;
	va_start(msg,format);
	vsprintf(buf,format,msg);
	strcat(buf,"\n");
	va_end(msg);
	printf("%s",buf);
#endif
}

void boxer_die(const char *functionName, const char *fileName, int lineNumber, const char * format,...)
{
	char err[512];
	va_list params;
	va_start(params, format);
	vsprintf(err, format, params);
	va_end(params);

    [[NSAssertionHandler currentHandler] handleFailureInFunction: [NSString stringWithCString: functionName encoding: NSASCIIStringEncoding]
                                                            file: [NSString stringWithCString: fileName encoding: NSASCIIStringEncoding]
                                                      lineNumber: lineNumber
                                                     description: [NSString stringWithCString: err encoding: NSASCIIStringEncoding], nil];
}


double boxer_realTime()
{
	return CFAbsoluteTimeGetCurrent();
}


#pragma mark -
#pragma mark No-ops

//These used to be defined in sdl_mapper.cpp, which we no longer include in Boxer.
void MAPPER_AddHandler(MAPPER_Handler * handler,MapKeys key,Bitu mods,char const * const eventname,char const * const buttonname) {}
void MAPPER_Init(void) {}
void MAPPER_StartUp(Section * sec) {}
void MAPPER_Run(bool pressed) {}
void MAPPER_RunInternal() {}
void MAPPER_LosingFocus(void) {}