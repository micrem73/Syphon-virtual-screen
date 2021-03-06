//
//  EWVirtualScreenController.m
//  EWProxyFrameBuffer
//
//  Created by Andrea Cremaschi on 21/03/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "EWVirtualScreenController.h"
#include <EWProxyFrameBufferConnection/EWProxyFrameBuffer.h>

@interface EWVirtualScreenController() {
    io_service_t _service;
    io_connect_t _connect;
    unsigned char *_driverbuf;
}

@property (readwrite, strong) NSMutableArray *_profiles;
@property (readwrite, strong) NSMutableArray *_profileNames;
@property (readwrite) bool isFramebufferActive;
@property (readwrite) int currentMode;

@end


@implementation EWVirtualScreenController
@synthesize _profiles, _profileNames;
@synthesize isFramebufferActive;
@synthesize currentMode ;

#pragma mark - Initialization

- (id)init
{
    self = [super init];
    if (self)
    {
        _profileNames=[[NSMutableArray alloc] init];
        _profiles=[[NSMutableArray alloc] init];
        currentMode=-1;
    }
    return self;
}


#pragma mark - Accessors
- (NSArray *)profileNames
{
    return [_profileNames copy];
}

- (NSArray *)profiles
{
    return [_profiles copy];
}

-(int)currentMode
{
    if (!self.isFramebufferActive) return -1;    
    return EWProxyFramebufferDriverCheckFramebufferState(_connect);
}

-(void)setCurrentMode:(int)value
{
    currentMode = value;
}

#pragma mark - Connection
- (BOOL) setupConnection
{
	//check for driver. if found, set everything up.
	_service = FindEWProxyFramebufferDriver();
	if(_service == IO_OBJECT_NULL)
        return NO;
	else
	{
		//establish connection.
		//this call instantiates our user client class in kernel code and attaches it to
		//the IOService in question
		if(IOServiceOpen(_service, mach_task_self(), 0, &_connect)==kIOReturnSuccess)
		{
			//read the driver configuration and set up internal classes
			int cnt=EWProxyFramebufferDriverGetModeCount(_connect);
			[self willChangeValueForKey:@"profileNames"];
			EWProxyFramebufferModeInfo data;
			for(int i=1;i<=cnt;i++)
			{
				EWProxyFramebufferDriverGetModeInfo(_connect, i, &data);
				[_profileNames addObject: [NSString stringWithCString: data.name encoding: NSASCIIStringEncoding]];
				[_profiles addObject: [NSData dataWithBytes:&data length: sizeof(data)]];
			}
			[self didChangeValueForKey:@"profileNames"];
            
			int state=EWProxyFramebufferDriverCheckFramebufferState(_connect);
			if(state!=0)
				self.isFramebufferActive=YES;
			else
				self.isFramebufferActive=NO;
			
            
            //create a notification port and register it in our runloop.
			//this is nessecary for the cursor change events.
			//we can ask the notificationport for a mach_port which is then used in registerEvent functions
			//however we're not implementing them yet.
			//TODO
			IONotificationPortRef notifyPort=IONotificationPortCreate(kIOMasterPortDefault);
			CFRunLoopSourceRef rlsource=IONotificationPortGetRunLoopSource(notifyPort);
			CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], rlsource, kCFRunLoopDefaultMode);
            
            return YES;
		}
		else
            return NO;
    }
}

- (BOOL) setVirtualScreenEnabled: (BOOL) enable waitUntilDone: (BOOL) waitUntilDone
{
    bool retVal=NO;
    int mode;
    
    //check current state.
//	int state=EWProxyFramebufferDriverCheckFramebufferState(connect);
	if (!enable)
    {
        //NSLog( @"Trying to disable virtual screen");

		//framebuffer is on, disable it. unmap framebuffer and disable it.
		EWProxyFramebufferDriverUnmapFramebuffer(_connect, _driverbuf);
		EWProxyFramebufferDriverDisableFramebuffer(_connect);
        self.isFramebufferActive=NO;
        mode=0;
	}
	else
	{
		mode = currentMode;
        if ((currentMode<0) || (currentMode> _profiles.count)) 
        {
            mode = 3;
            self.currentMode = mode;
        }

        //NSLog( @"Trying to enable virtual screen with mode: %i", mode);

		//enable with selected mode
		EWProxyFramebufferDriverEnableFramebuffer(_connect, mode);

		//map memory
		unsigned int size;
		_driverbuf=EWProxyFramebufferDriverMapFramebuffer(_connect, &size);
        self.isFramebufferActive=YES;
        
	}
    
    retVal = YES;
    
    if (waitUntilDone)
    {
        int result = 0;
        bool __block timeout=NO;
        
        double delayInSeconds = 5.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            timeout=YES;
        });
        do {
            result = EWProxyFramebufferDriverCheckFramebufferState(_connect);
            //NSLog(@"%i", result);
        } while ((mode != result) && !timeout);
        retVal = timeout;
        
    }

    return retVal;
    
}

- (void) setVirtualScreenEnabled: (BOOL) enable
{
    [self setVirtualScreenEnabled: enable waitUntilDone: YES];
}


- (bool) setVirtualScreenEnabledWithMode: (int) mode 
                           waitUntilDone: (BOOL) waitUntilDone
{
    
    [self switchToMode: mode];
    if (!self.isFramebufferActive)
        [self setVirtualScreenEnabled:YES];
    
    if (waitUntilDone)
    {
   /*     // Wait for Core Graphics to be set with the new virtual device
        CGDirectDisplayID activeDisplays[10]; 
        CGDirectDisplayID displayID;
        uint32_t displayCount;
        bool __block timeout=NO;
        
        double delayInSeconds = 10.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            timeout=YES;
        });
        
        do {
            CGGetActiveDisplayList(10,
                                   activeDisplays, &displayCount);                    
            displayID = activeDisplays[displayCount-1];
            
        } while (!timeout && (displayID == CGMainDisplayID()));
        
        return !timeout;*/

        // wait 5 seconds.. this is a brutal workaround!
        sleep(5.0);
        
    }

    return YES;
    
}

-(void)switchToMode: (int) mode
{
    bool curStatus=self.isFramebufferActive;
    if (curStatus)
        [self setVirtualScreenEnabled: NO];
    self.currentMode = mode;
    if (curStatus)
        [self setVirtualScreenEnabled: YES];
   // NSLog( @"Virtual screen is now %@ with mode: %i", (self.isFramebufferActive ? @"ON" : @"OFF"), self.currentMode);
    
}

- (bool)updateFramebuffer
{
    //tell driver to update buffer mapped to client memory
	int ret=EWProxyFramebufferDriverUpdateMemory(_connect);
	//NSLog(@"%x",ret);
    return ret==0;
	/*EWProxyFramebufferModeInfo *info=[self getCurrentModeInfo];
	//copy into nsdata object
	NSData *image=[[NSData alloc] initWithBytes:driverbuf length:info->width*info->height*3];
	//encapsulate into cg data provider
	CGDataProviderRef dataprovider=CGDataProviderCreateWithCFData((CFDataRef)image);
	//create cg image from provider
	CGImageRef cgimg=CGImageCreate(info->width, info->height, 8, 24, info->width*3, CGColorSpaceCreateDeviceRGB(), 0, dataprovider, NULL, NO, kCGRenderingIntentDefault);
	//create bitmapimagerepresentation
	NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:cgimg];
	//and stuff it into an nsimage
	NSImage *img=[[NSImage alloc] init];
	[img addRepresentation:rep];
	[imgView setImage:img];*/
}
@end
