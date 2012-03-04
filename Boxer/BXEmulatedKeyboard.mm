/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXEmulatedKeyboard.h"
#import "BXEmulator.h"
#import "BXCoalface.h"

//For unicode constants
#import <Cocoa/Cocoa.h>

#pragma mark -
#pragma mark Private method declarations

//Implemented in dos_keyboard_layout.cpp
Bitu DOS_SwitchKeyboardLayout(const char* new_layout, Bit32s& tried_cp);
Bitu DOS_LoadKeyboardLayout(const char * layoutname, Bit32s codepage, const char * codepagefile);
const char* DOS_GetLoadedLayout(void);

@interface BXEmulatedKeyboard ()

@property (readwrite, assign) BOOL capsLockEnabled;
@property (readwrite, assign) BOOL numLockEnabled;
@property (readwrite, assign) BOOL scrollLockEnabled;

//Assign rather than retain, because NSTimers retain their targets
@property (assign) NSTimer *pendingKeypresses;

//Called after a delay by keyPressed: to release the specified key
- (void) _releaseKeyWithCode: (NSNumber *)key;

//Returns the DOS keycode constant that will produce the specified character
//under the US keyboard layout, along with any modifiers needed to trigger it.
- (BXDOSKeyCode) _DOSKeyCodeForCharacter: (unichar)character requiredModifiers: (NSUInteger *)modifierFlags;

- (void) _processNextQueuedKey: (NSTimer *)timer;
- (void) _setUsesActiveLayoutFromValue: (NSNumber *)value;

@end


#pragma mark -
#pragma mark Implementation

@implementation BXEmulatedKeyboard
@synthesize capsLockEnabled, numLockEnabled, scrollLockEnabled, preferredLayout, pendingKeypresses;

+ (NSTimeInterval) defaultKeypressDuration { return 0.25; }


#pragma mark -
#pragma mark Initialization and deallocation

- (id) init
{
	if ((self = [super init]))
	{
		self.preferredLayout = [[self class] defaultKeyboardLayout];
	}
	return self;
}

- (void) dealloc
{
    self.preferredLayout = nil;
	[super dealloc];
}


#pragma mark -
#pragma mark Keyboard input

- (void) keyDown: (BXDOSKeyCode)key
{   
    //If this key is not already pressed, tell the emulator the key has been pressed.
    //TWEAK: ignore incoming keypresses while we're processing keypresses, so that
    //they won't get interleaved.
	if (!pressedKeys[key] && !self.pendingKeypresses)
	{
		KEYBOARD_AddKey(key, YES);
		
        //TODO: look these up from the actual emulation state.
		if		(key == KBD_capslock)	[self setCapsLockEnabled: !capsLockEnabled];
		else if	(key == KBD_numlock)	[self setNumLockEnabled: !numLockEnabled];
        else if (key == KBD_scrolllock) [self setScrollLockEnabled: !scrollLockEnabled];
	}
    pressedKeys[key]++;
}

- (void) keyUp: (BXDOSKeyCode)key
{
	if (pressedKeys[key])
	{
        //FIXME: we should just decrement the number of times the key has been pressed
        //instead of clearing it altogether. However, we're still running into problems
        //with arrowkeys, where we miss a keyUp: event from OS X and the key stays pressed.
        //This should be changed back once those problems have been located and fixed.
        
		//pressedKeys[key]--;
        pressedKeys[key] = 0;
        
        //If this was the last press of this key,
        //tell the emulator to finally release the key.
        if (!pressedKeys[key])
            KEYBOARD_AddKey(key, NO);
	}
}

- (BOOL) keyIsDown: (BXDOSKeyCode)key
{
	return pressedKeys[key] > 0;
}

- (void) keyPressed: (BXDOSKeyCode)key
{
	[self keyPressed: key forDuration: BXKeyPressDurationDefault];
}

