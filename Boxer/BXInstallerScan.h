/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//BXInstallerScan is used by BXImportSession for locating DOS game installers within a path
//or volume. It populates its matchingPaths with all the DOS installers it finds, ordered
//by relevance - with the preferred installer first. 

//It also collects overall file data about the source while scanning, such as the game profile
//and whether the game appears to be already installed (or not a DOS game at all).

#import "BXImageAwareFileScan.h"

@class BXGameProfile;
@interface BXInstallerScan : BXImageAwareFileScan
{
    NSMutableArray *windowsExecutables;
    NSMutableArray *DOSExecutables;
    BOOL isAlreadyInstalled;
    
    BXGameProfile *detectedProfile;
} 

//The relative paths of all DOS and Windows executables discovered during scanning.
@property (readonly, nonatomic) NSArray *windowsExecutables;
@property (readonly, nonatomic) NSArray *DOSExecutables;

//The profile of the game at the base path, used for discovery of additional installers.
//If left unspecified, this will be autodetected during scanning.
@property (retain, nonatomic) BXGameProfile *detectedProfile;

//Whether the game at the base path appears to be already installed.
@property (readonly, nonatomic) BOOL isAlreadyInstalled;


//Helper methods for adding executables to their appropriate match arrays,
//a la addMatchingPath:
- (void) addWindowsExecutable: (NSString *)relativePath;
- (void) addDOSExecutable: (NSString *)relativePath;

@end
