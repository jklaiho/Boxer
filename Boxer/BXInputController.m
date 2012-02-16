/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXInputControllerPrivate.h"
#import "BXAppController.h"
#import "BXSession.h"
#import "BXJoystickController.h"
#import "BXJoypadController.h"
#import "BXGeometry.h"
#import "BXCursorFadeAnimation.h"
#import "BXDOSWindowController.h"
#import "BXDOSWindow.h"
#import "BXPostLeopardAPIs.h"
#import "NSWindow+BXWindowDimensions.h"

#import "BXEventConstants.h"

#import "BXEmulator.h"
#import "BXEmulatedMouse.h"
#import "BXEmulatedKeyboard.h"
#import "BXEmulatedJoystick.h"

#import "BXBezelController.h"



@implementation BXInputController
@synthesize mouseLocked, mouseActive, trackMouseWhileUnlocked, simulatedNumpadActive, mouseSensitivity, availableJoystickTypes;


#pragma mark -
#pragma mark Initialization and cleanup

- (void) awakeFromNib
{	
	//Initialize the controller profile map to an empty dictionary
	controllerProfiles = [[NSMutableDictionary alloc] initWithCapacity: 1];
	
	//Initialize mouse sensitivity and tracking options to a suitable default
	mouseSensitivity = 1.0f;
	trackMouseWhileUnlocked = YES;
	
	//DOSBox-triggered cursor warp distances which fit within this deadzone will be ignored
	//to prevent needless input delays. q.v. _emulatedCursorMovedToPointInCanvas:
	cursorWarpDeadzone = NSInsetRect(NSZeroRect, -BXCursorWarpTolerance, -BXCursorWarpTolerance);
	
	//The extent of our relative mouse canvas. Mouse coordinates passed to DOSBox will be
	//relative to this canvas and clamped to fit within it. q.v. mouseMoved:
	canvasBounds = NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f);
	
	//Used for constraining where the mouse cursor will appear when we unlock the mouse.
	//This is inset slightly from canvasBounds, because a cursor that appears right at the
	//very edge of the window looks dumb. q.v. _applyMouseLockState:
	visibleCanvasBounds = NSMakeRect(0.01f, 0.01f, 0.98f, 0.98f);
	
	
	//Insert ourselves into the responder chain as our view's next responder
	[self setNextResponder: [[self view] nextResponder]];
	[[self view] setNextResponder: self];
	
	//Tell the view to accept touch events for 10.6 and above
	if ([[self view] respondsToSelector: @selector(setAcceptsTouchEvents:)])
		[[self view] setAcceptsTouchEvents: YES];
	
	//Set up a cursor region in the view for mouse handling
	NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingEnabledDuringMouseDrag | NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingAssumeInside;
	
	NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect: NSZeroRect
																options: options
																  owner: self
															   userInfo: nil];
	
	[[self view] addTrackingArea: trackingArea];
	[trackingArea release];
	 
	
	//Set up our cursor fade animation
	cursorFade = [[BXCursorFadeAnimation alloc] initWithDuration: BXCursorFadeDuration
												  animationCurve: NSAnimationEaseIn];
	[cursorFade setDelegate: self];
	[cursorFade setOriginalCursor: [NSCursor arrowCursor]];
	[cursorFade setAnimationBlockingMode: NSAnimationNonblocking];
	[cursorFade setFrameRate: BXCursorFadeFrameRate];
}

- (void) dealloc
{
	[cursorFade stopAnimation];
	[cursorFade release], cursorFade = nil;
	[controllerProfiles release], controllerProfiles = nil;
	[self setAvailableJoystickTypes: nil], [availableJoystickTypes release];
	
	[super dealloc];
}

- (BXSession *)representedObject
{
	return (BXSession *)[super representedObject];
}