- (void) keyPressed: (BXDOSKeyCode)key forDuration: (NSTimeInterval)duration
{
	[self keyDown: key];
	
    if (duration > 0)
    {
        [self performSelector: @selector(_releaseKeyWithCode:)
                   withObject: [NSNumber numberWithUnsignedShort: key]
                   afterDelay: duration];
    }
    //Immediately release the key if the duration was 0.
    //CHECKME: The keydown and keyup events will still appear in the keyboard event queue,
    //but games that poll the current state of the keys may overlook the event.
    else
    {
        [self keyUp: key];
    }
}

- (void) _releaseKeyWithCode: (NSNumber *)key
{
	[self keyUp: [key unsignedShortValue]];
}

- (void) clearInput
{
	BXDOSKeyCode key;
	for (key=KBD_NONE; key<KBD_LAST; key++)
    {
        [self clearKey: key];
    }
}

- (void) clearKey: (BXDOSKeyCode)key
{
    if (pressedKeys[key])
    {
        //Ensure that no matter how many ways the key is being held down,
        //it will always be released by this keyUp:.
        pressedKeys[key] = 1;
        [self keyUp: key];
    }
}

- (BOOL) keyboardBufferFull
{
    return boxer_keyboardBufferRemaining() == 0;
}

- (void) typeCharacters: (NSString *)characters
{
    [self typeCharacters: characters burstInterval: BXTypingBurstIntervalDefault];
}

- (void) typeCharacters: (NSString *)characters burstInterval: (NSTimeInterval)interval
{
    NSMutableArray *keyEvents = [NSMutableArray arrayWithCapacity: characters.length * 3];
    
    BOOL capsLock       = self.capsLockEnabled;
    BOOL leftShifted    = [self keyIsDown: KBD_leftshift];
    BOOL rightShifted   = [self keyIsDown: KBD_rightshift];
    
    NSUInteger i, length = characters.length;
    for (i=0; i < length; i++)
    {   
        unichar character = [characters characterAtIndex: i];
        NSUInteger flags;
        BXDOSKeyCode code = [self _DOSKeyCodeForCharacter: character requiredModifiers: &flags];
        
        //Skip codes we cannot process
        if (code == KBD_NONE) continue;
        
        BOOL needsShift = (flags & NSShiftKeyMask) == NSShiftKeyMask;
        
        //Ensure the shift keys are in the right state before we enter the key itself.
        if (needsShift && !(leftShifted || rightShifted))
        {
            [keyEvents addObject: [NSNumber numberWithInteger: KBD_leftshift]];
            leftShifted = YES;
        }
        else if (!needsShift && (leftShifted || rightShifted))
        {   
            if (leftShifted)
                [keyEvents addObject: [NSNumber numberWithInteger: -KBD_leftshift]];
            if (rightShifted)
                [keyEvents addObject: [NSNumber numberWithInteger: -KBD_rightshift]];
            
            leftShifted = rightShifted = NO;
        }
        
        [keyEvents addObject: [NSNumber numberWithInteger: code]];
        [keyEvents addObject: [NSNumber numberWithInteger: -code]];
    }
    
    //If none of the characters could be typed, then bail out now before modifying the keyboard state.
    if (!keyEvents.count) return;
    
    
    //Otherwise, bookend the typing with additional keys to set up the keyboard state appropriately.
    //Turn capslock off before processing any other keys, if it was on.
    if (capsLock)
    {
        [keyEvents insertObject: [NSNumber numberWithInteger: KBD_capslock] atIndex: 0];
        [keyEvents insertObject: [NSNumber numberWithInteger: -KBD_capslock] atIndex: 1];
        
        [keyEvents addObject: [NSNumber numberWithInteger: KBD_capslock]];
        [keyEvents addObject: [NSNumber numberWithInteger: -KBD_capslock]];
    }
    
    //If the shift keys were pressed in the course of typing, release them once the typing is done.
    if (leftShifted)
        [keyEvents addObject: [NSNumber numberWithInteger: -KBD_leftshift]];
    
    if (rightShifted)
        [keyEvents addObject: [NSNumber numberWithInteger: -KBD_rightshift]];
    
    
    //Set up a timer to begin sending the keypresses in bursts, if we don't have one already.
    if (!self.pendingKeypresses)
    {
        self.pendingKeypresses = [NSTimer scheduledTimerWithTimeInterval: interval
                                                                  target: self
                                                                selector: @selector(_processNextQueuedKey:)
                                                                userInfo: keyEvents
                                                                 repeats: YES];
    }
    //If we already have a timer for this running, then slap these events onto the end of its keypress queue.
    else
    {
        NSMutableArray *previousQueue = self.pendingKeypresses.userInfo;
        [previousQueue addObjectsFromArray: keyEvents];
    }
    
    //Process the initial batch of keypresses.
    [self.pendingKeypresses fire];
}

