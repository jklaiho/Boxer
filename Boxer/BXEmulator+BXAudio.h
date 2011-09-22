/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

//The BXAudio category extends BXEmulator with functionality
//for controlling DOSBox's audio emulation and output.

#import "BXEmulator.h"

@interface BXEmulator (BXAudio)

//Sends an LCD message via Sysex to the MT-32 emulator
//(or to a real MT-32, in CoreMIDI mode.)
//Intended for debugging.
- (id) displayMT32LCDMessage: (NSString *)message;

@end