- (void) setRepresentedObject: (BXSession *)session
{
	BXSession *previousSession = [self representedObject];
	if (session != previousSession)
	{
		BXJoystickController *joystickController = [[NSApp delegate] joystickController];
        BXJoypadController *joypadController = [[NSApp delegate] joypadController];
		
		if (previousSession)
		{
			[self unbind: @"mouseSensitivity"];
			[self unbind: @"trackMouseWhileUnlocked"];
			[self unbind: @"mouseActive"];
			
			[previousSession removeObserver: self forKeyPath: @"paused"];
			[previousSession removeObserver: self forKeyPath: @"autoPaused"];
			[previousSession removeObserver: self forKeyPath: @"emulator.mouse.position"];
			[previousSession removeObserver: self forKeyPath: @"emulator.keyboard.numLockEnabled"];
			[previousSession removeObserver: self forKeyPath: @"emulator.joystick"];
			[previousSession removeObserver: self forKeyPath: @"emulator.joystickSupport"];
			
			[joystickController removeObserver: self forKeyPath: @"joystickDevices"];
			[joypadController removeObserver: self forKeyPath: @"hasJoypadDevices"];
			
			
			[self didResignKey];
		}
		
		[super setRepresentedObject: session];
		
		if (session)
		{
			NSDictionary *trackingOptions = [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
																		forKey: NSNullPlaceholderBindingOption];
			[self bind: @"trackMouseWhileUnlocked" toObject: session
		   withKeyPath: @"gameSettings.trackMouseWhileUnlocked"
			   options: trackingOptions];
			
			NSDictionary *sensitivityOptions = [NSDictionary dictionaryWithObject: [NSNumber numberWithFloat: 1.0f]
																		   forKey: NSNullPlaceholderBindingOption];
			[self bind: @"mouseSensitivity" toObject: session
		   withKeyPath: @"gameSettings.mouseSensitivity"
			   options: sensitivityOptions];
			
			[self bind: @"mouseActive" toObject: session
		   withKeyPath: @"emulator.mouse.active"
			   options: nil];
			
			[session addObserver: self
					  forKeyPath: @"paused"
						 options: NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
						 context: nil];
			
			[session addObserver: self
					  forKeyPath: @"autoPaused"
						 options: NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
						 context: nil];
			
			[session addObserver: self
					  forKeyPath: @"emulator.mouse.position"
						 options: NSKeyValueObservingOptionInitial
						 context: nil];
            
			[session addObserver: self
					  forKeyPath: @"emulator.keyboard.numLockEnabled"
						 options: 0
						 context: nil];
			
			[joystickController addObserver: self
								 forKeyPath: @"joystickDevices"
									options: NSKeyValueObservingOptionInitial
									context: nil];
            
			[joypadController addObserver: self
                               forKeyPath: @"hasJoypadDevices"
                                  options: NSKeyValueObservingOptionInitial
                                  context: nil];
			
			[session addObserver: self
					  forKeyPath: @"emulator.joystick"
						 options: NSKeyValueObservingOptionInitial
						 context: nil];
            
			[session addObserver: self
					  forKeyPath: @"emulator.joystickSupport"
						 options: NSKeyValueObservingOptionInitial
						 context: nil];
			
			//Set the DOS keyboard layout to match the current OS X layout as best as possible
			//TODO: listen for input source changes
			NSString *bestLayoutMatch = [[self class] keyboardLayoutForCurrentInputMethod];
            if (bestLayoutMatch)
            {
                [[self _emulatedKeyboard] setActiveLayout: bestLayoutMatch];
			}
            
			[self didBecomeKey];
		}
	}
}

- (void) observeValueForKeyPath: (NSString *)keyPath
					   ofObject: (id)object
						 change: (NSDictionary *)change
						context: (void *)context
{
	//Ignore mouse position updates if we know we were the ones that moved the mouse
	if (!updatingMousePosition && [keyPath isEqualToString: @"emulator.mouse.position"])
	{
		NSPoint mousePosition = [[self _emulatedMouse] position];
		//Ensure we're synced to the OS X cursor whenever the emulator's mouse position changes
		[self _emulatedCursorMovedToPointInCanvas: mousePosition];
	}
	
    //Show a notification whenever the numlock state is toggled.
    else if ([keyPath isEqualToString: @"emulator.keyboard.numLockEnabled"])
    {
        [self _notifyNumlockState];
    }
    
	//Tweak: we used to observe just the @suspended key, but that meant we'd resign key
	//and unlock the mouse whenever Boxer interrupted the emulator for UI stuff like window resizing.
	else if ([keyPath isEqualToString: @"paused"] || [keyPath isEqualToString: @"autoPaused"])
	{
		BOOL wasPaused	= [[change objectForKey: NSKeyValueChangeOldKey] boolValue];
		BOOL isPaused	= [[change objectForKey: NSKeyValueChangeNewKey] boolValue];
		
		if (wasPaused != isPaused)
		{
			if (isPaused) [self didResignKey];
			else [self didBecomeKey];
		}
	}
	
	else if ([keyPath isEqualToString: @"emulator.joystick"])
    {
        //Regenerate HID controller profiles for the newly connected joystick
        [self _syncControllerProfiles];
    }
    
	else if ([keyPath isEqualToString: @"emulator.joystickSupport"])
	{
        //Ensure that the connected joystick and available joystick types are
        //appropriate for the emulator's joystick support level
        [self _syncAvailableJoystickTypes];
		[self _syncJoystickType];
	}
    
    else if ([keyPath isEqualToString: @"joystickDevices"])
    {
        BXEmulator *emulator = [[self representedObject] emulator];
        id oldJoystick = [emulator joystick];
        
        //Connect a joystick if none was available before
		[self _syncJoystickType];
        
        //Regenerate controller profiles for the specified joystick
        //The controller profiles may have already been synced as a result
        //of a joystick being added/removed by syncJoystickType above,
        //so only do this if the joystick didn't change
        //FIXME: ugh, move this logic to BXJoystickInput
        BOOL joystickChanged = (oldJoystick != [emulator joystick]);
        if (!joystickChanged) [self _syncControllerProfiles];
        
        //Let the Inspector UI know to switch from the connect-a-controller panel
        [self willChangeValueForKey: @"controllersAvailable"];
        [self didChangeValueForKey: @"controllersAvailable"];
    }
    
    else if ([keyPath isEqualToString: @"hasJoypadDevices"])
    {
        //Connect a joystick if none was available before
		[self _syncJoystickType];
        
        //Let the Inspector UI know to switch from the connect-a-controller panel
        [self willChangeValueForKey: @"controllersAvailable"];
        [self didChangeValueForKey: @"controllersAvailable"];
	}		 
}


