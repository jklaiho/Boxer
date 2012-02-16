/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXEmulatedKeyboard represents the DOS PC's keyboard hardware, and offers an API for sending
//emulated key events and setting keyboard layout.


#import <Foundation/Foundation.h>
#import "keyboard.h"


//How long keyPressed: should pretend to hold the specified key down before releasing.
#define BXKeyPressDurationDefault 0.25


typedef KBD_KEYS BXDOSKeyCode;

@interface BXEmulatedKeyboard : NSObject
{
	BOOL capsLockEnabled;
	BOOL numLockEnabled;
    BOOL scrollLockEnabled;
	NSString *activeLayout;
	NSUInteger pressedKeys[KBD_LAST];
}

@property (assign) BOOL capsLockEnabled;
@property (assign) BOOL numLockEnabled;
@property (assign) BOOL scrollLockEnabled;

@property (copy) NSString *activeLayout;


#pragma mark -
#pragma mark Keyboard input

//Press/release the specified key. Calls to keyDown: will stack to handle the same
//keycode being sent from multiple sources, so each keyDown: should be paired with
//a corresponding keyUp:. (Only the first keyDown: and the last keyUp: will actually
//trigger emulated keypresses.)
- (void) keyDown: (BXDOSKeyCode)key;
- (void) keyUp: (BXDOSKeyCode)key;

//Release all currently-pressed keys, as if the user took their hands off the keyboard.
- (void) clearInput;

//Release all current presses of the specified key, regardless of how many times keyDown:
//has been called on it.
- (void) clearKey: (BXDOSKeyCode)key;


//Imitate the key being pressed and then released after the default/specified duration.
- (void) keyPressed: (BXDOSKeyCode)key;
- (void) keyPressed: (BXDOSKeyCode)key forDuration: (NSTimeInterval)duration;

//Returns whether the specified key is currently pressed.
- (BOOL) keyIsDown: (BXDOSKeyCode)key;


#pragma mark -
#pragma mark Keyboard layout mapping

//The default DOS keyboard layout that should be used if no more specific one can be found.
+ (NSString *)defaultKeyboardLayout;

@end
