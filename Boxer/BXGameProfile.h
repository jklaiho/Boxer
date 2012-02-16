/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXGameProfile represents a detected game profile, which describes the game for gamebox creation
//and specifies custom DOSBox configuration and emulation behaviour.
//It has helper class methods for detecting a game profile from a filesystem path, and for
//determining the 'era' of a particular game at a filesystem path.


#import <Foundation/Foundation.h>
#import "BXDrive.h"


#pragma mark -
#pragma mark Constants

//Constants used by eraOfGameAtPath:
enum {
	BXUnknownMedium = 0,
	BX525DisketteMedium = 1,
	BX35DisketteMedium = 2,
	BXCDROMMedium = 3
};
typedef NSUInteger BXReleaseMedium;


//The default identifier string used for game profiles that don't match a known profile.
extern NSString * const BXGenericProfileIdentifier;


@interface BXGameProfile : NSObject
{
    NSString *identifier;
	NSString *gameName;
	NSString *profileDescription;
	NSDictionary *driveLabelMappings;
	NSArray *installerPatterns;
    NSArray *ignoredInstallerPatterns;
	NSArray *configurations;
	
	BXReleaseMedium coverArtMedium;
	BXDriveType sourceDriveType;
	NSInteger requiredDiskSpace;
	BOOL mountHelperDrivesDuringImport;
    BOOL mountTempDrive;
    BOOL requiresCDROM;
}

#pragma mark -
#pragma mark Properties

//A unique identifier for this profile. Used for quick lookups via +profileWithIdentifier:.
@property (copy, nonatomic) NSString *identifier;

//The human-readable name of the game this profile represents.
//Will be nil for shared profiles (in which case profileDescription will be available.) 
@property (copy, nonatomic) NSString *gameName;

//The configuration file(s) to use for this game (sans path and .conf extension),
//as stored in Resources/Configurations
@property (copy, nonatomic) NSArray *configurations;

//The description of what kind of games this game profile covers.
//Will be nil for game-specific profiles (in which case gameName will be available.)
@property (copy, nonatomic) NSString *profileDescription;

//Whether this game needs to be installed from a particular kind of drive
//(e.g. floppy-disk or CD-ROM).
//If the game has no special requirements, this will be BXDriveAutodetect.
@property (assign, nonatomic) BXDriveType sourceDriveType;

//The maximum amount of free disk space this game may need to install.
//Used to assign an appropriate amount of free space on drive C.
//If the game has no special requirements, this will be BXDefaultFreeSpace.
@property (assign, nonatomic) NSInteger requiredDiskSpace;

//Whether the game requires a CD-ROM drive to be present in order to start up.
//If YES, then Boxer will mount a dummy CD-ROM if no other CDs are present.
//Defaults to NO.
@property (assign, nonatomic) BOOL requiresCDROM;

//Whether to mount the X and Y helper drives while importing this game.
//These drives can confuse the installers for some games,
//e.g. making them offer the wrong default destination drive.
//Defaults to YES.
@property (assign, nonatomic) BOOL mountHelperDrivesDuringImport;

//Whether to mount the X drive at all when running this game.
//Certain games misinterpret the TMP and TEMP variables and need this disabled.
//Defaults to YES.
@property (assign, nonatomic) BOOL mountTempDrive;

//The type of media upon which this game was likely released: currently this
//is used only for deciding on cover art, not for emulation decisions.
//(See installMedium above, which does affect how the game is installed.)
//Defaults to BXUnknownMedium.
@property (assign, nonatomic) BXReleaseMedium coverArtMedium;


#pragma mark -
#pragma mark Helper class methods

//The version of the current profile detection catalogue.
//This is used for invalidating profiles that were detected and saved under
//previous versions of Boxer (and which may have since been superseded.)
+ (NSString *) catalogueVersion;

//Returns an array of generic profiles that match multiple games.
//This corresponds the contents of the BXGenericProfiles key in GameProfiles.plist.
+ (NSArray *) genericProfiles;

//Returns an array of game profiles identifying specific games.
//This corresponds the contents of the BXSpecificGameProfiles key in GameProfiles.plist.
+ (NSArray *) specificGameProfiles;

//Returns the game era that the contents of the specified file path look like, based on filesize
//and age of files. This is used by BXDockTileController to decide which bootleg coverart style to use.
+ (BXReleaseMedium) mediumOfGameAtPath: (NSString *)basePath;


#pragma mark -
#pragma mark Initializers

//Returns a generic profile with no special configuration or game data.
+ (id) genericProfile;

//Returns the game profile matching the specified identifier,
//or nil if no such profile was found.
+ (id) profileWithIdentifier: (NSString *)identifier;

//Detects and returns an appropriate game profile for the specified path,
//by scanning for telltale files in the file heirarchy starting at basePath.
//Will return nil if no profile could be found.
//If searchSubfolders is NO, only the base path will be scanned without
//recursing into subfolders.
+ (id) detectedProfileForPath: (NSString *)basePath
             searchSubfolders: (BOOL) searchSubfolders;

//Creates a new profile from the specified GameProfiles.plist-format dictionary.
- (id) initWithDictionary: (NSDictionary *)profileDictionary;

#pragma mark -
#pragma mark Methods affecting emulation behaviour

//Returns an customised drive label for the specified drive.
- (NSString *) volumeLabelForDrive: (BXDrive *)drive;

//Returns whether the file at the specified path is the designated installer for this game.
- (BOOL) isDesignatedInstallerAtPath: (NSString *)path;

//Returns whether the file at the specified path should be ignored when scanning for installers.
- (BOOL) isIgnoredInstallerAtPath: (NSString *)path;

@end