#pragma mark -
#pragma mark Cursor and event state handling

- (BOOL) mouseInView
{
	if ([self mouseLocked]) return YES;
	
    NSPoint mouseLocation = [NSEvent mouseLocation];
    NSWindow *window = [[self view] window];
    
    //Check if that point is over our window to begin with
    if ([NSWindow windowAtPoint: mouseLocation] != window) return NO;
    
    //If it is, check if the mouse is inside our view
	NSPoint pointInWindow = [window convertScreenToBase: mouseLocation];
	NSPoint pointInView = [[self view] convertPoint: pointInWindow fromView: nil];
    
    return ([[self view] mouse: pointInView inRect: [[self view] bounds]]);
}

- (void) cursorUpdate: (NSEvent *)theEvent
{
    //IMPLEMENTATION NOTE: changes to the statusbar segmented control appear
    //to trigger spurious cursor updates which should be ignored.
    //TODO: find a better heuristic for detecting such cursor updates,
    //and figure out why they're being generated in the first place.
    BOOL isSpuriousUpdate = (theEvent != nil) && ([theEvent timestamp] == 0);
    if (isSpuriousUpdate) return;
    
    //If we have control of the mouse cursor and we aren't fading it out yet,
    //start doing so now.
	if ([self _controlsCursor])
	{
        if (![cursorFade isAnimating])
		{
			//If the cursor fade was interrupted, make it restart from the beginning
            //rather than where it left off last time.
			[cursorFade setCurrentProgress: 0.0f];
			[cursorFade startAnimation];
		}
	}
    //Otherwise, restore the opaque cursor.
	else
	{
		[cursorFade stopAnimation];
        [[NSCursor arrowCursor] set];
	}
}

- (float) animation: (NSAnimation *)animation valueForProgress: (NSAnimationProgress)progress
{
    //Start fading only halfway through the animation.
    float fadeDelay = 0.5f;
    float curve = 0.9f;
    
    float easedValue = powf(progress, 2 * curve);
    
    return easedValue;
    
    return fadeDelay + (easedValue * (1.0f - fadeDelay));
}

- (BOOL) animationShouldChangeCursor: (BXCursorFadeAnimation *)animation
{
	//If the mouse is still inside the view, let the cursor change proceed
	if ([self _controlsCursor]) return YES;
	//If the mouse has left the view, cancel the animation and don't change the cursor
	else
	{
		if ([animation isAnimating]) [animation stopAnimation];
		return NO;
	}
}

- (void) didResignKey
{
	[self setMouseLocked: NO];
	
	[[self _emulatedKeyboard] clearInput];
	[[self _emulatedMouse] clearInput];
	[[self _emulatedJoystick] clearInput];
	
	simulatedMouseButtons = BXNoMouseButtonsMask;
	threeFingerTapStarted = 0;
    
    //Clear our record of which keys were fn-modified
    memset(&modifiedKeys, NO, sizeof(modifiedKeys));
}

- (void) didBecomeKey
{
	//Account for any changes to key modifier flags while we didn't have keyboard focus.
	//IMPLEMENTATION NOTE: CGEventSourceFlagsState returns the currently active modifiers
	//outside of the event stream. It works the same as the 10.6-only NSEvent +modifierFlags,
	//but is available on 10.5 and (unlike +modifierFlags) it also includes side-specific Shift,
    //Ctrl and Alt flags.
	CGEventFlags currentModifiers = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
	[self _syncModifierFlags: (NSUInteger)currentModifiers];
	
	//Also sync the cursor state while we're at it, in case the cursor was already over the window.
	[self cursorUpdate: nil];
}


#pragma mark -
#pragma mark Mouse focus and locking 