- (void) _processNextQueuedKey: (NSTimer *)timer
{
    NSMutableArray *keyEvents = timer.userInfo;
    NSUInteger numProcessed = 0;
    
    for (NSNumber *keyEvent in keyEvents)
    {
        //Give up for now once we're out of keyboard buffer:
        //we'll continue on the next cycle of the timer.
        if (self.keyboardBufferFull) break;
        
        NSInteger code = keyEvent.integerValue;
        BOOL pressed = (code >= 0);
        
        KEYBOARD_AddKey(ABS(code), pressed);
        numProcessed++;
    }
    
    if (numProcessed > 0)
    {
        //Tell the keyboard to ignore its builtin layout while processing these keys, and use the US layout instead.
        //This ensures the keycodes are processed exactly as intended.
        self.usesActiveLayout = NO;
        
        [keyEvents removeObjectsInRange: NSMakeRange(0, numProcessed)];
    }
    
    //Shut down the timer once we're out of keys to send.
    if (!keyEvents.count) [self cancelTyping];
}

- (void) cancelTyping
{
    if (self.pendingKeypresses)
    {
        [self performSelector: @selector(_setUsesActiveLayoutFromValue:)
                   withObject: [NSNumber numberWithBool: YES]
                   afterDelay: self.pendingKeypresses.timeInterval];
        
        [self.pendingKeypresses invalidate];
        self.pendingKeypresses = nil;
    }
}
- (BOOL) isTyping
{
    return self.pendingKeypresses != nil;
}


#pragma mark -
#pragma mark Keyboard layout

//FIXME: the US layout has a bug in codepage 858, whereby the E will remain lowercase when capslock is on.
//This bug goes away after switching from another layout back to US, so it may be at the DOSBox level.
+ (NSString *) defaultKeyboardLayout { return @"us"; }

- (void) setActiveLayout: (NSString *)layout
{
    if (![layout isEqualToString: self.activeLayout])
    {
        const char *layoutName;
        if (!layout || layout.length < 2) layoutName = "none";
        //Sanitise the layout name to lowercase.
        else layoutName = [layout.lowercaseString cStringUsingEncoding: BXDirectStringEncoding];
        
        //IMPLEMENTATION NOTE: we can only safely swap layouts to one that's supported
        //by the current codepage. If the current codepage does not support the specified
        //layout, we would need to load up another codepage, which is too complex and brittle
        //to do while another program may be running.
        //TODO: if we're at the DOS prompt anyway, then run KEYB to let it handle such cases.
        if (boxer_keyboardLayoutSupported(layoutName))
        {   
            Bit32s codepage = -1;
            DOS_SwitchKeyboardLayout(layoutName, codepage);
        }
        
        //Whether we can apply it or not, mark this as our preferred layout so that
        //DOSBox will apply it during startup.
        self.preferredLayout = layout;
    }
}

- (NSString *)activeLayout
{
    if (boxer_keyboardLayoutLoaded())
    {
        const char *loadedName = DOS_GetLoadedLayout();
        
        //The name of the "none" keyboard layout will be reported as NULL by DOSBox.
        if (loadedName)
        {
            return [NSString stringWithCString: loadedName encoding: BXDirectStringEncoding];
        }
        else
        {
            return nil;
        }
    }
    //If the keyboard has not been initialized yet, return the layout we'll apply once DOSBox finishes initializing.
    else
    {
        return self.preferredLayout;
    }
}

- (BOOL) usesActiveLayout
{
    return boxer_keyboardLayoutActive();
}

- (void) setUsesActiveLayout: (BOOL)usesActiveLayout
{
    boxer_setKeyboardLayoutActive(usesActiveLayout);
}

