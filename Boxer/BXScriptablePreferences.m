/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXScriptablePreferences.h"
#import "BXPreferencesController.h"
#import "BXAppController+BXGamesFolder.h"
#import "BXScriptableWindow.h"

@implementation BXScriptablePreferences

- (NSWindow *)window
{
	NSWindow *window = [[BXPreferencesController controller] window];
	return [BXScriptableWindow scriptableWindow: window];
}

- (NSURL *)gamesFolderURL
{
	NSString *path = [[NSApp delegate] gamesFolderPath];
	if (path) return [NSURL fileURLWithPath: path];
	else return nil;
}

- (void) setGamesFolderURL: (NSURL *)url
{
	[[NSApp delegate] setGamesFolderPath: [url path]];
}

+ (BXScriptablePreferences *) sharedPreferences
{
	static BXScriptablePreferences *preferences = nil;
	if (!preferences) preferences = [[self alloc] init];
	return preferences;
}

- (NSScriptObjectSpecifier *) objectSpecifier
{
	NSScriptClassDescription *appDesc = [NSScriptClassDescription classDescriptionForClass: [NSApplication class]];
	
	NSScriptObjectSpecifier *specifier = [[NSPropertySpecifier alloc] initWithContainerClassDescription: appDesc
																					 containerSpecifier: nil
																									key: @"Boxer preferences"];
	
	return [specifier autorelease];
}
@end