- (void) setMouseLocked: (BOOL)lock force: (BOOL)force
{
    [self willChangeValueForKey: @"mouseLocked"];
    
	//Don't continue if we're already in the right lock state
	if (lock != [self mouseLocked])
    {
        if (!lock || force || [self canLockMouse])
        {
            [self _applyMouseLockState: lock];
            mouseLocked = lock;
            
            //Let everybody know we've grabbed the mouse on behalf of our session
            NSString *notification = (lock) ? BXSessionDidLockMouseNotification : BXSessionDidUnlockMouseNotification;
            [[NSNotificationCenter defaultCenter] postNotificationName: notification object: [self representedObject]]; 
            
        }
    }
	
    [self didChangeValueForKey: @"mouseLocked"];
}

- (void) setMouseLocked: (BOOL)lock
{
    [self setMouseLocked: lock force: NO];
}

- (void) setMouseActive: (BOOL)active
{
	if (active != mouseActive)
	{
		mouseActive = active;
        //Update the mouse cursor, in case the mouse became active while the cursor was already
        //over the window.
		[self cursorUpdate: nil];
		
		//Release the mouse lock when DOS stops using the mouse, unless we're in fullscreen mode
		if (!active && ![[[self _windowController] window] isFullScreen]) [self setMouseLocked: NO];
	}
}

- (void) setTrackMouseWhileUnlocked: (BOOL)track
{	
	if (trackMouseWhileUnlocked != track)
	{
		trackMouseWhileUnlocked = track;
	
		//If we're disabling tracking, and the mouse is currently unlocked,
		//then warp the mouse to the center of the window as if we had just unlocked it.
		
		//Disabled for now because this makes the mouse jumpy and unpredictable.
		/*
		if (!track && ![self mouseLocked])
			[self _syncEmulatedCursorToPointInCanvas: NSMakePoint(0.5f, 0.5f)];
		*/
	}
}

- (BOOL) trackMouseWhileUnlocked
{
	//Tweak: when in fullscreen mode, ignore the current mouse-tracking setting.
	return trackMouseWhileUnlocked && ![[[self _windowController] window] isFullScreen];
}

- (BOOL) canLockMouse
{
	if (![NSApp isActive]) return NO;
	
	if (![[[self view] window] isKeyWindow]) return NO;
	
    //Always allow the mouse to be locked in fullscreen mode, even when the mouse is not active.
	return ([self mouseActive] || [[[self _windowController] window] isFullScreen]);
}


#pragma mark -
#pragma mark Interface actions

- (IBAction) toggleMouseLocked: (id)sender
{
	BOOL lock;
	BOOL wasLocked = [self mouseLocked];
	
	if ([sender respondsToSelector: @selector(boolValue)]) lock = [sender boolValue];
	else lock = !wasLocked;
	
	[self setMouseLocked: lock];
	
	//If the mouse state was actually toggled, play a sound to commemorate the occasion
	if ([self mouseLocked] != wasLocked)
	{
		NSString *lockSoundName	= (wasLocked) ? @"LockOpening" : @"LockClosing";
		[[NSApp delegate] playUISoundWithName: lockSoundName atVolume: BXMouseLockSoundVolume];
	}
}

- (IBAction) toggleSimulatedNumpad: (id)sender
{
    BOOL simulating = [self simulatedNumpadActive];
    [self setSimulatedNumpadActive: !simulating];
    
    if ([self simulatedNumpadActive])
        [[BXBezelController controller] showNumpadActiveBezel];
    else
        [[BXBezelController controller] showNumpadInactiveBezel];
}

- (IBAction) toggleTrackMouseWhileUnlocked: (id)sender
{
	BOOL tracking = [self trackMouseWhileUnlocked];
	[self setTrackMouseWhileUnlocked: !tracking];
}

- (BOOL) validateMenuItem: (NSMenuItem *)menuItem
{
	SEL theAction = [menuItem action];
	
	if (theAction == @selector(toggleMouseLocked:))
	{
		[menuItem setState: [self mouseLocked]];
		return [self canLockMouse];
	}
	else if (theAction == @selector(toggleTrackMouseWhileUnlocked:))
	{
		[menuItem setState: [self trackMouseWhileUnlocked]];
		return YES;
	}
	else if (theAction == @selector(toggleSimulatedNumpad:))
	{
		[menuItem setState: [self simulatedNumpadActive]];
        return YES;
	}
    else if (theAction == @selector(sendNumLock:))
    {
        [menuItem setState: [[self _emulatedKeyboard] numLockEnabled]];
        return YES;
    }
    else if (theAction == @selector(sendScrollLock:))
    {
        [menuItem setState: [[self _emulatedKeyboard] scrollLockEnabled]];
        return YES;
    }
	return YES;
}


#pragma mark -
#pragma mark Mouse events

