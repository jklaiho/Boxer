/* 
 Boxer is copyright 2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXOperation.h"
#import "BXOperationDelegate.h"

#pragma mark -
#pragma mark Notification constants and keys

NSString * const BXOperationWillStart		= @"BXOperationWillStart";
NSString * const BXOperationDidFinish		= @"BXOperationDidFinish";
NSString * const BXOperationInProgress		= @"BXOperationInProgress";
NSString * const BXOperationWasCancelled	= @"BXOperationWasCancelled";

NSString * const BXOperationContextInfoKey	= @"BXOperationContextInfoKey";
NSString * const BXOperationSuccessKey		= @"BXOperationSuccessKey";
NSString * const BXOperationErrorKey		= @"BXOperationErrorKey";
NSString * const BXOperationProgressKey		= @"BXOperationProgressKey";
NSString * const BXOperationIndeterminateKey	= @"BXOperationIndeterminateKey";


@implementation BXOperation
@synthesize delegate, contextInfo, notifyOnMainThread;
@synthesize error;
@synthesize willStartSelector, wasCancelledSelector, inProgressSelector, didFinishSelector;

- (id) init
{
	if ((self = [super init]))
	{
		[self setNotifyOnMainThread: YES];
		[self setWillStartSelector:		@selector(operationWillStart:)];
		[self setInProgressSelector:	@selector(operationInProgress:)];
		[self setWasCancelledSelector:	@selector(operationWasCancelled:)];
		[self setDidFinishSelector:		@selector(operationDidFinish:)];
	}
	return self;
}

- (void) dealloc
{
	[self setDelegate: nil];
	
	[self setContextInfo: nil], [contextInfo release];
	[self setError: nil], [error release];
	
	[super dealloc];
}

- (void) start
{
    [self _sendWillStartNotificationWithInfo: nil];
    [super start];
    [self _sendDidFinishNotificationWithInfo: nil];
}

- (void) main
{
    if ([self shouldPerformOperation])
    {
        [self willPerformOperation];
        //In case willPerformOperation has cancelled us already
        if (![self isCancelled]) [self performOperation];
        [self didPerformOperation];
    }
}

- (BOOL) shouldPerformOperation
{
    //Don’t bother starting if we are already cancelled
    return ![self isCancelled];
}

- (void) willPerformOperation {}
- (void) didPerformOperation {}
- (void) performOperation {}

- (void) cancel
{	
	//Only send a notification the first time we're cancelled,
	//and only if we're in progress when we get cancelled
	if (![self isCancelled] && [self isExecuting])
	{
		[super cancel];
		if (![self error])
		{
			//If we haven't encountered a more serious error, set the error to indicate that this operation was cancelled.
			[self setError: [NSError errorWithDomain: NSCocoaErrorDomain
												code: NSUserCancelledError
											userInfo: nil]];
		}
		[self _sendWasCancelledNotificationWithInfo: nil];
	}
	else [super cancel];
}

- (BOOL) succeeded
{
    return ![self error];
}

//The following are meant to be overridden by subclasses to provide more meaningful progress tracking.
- (BXOperationProgress) currentProgress
{
	return 0.0f;
}

+ (NSSet *) keyPathsForValuesAffectingTimeRemaining
{
	return [NSSet setWithObjects: @"currentProgress", @"isFinished", nil];
}

- (NSTimeInterval) timeRemaining
{
	return [self isFinished] ? 0.0 : BXUnknownTimeRemaining;
}

- (BOOL) isIndeterminate
{
	return YES;
}


#pragma mark -
#pragma mark Notifications

- (void) _sendWillStartNotificationWithInfo: (NSDictionary *)info
{
	//Don't send start notifications if we're already cancelled
	if ([self isCancelled]) return;
	
	[self _postNotificationName: BXOperationWillStart
			   delegateSelector: [self willStartSelector]
	 				   userInfo: info];
}

- (void) _sendWasCancelledNotificationWithInfo: (NSDictionary *)info
{
	[self _postNotificationName: BXOperationWasCancelled
			   delegateSelector: [self wasCancelledSelector]
					   userInfo: info];
}

- (void) _sendDidFinishNotificationWithInfo: (NSDictionary *)info
{
	NSMutableDictionary *finishInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
									   [NSNumber numberWithBool: [self succeeded]], BXOperationSuccessKey,
									   [self error], BXOperationErrorKey,
									   nil];

	if (info) [finishInfo addEntriesFromDictionary: info];

	[self _postNotificationName: BXOperationDidFinish
			   delegateSelector: [self didFinishSelector]
					   userInfo: finishInfo];
}

- (void) _sendInProgressNotificationWithInfo: (NSDictionary *)info
{
	//Don't send progress notifications if we're already cancelled
	if ([self isCancelled]) return;
	
	NSMutableDictionary *progressInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										 [NSNumber numberWithFloat: [self currentProgress]],	BXOperationProgressKey,
										 [NSNumber numberWithBool: [self isIndeterminate]],		BXOperationIndeterminateKey,
										 nil];
	if (info) [progressInfo addEntriesFromDictionary: info];
	
	[self _postNotificationName: BXOperationInProgress
			   delegateSelector: [self inProgressSelector]
					   userInfo: progressInfo];
}


- (void) _postNotificationName: (NSString *)name
			  delegateSelector: (SEL)selector
					  userInfo: (NSDictionary *)userInfo
{
	//Extend the notification dictionary with context info
	if ([self contextInfo])
	{
		NSMutableDictionary *contextDict = [NSMutableDictionary dictionaryWithObject: [self contextInfo]
																			  forKey: BXOperationContextInfoKey];
		if (userInfo) [contextDict addEntriesFromDictionary: userInfo];
		userInfo = contextDict;
	}
	
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	NSNotification *notification = [NSNotification notificationWithName: name
																 object: self
															   userInfo: userInfo];
	
	if ([[self delegate] respondsToSelector: selector])
	{
		if ([self notifyOnMainThread])
			[(id)[self delegate] performSelectorOnMainThread: selector withObject: notification waitUntilDone: NO];
		else
			[[self delegate] performSelector: selector withObject: notification];
	}
	
	if ([self notifyOnMainThread])
		[center performSelectorOnMainThread: @selector(postNotification:) withObject: notification waitUntilDone: NO];		
	else
		[center postNotification: notification];
}

@end
