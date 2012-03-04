/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXExternalMT32.h"
#import "BXExternalMT32+BXMT32Sysexes.h"

#define BXExternalMT32DelayFactor 1.25
#define BXExternalMT32BaseDelay 0.02


@implementation BXExternalMT32

- (BOOL) supportsMT32Music          { return YES; }
- (BOOL) supportsGeneralMIDIMusic   { return NO; }

- (NSTimeInterval) processingDelayForSysex: (NSData *)sysex
{
    //The calculations for these sysex processing delays have been adapted from DOSBox's delaysysex patch.
    NSTimeInterval baseDelay = (BXExternalMT32DelayFactor * _secondsPerByte * sysex.length) + BXExternalMT32BaseDelay;
    
    //If this wasn't a valid MT-32 sysex message, ignore it and go with the standard delay.
    //(Even if the MT-32 can't handle it, it'll still take time for it to reach the MT-32 and get rejected.)
    if (![[self class] isMT32Sysex: sysex confirmingSupport: NULL])
        return baseDelay;
    
    const UInt8 *contents = sysex.bytes;
    const UInt8 baseAddress     = contents[5],
                subAddress1     = contents[6],
                subAddress2     = contents[7];
    
    //All Parameters Reset
    if (baseAddress == BXMT32SysexAddressReset)
        return MAX(0.290, baseDelay);
    
    //Partial reserve part 1: fixes Viking Child
    if (baseAddress == BXMT32SysexAddressSystemArea && subAddress1 == 0x00 && subAddress2 == 0x04)
        return MAX(0.145, baseDelay);
    
    //Reverb: fixes Dark Sun 1
    if (baseAddress == BXMT32SysexAddressSystemArea && subAddress1 == 0x00 && subAddress2 == 0x01)
        return MAX(0.030, baseDelay);
    
    //Patch/timbre assignment: fixes Colonel's Bequest on my own shitty MIDI cable.
    if (baseAddress == BXMT32SysexAddressPatchMemory || baseAddress == BXMT32SysexAddressTimbreMemory)
        return MAX(0.040, baseDelay);
    
    return baseDelay;
}

@end