- (void) mouseDown: (NSEvent *)theEvent
{
	//Unpause whenever the view is clicked on
	[[self representedObject] resume: self];
	
	//Only respond to clicks if we're locked or tracking mouse input while unlocked
	if ([self _controlsCursorWhileMouseInside])
	{
		BXEmulatedMouse *mouse = [self _emulatedMouse];
		
		NSUInteger modifiers = [theEvent modifierFlags];
		
        //Cmd-clicking toggles mouse-locking and causes the actual click to be ignored.
		if ((modifiers & NSCommandKeyMask) == NSCommandKeyMask)
		{
			[self toggleMouseLocked: self];
		}
        else
        {
            //Check if our right-mouse-button/both-mouse-button shortcut modifiers are being
            //pressed: if so, simulate the appropriate kind of mouse click.
            NSDictionary *gameSettings = [[self representedObject] gameSettings];
            
            NSUInteger rightButtonModifierMask = [[gameSettings objectForKey: @"mouseButtonModifierRight"] unsignedIntegerValue];
            
            NSUInteger bothButtonsModifierMask = [[gameSettings objectForKey: @"mouseButtonModifierBoth"] unsignedIntegerValue];
                    
            //Check if our both-buttons-at-once modifiers are being pressed.
            if (bothButtonsModifierMask > 0 && (modifiers & bothButtonsModifierMask) == bothButtonsModifierMask)
            {
                simulatedMouseButtons |= BXMouseButtonLeftAndRightMask;
                [mouse buttonDown: BXMouseButtonLeft];
                [mouse buttonDown: BXMouseButtonRight];
            }
            
            //Check if our right-button modifiers are being pressed.
            else if (rightButtonModifierMask > 0 && (modifiers & rightButtonModifierMask) == rightButtonModifierMask)
            {
                simulatedMouseButtons |= BXMouseButtonRightMask;
                [mouse buttonDown: BXMouseButtonRight];
            }
            
            //Otherwise, pass the left click on to the emulator as-is.
            else
            {
                [mouse buttonDown: BXMouseButtonLeft];   
            }
        }
	}
	
	//A single click on the window will lock the mouse if unlocked-tracking is disabled or we're in fullscreen mode
	else if (![self trackMouseWhileUnlocked])
	{
		[self toggleMouseLocked: self];
	}
	
	//Otherwise, let the mouse event pass on unmolested
	else
	{
		[super mouseDown: theEvent];
	}
}

- (void) rightMouseDown: (NSEvent *)theEvent
{
	//Unpause whenever the view is clicked on
	[[self representedObject] resume: self];
	
	if ([self _controlsCursorWhileMouseInside])
	{
		[[self _emulatedMouse] buttonDown: BXMouseButtonRight];
	}
	else
	{
		[super rightMouseDown: theEvent];
	}
}

- (void) otherMouseDown: (NSEvent *)theEvent
{
	//Unpause whenever the view is clicked on
	[[self representedObject] resume: self];
	
	if ([self _controlsCursorWhileMouseInside] && [theEvent buttonNumber] == BXMouseButtonMiddle)
	{
		[[self _emulatedMouse] buttonDown: BXMouseButtonMiddle];
	}
	else
	{
		[super otherMouseDown: theEvent];
	}
}

- (void) mouseUp: (NSEvent *)theEvent
{
	if ([self _controlsCursorWhileMouseInside])
	{
		BXEmulatedMouse *mouse = [self _emulatedMouse];
		
		if (simulatedMouseButtons != BXNoMouseButtonsMask)
		{
			if ((simulatedMouseButtons & BXMouseButtonLeftMask) == BXMouseButtonLeftMask)
				[mouse buttonUp: BXMouseButtonLeft];
			
			if ((simulatedMouseButtons & BXMouseButtonRightMask) == BXMouseButtonRightMask)
				[mouse buttonUp: BXMouseButtonRight];
			
			if ((simulatedMouseButtons & BXMouseButtonMiddleMask) == BXMouseButtonMiddleMask)
				[mouse buttonUp: BXMouseButtonMiddle];
			
			simulatedMouseButtons = BXNoMouseButtonsMask;
		}
		//Pass the mouse release as-is to our input handler
		else [mouse buttonUp: BXMouseButtonLeft];
	}
	else
	{
		[super mouseUp: theEvent];
	}
}

- (void) rightMouseUp: (NSEvent *)theEvent
{
	if ([self _controlsCursorWhileMouseInside])
	{
		[[self _emulatedMouse] buttonUp: BXMouseButtonRight];
	}
	else
	{
		[super rightMouseUp: theEvent];
	}

}

- (void) otherMouseUp: (NSEvent *)theEvent
{
	//Only pay attention to the middle mouse button; all others can do as they will
	if ([theEvent buttonNumber] == BXMouseButtonMiddle && [self _controlsCursorWhileMouseInside])
	{
		[[self _emulatedMouse] buttonUp: BXMouseButtonMiddle];
	}		
	else
	{
		[super otherMouseUp: theEvent];
	}
}

