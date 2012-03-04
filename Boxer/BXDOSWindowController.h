/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXDOSWindowController manages a session window and its dependent views and view controllers.
//Besides the usual window-controller responsibilities, it handles switching to and from fullscreen
//and passing frames to the emulator to the rendering view.


#import <Cocoa/Cocoa.h>
#import "BXFullScreenCapableWindow.h"

@class BXEmulator;
@class BXSession;
@class BXDOSWindow;
@class BXProgramPanelController;
@class BXInputController;
@class BXStatusBarController;
@class BXEmulator;
@class BXFrameBuffer;
@class BXInputView;

@protocol BXFrameRenderingView;

//Produced by our rendering view when it begins/ends a live resize operation.
extern NSString * const BXViewWillLiveResizeNotification;
extern NSString * const BXViewDidLiveResizeNotification;

@interface BXDOSWindowController : NSWindowController <BXFullScreenCapableWindowDelegate>
{
	IBOutlet NSView <BXFrameRenderingView> *renderingView;
	IBOutlet BXInputView *inputView;
	IBOutlet NSView *statusBar;
	IBOutlet NSView *programPanel;

	IBOutlet BXProgramPanelController *programPanelController;
	IBOutlet BXInputController *inputController;
	IBOutlet BXStatusBarController *statusBarController;
	
    NSSize currentScaledSize;
	NSSize currentScaledResolution;
	BOOL resizingProgrammatically;
    BOOL windowIsClosing;
    
    NSSize renderingViewSizeBeforeFullScreen;
    NSString *autosaveNameBeforeFullScreen;
}

#pragma mark -
#pragma mark Properties

//Our subsidiary view controllers.
@property (retain, nonatomic) BXProgramPanelController *programPanelController;
@property (retain, nonatomic) BXInputController *inputController;
@property (retain, nonatomic) BXStatusBarController *statusBarController;

//The view which displays the emulator's graphical output.
@property (retain, nonatomic) NSView <BXFrameRenderingView> *renderingView;

//The view that tracks user input. This is also be the view we use for fullscreen.
@property (retain, nonatomic) BXInputView *inputView;

//The slide-out program picker panel.
@property (retain, nonatomic) NSView *programPanel;

//The status bar at the bottom of the window.
@property (retain, nonatomic) NSView *statusBar;

//The maximum BXFrameBuffer size we can render.
@property (readonly, nonatomic) NSSize maxFrameSize;

//The current size of the DOS rendering viewport.
@property (readonly, nonatomic) NSSize viewportSize;


#pragma mark -
#pragma mark Inherited accessor overrides

//Recast NSWindowController's standard accessors so that we get our own classes
//(and don't have to keep recasting them ourselves)
- (BXSession *) document;
- (BXDOSWindow *) window;


#pragma mark -
#pragma mark Renderer-related methods

//Passes the specified frame on to our rendering view to handle,
//and resizes the window appropriately if a change in resolution or aspect ratio has occurred.
- (void) updateWithFrame: (BXFrameBuffer *)frame;

//Returns a screenshot of what is currently being rendered in the rendering view.
//Will return nil if no frame has been provided yet (via updateWithFrame:).
- (NSImage *) screenshotOfCurrentFrame;


#pragma mark -
#pragma mark Interface actions

//Toggle the status bar and program panel components on and off.
- (IBAction) toggleStatusBarShown:		(id)sender;
- (IBAction) toggleProgramPanelShown:	(id)sender;

//Unconditionally show/hide the program panel.
- (IBAction) showProgramPanel: (id)sender;
- (IBAction) hideProgramPanel: (id)sender;

//Toggle the emulator's active rendering filter.
- (IBAction) toggleFilterType: (id)sender;


#pragma mark -
#pragma mark Toggling UI components

//Get/set whether the statusbar should be shown.
- (BOOL) statusBarShown;
- (void) setStatusBarShown: (BOOL)show
                   animate: (BOOL)animate;

//Get/set whether the program panel should be shown.
- (BOOL) programPanelShown;
- (void) setProgramPanelShown: (BOOL)show
                      animate: (BOOL)animate;

@end