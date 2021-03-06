/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXHUDProgressIndicator.h"
#import "NSShadow+BXShadowExtensions.h"
#import "NSBezierPath+MCAdditions.h"


@implementation BXHUDProgressIndicator

- (BOOL) isOpaque
{
    return NO;
}

- (BOOL) isBezeled
{
    return NO;
}

- (NSBezierPath *) stripePathForFrame: (NSRect)frame
                        animationTime: (NSTimeInterval)timeInterval
{
    CGFloat stripeWidth = frame.size.height;
    
    //Expand the frame so that our stripe will be unbroken.
    frame.size.width += (stripeWidth * 4);
    frame.origin.x -= (stripeWidth * 2);
    
    NSPoint offset = frame.origin;
    
    //Choose the starting offset based on our animation time: we complete
    //one full cycle of the stripes in a second.
    //TODO: abstract this calculation and allow it to have arbitrary timing.
    double ms = (long long)(timeInterval * 1000) % 1000;
    float animationProgress = (float)(ms / 1000);
    offset.x += (stripeWidth * 2 * animationProgress);
    
    //Now, walk across the frame drawing parallelograms!
    NSBezierPath *stripePath = [[NSBezierPath alloc] init];
    
    while(offset.x <= NSMaxX(frame))
    {
        [stripePath moveToPoint: offset];
        [stripePath lineToPoint: NSMakePoint(offset.x + stripeWidth,          offset.y)];
        [stripePath lineToPoint: NSMakePoint(offset.x + (stripeWidth * 2),    offset.y + stripeWidth)];
        [stripePath lineToPoint: NSMakePoint(offset.x + stripeWidth,          offset.y + stripeWidth)];
        [stripePath closePath];
        
        offset.x += (stripeWidth * 2);
    }
    
    return [stripePath autorelease];
}

- (void) drawSlotInRect: (NSRect)dirtyRect
{
    NSColor *strokeColor = [NSColor colorWithCalibratedWhite: 1.0f alpha: 0.5f];
    NSColor *fillColor = [NSColor colorWithCalibratedWhite: 0.0f alpha: 0.25f];
    
    NSShadow *fillShadow = [NSShadow shadowWithBlurRadius: 2.0f offset: NSMakeSize(0.0f, -1.0f)];
    
    NSRect fillRegion       = NSInsetRect([self bounds], 1.0f, 1.0f);
    NSRect strokeRegion     = NSInsetRect([self bounds], 0.5f, 0.5f);
    
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect: fillRegion
                                                             xRadius: fillRegion.size.height / 2
                                                             yRadius: fillRegion.size.height / 2];
    
    NSBezierPath *strokePath = [NSBezierPath bezierPathWithRoundedRect: strokeRegion
                                                               xRadius: strokeRegion.size.height / 2
                                                               yRadius: strokeRegion.size.height / 2];
    
    [NSGraphicsContext saveGraphicsState];
    [strokeColor setStroke];
    [fillColor setFill];
    
    [fillPath fill];
    [fillPath fillWithInnerShadow: fillShadow];
    [strokePath stroke];
    [NSGraphicsContext restoreGraphicsState];
}

- (void) drawIndeterminateProgressInRect: (NSRect)dirtyRect
{
    NSRect progressRegion = NSInsetRect([self bounds], 2.0f, 2.0f);
    
    if ([self needsToDrawRect: progressRegion])
    {
        NSBezierPath *progressPath = [NSBezierPath bezierPathWithRoundedRect: progressRegion
                                                                     xRadius: progressRegion.size.height / 2
                                                                     yRadius: progressRegion.size.height / 2];
        
        NSBezierPath *stripePath = [self stripePathForFrame: progressRegion
                                              animationTime: [NSDate timeIntervalSinceReferenceDate]];
        
        NSColor *stripeColor = [NSColor colorWithCalibratedWhite: 1.0f alpha: 0.25f];
        NSGradient *progressGradient = [[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 1.0f alpha: 0.5f]
                                                                     endingColor: [NSColor colorWithCalibratedWhite: 1.0f alpha: 0.25f]];
        
        [NSGraphicsContext saveGraphicsState];
        [progressPath addClip];
        
        [progressGradient drawInBezierPath: progressPath
                                     angle: 90.0f];
        
        [stripeColor setFill];
        [stripePath fill];
        [NSGraphicsContext restoreGraphicsState];
        
        [progressGradient release];
    }
}

- (void) drawProgressInRect: (NSRect)dirtyRect
{
    NSRect progressRegion = NSInsetRect([self bounds], 2.0f, 2.0f);
    
    //Work out how full the progress bar should be, and calculate from that how much of the path to draw
    double progress = ([self doubleValue] - [self minValue]) / ([self maxValue] - [self minValue]);
    
    NSRect progressClip = progressRegion;
    progressClip.size.width = roundf(progressClip.size.width * (float)progress);
    
    if ([self needsToDrawRect: progressClip])
    {
        NSBezierPath *progressPath = [NSBezierPath bezierPathWithRoundedRect: progressRegion
                                                                     xRadius: progressRegion.size.height / 2
                                                                     yRadius: progressRegion.size.height / 2];
        
        NSGradient *progressGradient = [[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 1.0f alpha: 1.0f]
                                                                     endingColor: [NSColor colorWithCalibratedWhite: 1.0f alpha: 0.66f]];
        
        [NSGraphicsContext saveGraphicsState];
        [NSBezierPath clipRect: progressClip];
        
        [progressGradient drawInBezierPath: progressPath
                                     angle: 90.0f];
        [NSGraphicsContext restoreGraphicsState];
        
        [progressGradient release];
    }
}

- (void) drawRect: (NSRect)dirtyRect
{
    [self drawSlotInRect: dirtyRect];
    
    if ([self isIndeterminate])
    {
        [self drawIndeterminateProgressInRect: dirtyRect];
    }
    else
    {
        [self drawProgressInRect: dirtyRect];
    }
}


#pragma mark -
#pragma mark Animation methods

//These needed to be reimplemented because NSProgressIndicator's own
//implementation causes nasty ugly overdraws for some goddamn reason.
//Note that these do not perform threaded animation yet.

- (void) performAnimation: (NSTimer *)timer
{
    if ([self isIndeterminate])
        [self setNeedsDisplay: YES];
}

- (void) startAnimation: (id)sender
{
    if (!animationTimer)
    {
        //Animate every 1/12th of a second, same as NSProgressIndicator.
        animationTimer = [NSTimer scheduledTimerWithTimeInterval: 5.0/60.0
                                                          target: self
                                                        selector: @selector(performAnimation:)
                                                        userInfo: nil
                                                         repeats: YES];
        [animationTimer retain];
    }
}

- (void) stopAnimation: (id)sender
{
    if (animationTimer)
    {
        [animationTimer invalidate];
        [animationTimer release];
        animationTimer = nil;
    }
}

- (void) viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    
    if (![self window])
        [self stopAnimation: self];
}

- (void) dealloc
{
    if (animationTimer)
        [self stopAnimation: self];
    
    [super dealloc];
}

@end