//Work out mouse motion relative to the view's canvas, passing on the current position
//and movement delta to the emulator's input handler.
//We represent position and delta as as a fraction of the canvas rather than as a fixed unit
//position, so that they stay consistent when the view size changes.
- (void) mouseMoved: (NSEvent *)theEvent
{
	//Only apply mouse movement if we're locked or we're accepting unlocked mouse input
	if ([self _controlsCursorWhileMouseInside])
	{
		NSRect canvas = [[self view] bounds];
		CGFloat width = canvas.size.width;
		CGFloat height = canvas.size.height;
		
		NSPoint pointOnCanvas, delta;

		//Make the delta relative to the canvas
		delta = NSMakePoint([theEvent deltaX] / width,
							[theEvent deltaY] / height);		
		
		//If we have just warped the mouse, the delta above will include the distance warped
		//as well as the actual distance moved in this mouse event: so, we subtract the warp.
		if (!NSEqualPoints(distanceWarped, NSZeroPoint))
		{
			delta.x -= distanceWarped.x;
			delta.y -= distanceWarped.y;
		}
		
		if (![self mouseLocked])
		{
			NSPoint pointInView	= [[self view] convertPoint: [theEvent locationInWindow]
												   fromView: nil];
			pointOnCanvas = NSMakePoint(pointInView.x / width,
										pointInView.y / height);

			//Clamp the position to within the canvas.
			pointOnCanvas = clampPointToRect(pointOnCanvas, canvasBounds);
		}
		else
		{
			//While the mouse is locked, OS X won't update the absolute cursor position and
			//DOSBox won't pay attention to the absolute cursor position either, so we don't
			//bother calculating it.
			pointOnCanvas = NSZeroPoint;
			
			//While the mouse is locked, we apply our mouse sensitivity to the delta.
			delta.x *= mouseSensitivity;
			delta.y *= mouseSensitivity;
		}
		
		//Ensures we ignore any cursor-moved notifications from the emulator as a result of this call.
		updatingMousePosition = YES;
		
		[[self _emulatedMouse] movedTo: pointOnCanvas
									by: delta
							  onCanvas: canvas
						   whileLocked: [self mouseLocked]];
		
		//Resume paying attention to mouse position updates.
		updatingMousePosition = NO;
	}
	else
	{
		[super mouseMoved: theEvent];
	}
	
	//Always reset our internal warp tracking after every mouse movement event,
	//even if the event is not handled.
	distanceWarped = NSZeroPoint;
}

//Treat drag events as simple mouse movement
- (void) mouseDragged: (NSEvent *)theEvent		{ [self mouseMoved: theEvent]; }
- (void) rightMouseDragged: (NSEvent *)theEvent	{ return [self mouseDragged: theEvent]; }
- (void) otherMouseDragged: (NSEvent *)theEvent	{ return [self mouseDragged: theEvent]; }


- (void) mouseExited: (NSEvent *)theEvent
{
	[self willChangeValueForKey: @"mouseInView"];
	//Force a cursor update at this point: OS X 10.7 won't do so itself
    //if the mouse leaves the tracking area by moving into a floating panel.
	[super mouseExited: theEvent];
    [self cursorUpdate: theEvent];
    [self didChangeValueForKey: @"mouseInView"];
}

- (void) mouseEntered: (NSEvent *)theEvent
{
	[self willChangeValueForKey: @"mouseInView"];
	[super mouseEntered: theEvent];
    [self cursorUpdate: theEvent];
	[self didChangeValueForKey: @"mouseInView"];
}


#pragma mark -
#pragma mark Touch events

- (void) touchesBeganWithEvent: (NSEvent *)theEvent
{	
	if ([self _controlsCursorWhileMouseInside])
	{
		NSSet *touches = [theEvent touchesMatchingPhase: NSTouchPhaseTouching
												 inView: [self view]];
		
		//As soon as the user has placed three fingers onto the touch surface,
		//start tracking for the release to detect this as a three-finger tap gesture.
		if ([touches count] == 3)
		{
			threeFingerTapStarted = [NSDate timeIntervalSinceReferenceDate];
		}
		//If the user puts down more fingers, then cancel the gesture.
		else
		{
			threeFingerTapStarted = 0;
		}
	}
}