- (void) _setUsesActiveLayoutFromValue: (NSNumber *)value
{
    self.usesActiveLayout = value.boolValue;
}


- (BXDOSKeyCode) _DOSKeyCodeForCharacter: (unichar)character requiredModifiers: (NSUInteger *)modifierFlags;
{
    NSAssert(modifierFlags, @"_DOSKeyCodeForCharacter:requiredModifiers: must be called with a valid pointer in which to store the modifier flags.");
    
    *modifierFlags = 0;
    
    switch (character)
    {
            //UNSHIFTED KEYS    
            
        case NSF1FunctionKey: return KBD_f1;
        case NSF2FunctionKey: return KBD_f2;
        case NSF3FunctionKey: return KBD_f3;
        case NSF4FunctionKey: return KBD_f4;
        case NSF5FunctionKey: return KBD_f5;
        case NSF6FunctionKey: return KBD_f6;
        case NSF7FunctionKey: return KBD_f7;
        case NSF8FunctionKey: return KBD_f8;
        case NSF9FunctionKey: return KBD_f9;
        case NSF10FunctionKey: return KBD_f10;
        case NSF11FunctionKey: return KBD_f11;
        case NSF12FunctionKey: return KBD_f12;
            
        case '1': return KBD_1;
        case '2': return KBD_2;
        case '3': return KBD_3;
        case '4': return KBD_4;
        case '5': return KBD_5;
        case '6': return KBD_6;
        case '7': return KBD_7;
        case '8': return KBD_8;
        case '9': return KBD_9;
        case '0': return KBD_0;
            
        case NSPrintScreenFunctionKey: return KBD_printscreen;
        case NSScrollLockFunctionKey: return KBD_scrolllock;
        case NSPauseFunctionKey: return KBD_pause;
            
        case 'q': return KBD_q;
        case 'w': return KBD_w;
        case 'e': return KBD_e;
        case 'r': return KBD_r;
        case 't': return KBD_t;
        case 'y': return KBD_y;
        case 'u': return KBD_u;
        case 'i': return KBD_i;
        case 'o': return KBD_o;
        case 'p': return KBD_p;
            
        case 'a': return KBD_a;
        case 's': return KBD_s;
        case 'd': return KBD_d;
        case 'f': return KBD_f;
        case 'g': return KBD_g;
        case 'h': return KBD_h;
        case 'j': return KBD_j;
        case 'k': return KBD_k;
        case 'l': return KBD_l;
            
        case 'z': return KBD_z;
        case 'x': return KBD_x;
        case 'c': return KBD_c;
        case 'v': return KBD_v;
        case 'b': return KBD_b;
        case 'n': return KBD_n;
        case 'm': return KBD_m;
            
        case '\e': return KBD_esc;
            //KBD_capslock unavailable
        case NSBackspaceCharacter: return KBD_tab;
            
        case NSDeleteCharacter: return KBD_delete;
        case NSDeleteFunctionKey: return KBD_delete;
        case NSInsertFunctionKey: return KBD_insert;
        case NSEnterCharacter: return KBD_enter;
        case NSNewlineCharacter: return KBD_enter;
        case ' ': return KBD_space;
            
        case NSHomeFunctionKey: return KBD_home;
        case NSEndFunctionKey: return KBD_end;
        case NSPageUpFunctionKey: return KBD_pageup;
        case NSPageDownFunctionKey: return KBD_pagedown;
            
        case NSUpArrowFunctionKey: return KBD_up;
        case NSLeftArrowFunctionKey: return KBD_left;
        case NSDownArrowFunctionKey: return KBD_down;
        case NSRightArrowFunctionKey: return KBD_right;
            
        case '-': return KBD_minus;
        case '=': return KBD_equals;
            
        case '[': return KBD_leftbracket;
        case ']': return KBD_rightbracket;
        case '\\': return KBD_backslash;
            
        case '`': return KBD_grave;
        case ';': return KBD_semicolon;
        case '\'': return KBD_quote;
        case ',': return KBD_comma;
        case '.': return KBD_period;
        case '/': return KBD_slash;
            
            //SHIFTED KEYS
            
        case '!': *modifierFlags = NSShiftKeyMask; return KBD_1;
        case '@': *modifierFlags = NSShiftKeyMask; return KBD_2;
        case '#': *modifierFlags = NSShiftKeyMask; return KBD_3;
        case '$': *modifierFlags = NSShiftKeyMask; return KBD_4;
        case '%': *modifierFlags = NSShiftKeyMask; return KBD_5;
        case '^': *modifierFlags = NSShiftKeyMask; return KBD_6;
        case '&': *modifierFlags = NSShiftKeyMask; return KBD_7;
        case '*': *modifierFlags = NSShiftKeyMask; return KBD_8;
        case '(': *modifierFlags = NSShiftKeyMask; return KBD_9;
        case ')': *modifierFlags = NSShiftKeyMask; return KBD_0;
            
        case 'Q': *modifierFlags = NSShiftKeyMask; return KBD_q;
        case 'W': *modifierFlags = NSShiftKeyMask; return KBD_w;
        case 'E': *modifierFlags = NSShiftKeyMask; return KBD_e;
        case 'R': *modifierFlags = NSShiftKeyMask; return KBD_r;
        case 'T': *modifierFlags = NSShiftKeyMask; return KBD_t;
        case 'Y': *modifierFlags = NSShiftKeyMask; return KBD_y;
        case 'U': *modifierFlags = NSShiftKeyMask; return KBD_u;
        case 'I': *modifierFlags = NSShiftKeyMask; return KBD_i;
        case 'O': *modifierFlags = NSShiftKeyMask; return KBD_o;
        case 'P': *modifierFlags = NSShiftKeyMask; return KBD_p;
            
        case 'A': *modifierFlags = NSShiftKeyMask; return KBD_a;
        case 'S': *modifierFlags = NSShiftKeyMask; return KBD_s;
        case 'D': *modifierFlags = NSShiftKeyMask; return KBD_d;
        case 'F': *modifierFlags = NSShiftKeyMask; return KBD_f;
        case 'G': *modifierFlags = NSShiftKeyMask; return KBD_g;
        case 'H': *modifierFlags = NSShiftKeyMask; return KBD_h;
        case 'J': *modifierFlags = NSShiftKeyMask; return KBD_j;
        case 'K': *modifierFlags = NSShiftKeyMask; return KBD_k;
        case 'L': *modifierFlags = NSShiftKeyMask; return KBD_l;
            
        case 'Z': *modifierFlags = NSShiftKeyMask; return KBD_z;
        case 'X': *modifierFlags = NSShiftKeyMask; return KBD_x;
        case 'C': *modifierFlags = NSShiftKeyMask; return KBD_c;
        case 'V': *modifierFlags = NSShiftKeyMask; return KBD_v;
        case 'B': *modifierFlags = NSShiftKeyMask; return KBD_b;
        case 'N': *modifierFlags = NSShiftKeyMask; return KBD_n;
        case 'M': *modifierFlags = NSShiftKeyMask; return KBD_m;
            
        case '_': *modifierFlags = NSShiftKeyMask; return KBD_minus;
        case '+': *modifierFlags = NSShiftKeyMask; return KBD_equals;
            
        case '{': *modifierFlags = NSShiftKeyMask; return KBD_leftbracket;
        case '}': *modifierFlags = NSShiftKeyMask; return KBD_rightbracket;
        case '|': *modifierFlags = NSShiftKeyMask; return KBD_backslash;
            
        case '~': *modifierFlags = NSShiftKeyMask; return KBD_grave;
        case ':': *modifierFlags = NSShiftKeyMask; return KBD_semicolon;
        case '"': *modifierFlags = NSShiftKeyMask; return KBD_quote;
        case '<': *modifierFlags = NSShiftKeyMask; return KBD_comma;
        case '>': *modifierFlags = NSShiftKeyMask; return KBD_period;
        case '?': *modifierFlags = NSShiftKeyMask; return KBD_slash;
            
        default:
            return KBD_NONE;
    }
}

@end