- (void) touchesEndedWithEvent: (NSEvent *)theEvent
{
	if (threeFingerTapStarted && [self _controlsCursorWhileMouseInside])
	{
		//If the touch has gone on for too long to treat as a tap,
		//then cancel the gesture.
		if (([NSDate timeIntervalSinceReferenceDate] - threeFingerTapStarted) > BXTapDurationThreshold)
		{
			threeFingerTapStarted = 0;
		}
		else
		{
			NSSet *touches = [theEvent touchesMatchingPhase: NSTouchPhaseTouching
													 inView: [self view]];
			
			//If all fingers have now been lifted from the surface,
			//then treat this as a proper triple-tap gesture.
			if ([touches count] == 0)
			{	
				//Unpause when triple-tapping
				[[self representedObject] resume: self];
				
				BXEmulatedMouse *mouse = [self _emulatedMouse];
			
				[mouse buttonPressed: BXMouseButtonLeft];
				[mouse buttonPressed: BXMouseButtonRight];
				
				threeFingerTapStarted = 0;
			}
		}
	}
}

- (void) swipeWithEvent: (NSEvent *)theEvent
{
	//The swipe event is a three-finger gesture based on movement and so may conflict with our own.
	//(We listen for this instead of for the touchesMovedWithEvent: message because it means we don't
	//have to bother calculating movement deltas.)
	threeFingerTapStarted = 0;
}

- (void) touchesCancelledWithEvent: (NSEvent *)theEvent
{
	threeFingerTapStarted = 0;
}


#pragma mark -
#pragma mark Private methods

- (BXDOSWindowController *) _windowController	{ return [[self representedObject] DOSWindowController]; }
- (BXEmulatedMouse *)_emulatedMouse				{ return [[[self representedObject] emulator] mouse]; }
- (BXEmulatedKeyboard *)_emulatedKeyboard		{ return [[[self representedObject] emulator] keyboard]; }
- (id <BXEmulatedJoystick>)_emulatedJoystick	{ return [[[self representedObject] emulator] joystick]; }


- (BOOL) _controlsCursor
{
	if (![self _controlsCursorWhileMouseInside]) return NO;
	
	if (![[[self view] window] isKeyWindow]) return NO;
	
	return [self mouseInView];
}

- (BOOL) _controlsCursorWhileMouseInside
{
	if (![self mouseActive]) return NO;
	if ([[self representedObject] isSuspended]) return NO;
	
	return ([self mouseLocked] || [self trackMouseWhileUnlocked]);
}

- (NSPoint) _pointOnScreen: (NSPoint)canvasPoint
{
	NSRect canvas = [[self view] bounds];
	NSPoint pointInView = NSMakePoint(canvasPoint.x * canvas.size.width,
									  canvasPoint.y * canvas.size.height);
	
	NSPoint pointInWindow = [[self view] convertPoint: pointInView toView: nil];
	NSPoint pointOnScreen = [[[self view] window] convertBaseToScreen: pointInWindow];
	
	return pointOnScreen;
}

- (NSPoint) _pointInCanvas: (NSPoint)screenPoint
{
	NSPoint pointInWindow	= [[[self view] window] convertScreenToBase: screenPoint];
	NSPoint pointInView		= [[self view] convertPoint: pointInWindow fromView: nil];
	
	NSRect canvas = [[self view] bounds];
	NSPoint pointInCanvas = NSMakePoint(pointInView.x / canvas.size.width,
										pointInView.y / canvas.size.height);
	
	return pointInCanvas;	
}

- (void) _applyMouseLockState: (BOOL)lock
{	
	if (lock)
	{
        //Hide the mouse cursor when locking, if it's currently visible.
        //Checking CGCursorIsVisible() ensures we don't "over-hide"
        //the cursor if it's already hidden, since [NSCursor hide] stacks
        //and we have no way of knowing the current stack depth.
        if (CGCursorIsVisible()) [NSCursor hide];
        
        //Disassociate the mouse and the OS X cursor. This prevents the OS X cursor
        //from moving as long as the mouse is locked (which prevents it leaving the
        //confines of the window, which is what we want to avoid.)
        //FIXME: this is ignored by tablet devices on OS X 10.6 and below, which means
        //the cursor can leave the window and inadvertently click on other applications.
        CGAssociateMouseAndMouseCursorPosition(NO);
        
		//If the cursor is outside of the view when we lock the mouse,
		//then warp it to the center of the DOS view.
		//This prevents mouse clicks from going to other windows.
		//(We avoid warping if the mouse is already over the view,
        //as this would cause an input delay.)
		if (![self mouseInView]) [self _syncOSXCursorToPointInCanvas: NSMakePoint(0.5f, 0.5f)];
		
		//Warp the DOS mouse cursor to the previous location of the OS X cursor upon locking.
		//Disabled for now, because this gives poor results in games with relative mouse positioning
        //and so makes the mouse behaviour feel jumpy and unpredictable.
        /*
		if (![self trackMouseWhileUnlocked])
		{
			NSPoint mouseLocation = [NSEvent mouseLocation];
			NSPoint canvasLocation = [self _pointInCanvas: mouseLocation];
			
			[self _syncEmulatedCursorToPointInCanvas: canvasLocation];
		}
         */
	}
	else
	{
        //Restore the regular mouse cursor if it was previously faded-out.
        [[NSCursor arrowCursor] set];
        
        //Allow the OS X cursor to update its position in response to mouse
        //movement again.
        CGAssociateMouseAndMouseCursorPosition(YES);
        
		//If we're unlocking the mouse, then sync the OS X mouse cursor
		//to wherever DOSBox's cursor is located within the view.
		NSPoint mousePosition = [[self _emulatedMouse] position];
		
		//Constrain the cursor position to slightly inset within the view:
		//This ensures the mouse doesn't appear outside the view or right
		//at the view's edge, which looks ugly.
		mousePosition = clampPointToRect(mousePosition, visibleCanvasBounds);
		
		[self _syncOSXCursorToPointInCanvas: mousePosition];
		
		
		//If we don't track the mouse while unlocked, then also tell DOSBox
		//to warp the mouse to the center of the canvas; this will prevent
		//the leftover position from latently causing unintended input
		//(such as scrolling or turning).
		
		//Disabled for now because this makes the mouse jumpy and unpredictable.
		/*
		if (![self trackMouseWhileUnlocked])
		{
			[self _syncEmulatedCursorToPointInCanvas: NSMakePoint(0.5f, 0.5f)];
		}
		 */
        
        //Unhide the mouse cursor once we're unlocked.
        //IMPLEMENTATION NOTE: we used to check CGCursorIsVisible when unhiding,
        //as with hiding, but this broke with Cmd-Tabbing and there's no danger
        //of "over-unhiding" anyway.
        [NSCursor unhide];
	}
}

- (void) _emulatedCursorMovedToPointInCanvas: (NSPoint)pointInCanvas
{	
	//If the mouse warped of its own accord, and we have control of the cursor,
	//then sync the OS X mouse cursor to match DOSBox's.
	//(We only bother doing this if the mouse is unlocked; there's no point doing
	//otherwise, since we'll sync the cursors when we unlock.)
	if (!updatingMousePosition && ![self mouseLocked] && [self _controlsCursor])
	{
		//Don't sync if the mouse was warped to the 0, 0 point:
		//This indicates a game testing the extents of the mouse canvas.
		if (NSEqualPoints(pointInCanvas, NSZeroPoint)) return;
		
		//Don't sync if the mouse was warped outside the canvas:
		//This would place the mouse cursor beyond the confines of the window.
		if (!NSPointInRect(pointInCanvas, canvasBounds)) return;
		
		//Because syncing the OS X cursor causes a slight but noticeable input delay,
		//we check how far it moved and ignore small distances.
		NSPoint oldPointInCanvas = [self _pointInCanvas: [NSEvent mouseLocation]];
		NSPoint distance = deltaFromPointToPoint(oldPointInCanvas, pointInCanvas);

		if (!NSPointInRect(distance, cursorWarpDeadzone))
			[self _syncOSXCursorToPointInCanvas: pointInCanvas];
	}
}

- (void) _syncOSXCursorToPointInCanvas: (NSPoint)pointInCanvas
{
	NSPoint oldPointOnScreen	= [NSEvent mouseLocation];
	NSPoint pointOnScreen		= [self _pointOnScreen: pointInCanvas];
	
	//Warping the mouse won't generate a mouseMoved event, but it will mess up the delta on the 
	//next mouseMoved event to reflect the distance the mouse was warped. So, we determine how
	//far the mouse was warped, and will subtract that from the next mouse delta calculation.
	NSPoint oldPointInCanvas = [self _pointInCanvas: oldPointOnScreen];
	distanceWarped = deltaFromPointToPoint(oldPointInCanvas, pointInCanvas);
	
	
	CGPoint cgPointOnScreen = NSPointToCGPoint(pointOnScreen);
	//Flip the coordinates to compensate for AppKit's bottom-left screen origin
	NSRect screenFrame = [[[[self view] window] screen] frame];
	cgPointOnScreen.y = screenFrame.origin.y + screenFrame.size.height - cgPointOnScreen.y;
	
	//TODO: check that this behaves correctly across multiple displays.
	CGWarpMouseCursorPosition(cgPointOnScreen);
}

- (void) _syncEmulatedCursorToPointInCanvas: (NSPoint)pointInCanvas
{
	BXEmulatedMouse *mouse = [self _emulatedMouse];
	NSPoint mousePosition = [mouse position];
	NSPoint delta = deltaFromPointToPoint(mousePosition, pointInCanvas);
	[mouse movedTo: pointInCanvas
				by: delta
		  onCanvas: [[self view] bounds]
	   whileLocked: NO];
}
@end
