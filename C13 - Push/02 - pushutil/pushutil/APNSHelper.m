/*
 Erica Sadun, http://ericasadun.com
 iPhone Developer's Cookbook, 3.0 Edition
 BSD License, Use at your own risk
 */

#import "APNSHelper.h"
#import "ioSock.h"

@implementation APNSHelper
@synthesize certificateData;
@synthesize deviceTokenID;
@synthesize useSandboxServer;

static APNSHelper *sharedInstance = nil;

+(APNSHelper *) sharedInstance {
    if(!sharedInstance) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id) init
{
    if (!(self = [super init])) return self;
    self.certificateData = nil;
    self.deviceTokenID = nil;
    return self;
}

// Adapted from code by Stefan Hafeneger
- (BOOL) push: (NSString *) payload
{
    otSocket socket;
    SSLContextRef context;
    SecKeychainRef keychain;
    SecIdentityRef identity;
    SecCertificateRef certificate;
    OSStatus result;

    // Ensure device token
    if (!self.deviceTokenID) 
    {
        printf("Error: Device Token is nil\n");
        return NO;
    }
    
    // Ensure certificate
    if (!self.certificateData)
    {
        printf("Error: Certificate Data is nil\n");
        return NO;
    }
    
    // Establish connection to server.
    PeerSpec peer;
    if (self.useSandboxServer)
    {
        printf("Sending message via sandbox\n");
        result = MakeServerConnection("gateway.sandbox.push.apple.com", 2195, &socket, &peer);
    }
    else
        result = MakeServerConnection("gateway.push.apple.com", 2195, &socket, &peer);
    if (result)
    {
        printf("Error creating server connection\n");
        return NO;
    }
    
    // Create new SSL context.
    result = SSLNewContext(false, &context);
    if (result)
    {
        printf("Error creating SSL context\n");
        return NO;
    }
    
    // Set callback functions for SSL context.
    result = SSLSetIOFuncs(context, SocketRead, SocketWrite);
    if (result)
    {
        printf("Error setting SSL context callback functions\n");
        return NO;
    }
    
    // Set SSL context connection.
    result = SSLSetConnection(context, socket);
    if (result)
    {
        printf("Error setting the SSL context connection\n");
        return NO;
    }
    
    // Set server domain name.
    result = SSLSetPeerDomainName(context, "gateway.sandbox.push.apple.com", 30);
    if (result)
    {
        printf("Error setting the server domain name\n");
        return NO;
    }
    
    // Open keychain.
    result = SecKeychainCopyDefault(&keychain);
    if (result)
    {
        printf("Error accessing keychain\n");
        return NO;
    }

    // Create certificate from data
    CFDataRef data = (__bridge CFDataRef) self.certificateData;
    certificate = SecCertificateCreateWithData(kCFAllocatorDefault, data);
    if (!certificate)
    {
        printf("Error creating certificate from data\n");
        return NO;
    }
    
    // Create identity.
    result = SecIdentityCreateWithCertificate(keychain, certificate, &identity);
    if (result)
    {
        printf("Error creating identity from certificate: %d\n", result);
        return NO;
    }
    
    // Disable Verify
    result = SSLSetEnableCertVerify(context, NO);
    if (result)
    {
        printf("Error disabling cert verify\n");
        return NO;
    }
    
    // Set client certificate.
    CFArrayRef certificates = CFArrayCreate(NULL, (const void **)&identity, 1, NULL);
    result = SSLSetCertificate(context, certificates);
    if (result)
    {
        printf("Error setting the client certificate\n");
        CFRelease(certificates);
        return NO;
    }

    CFRelease(certificates);
    
    // Perform SSL handshake.
    do {result = SSLHandshake(context);} while(result == errSSLWouldBlock);
    
    // Convert string into device token data.
    NSMutableData *deviceToken = [NSMutableData data];
    unsigned value;
    NSScanner *scanner = [NSScanner scannerWithString:self.deviceTokenID];
    while(![scanner isAtEnd]) {
        [scanner scanHexInt:&value];
        value = htonl(value);
        [deviceToken appendBytes:&value length:sizeof(value)];
    }
    
    // Create C input variables.
    char *deviceTokenBinary = (char *)[deviceToken bytes];
    char *payloadBinary = (char *)[payload UTF8String];
    size_t payloadLength = strlen(payloadBinary);
    
    // Prepare message
    uint8_t command = 0;
    char message[293];
    char *pointer = message;
    uint16_t networkTokenLength = htons(32);
    uint16_t networkPayloadLength = htons(payloadLength);
    
    // Compose message.
    memcpy(pointer, &command, sizeof(uint8_t));
    pointer += sizeof(uint8_t);
    memcpy(pointer, &networkTokenLength, sizeof(uint16_t));
    pointer += sizeof(uint16_t);
    memcpy(pointer, deviceTokenBinary, 32);
    pointer += 32;
    memcpy(pointer, &networkPayloadLength, sizeof(uint16_t));
    pointer += sizeof(uint16_t);
    memcpy(pointer, payloadBinary, payloadLength);
    pointer += payloadLength;
    
    // Send message over SSL.
    size_t processed = 0;
    result = SSLWrite(context, &message, (pointer - message), &processed);
    if (result)
    {
        printf("Error sending message via SSL.\n");
        return NO;
    }
    else
    {
        printf("Message sent.\n");
        return YES;
    }
}

- (NSArray *) fetchFeedback
{
    otSocket socket;
    SSLContextRef context;
    SecKeychainRef keychain;
    SecIdentityRef identity;
    SecCertificateRef certificate;
    OSStatus result;
    
    // Ensure device token
    if (!self.deviceTokenID) 
    {
        printf("Error: Device Token is nil\n");
        return nil;
    }
    
    // Ensure certificate
    if (!self.certificateData)
    {
        printf("Error: Certificate Data is nil\n");
        return nil;
    }
    
    // Establish connection to server.
    PeerSpec peer;
    if (self.useSandboxServer)
    {
        printf("Recovering feedback via sandbox\n");    
        result = MakeServerConnection("feedback.sandbox.push.apple.com", 2196, &socket, &peer);
    }
    else
        result = MakeServerConnection("feedback.push.apple.com", 2196, &socket, &peer);
    if (result)
    {
        printf("Error creating server connection\n");
        return nil;
    }
    
    // Create new SSL context.
    result = SSLNewContext(false, &context);
    if (result)
    {
        printf("Error creating SSL context\n");
        return nil;
    }
    
    // Set callback functions for SSL context.
    result = SSLSetIOFuncs(context, SocketRead, SocketWrite);
    if (result)
    {
        printf("Error setting SSL context callback functions\n");
        return nil;
    }
    
    // Set SSL context connection.
    result = SSLSetConnection(context, socket);
    if (result)
    {
        printf("Error setting the SSL context connection\n");
        return nil;
    }
    
    // Set server domain name.
    result = SSLSetPeerDomainName(context, "gateway.sandbox.push.apple.com", 30);
    if (result)
    {
        printf("Error setting the server domain name\n");
        return nil;
    }
    
    // Open keychain.
    result = SecKeychainCopyDefault(&keychain);
    if (result)
    {
        printf("Error accessing keychain\n");
        return nil;
    }
    
    // Create certificate from data
    CFDataRef data = (__bridge CFDataRef) self.certificateData;
    certificate = SecCertificateCreateWithData(kCFAllocatorDefault, data);
    if (!certificate)
    {
        printf("Error creating certificate from data\n");
        return nil;
    }
    
    // Create identity.
    result = SecIdentityCreateWithCertificate(keychain, certificate, &identity);
    if (result)
    {
        printf("Error creating identity from certificate\n");
        return nil;
    }
        
    // Disable Verify
    result = SSLSetEnableCertVerify(context, NO);
    if (result)
    {
        printf("Error disabling cert verify\n");
        return nil;
    }
    
    // Set client certificate.
    CFArrayRef certificates = CFArrayCreate(NULL, (const void **)&identity, 1, NULL);
    result = SSLSetCertificate(context, certificates);
    if (result)
    {
        printf("Error setting the client certificate\n");
        CFRelease(certificates);
        return nil;
    }
    CFRelease(certificates);
    
    // Perform SSL handshake.
    do {result = SSLHandshake(context);} while(result == errSSLWouldBlock);
    if (result)
    {
        cssmPerror("Error", result);
        return nil;
    }
    
    NSMutableArray *results = [NSMutableArray array];
    
    // 4 big endian bytes for time_t
    // 2 big endian bytes for token length (always 0, 32)
    // 32 bytes for device token
    
    // Retrieve message from SSL.
    size_t processed = 0;
    char buffer[38];
    do 
    {
        result = SSLRead(context, buffer, 38, &processed);
        if (result) break;

        // Recover Date
        char *b = buffer;
        NSTimeInterval ti = ((unsigned char)b[0] << 24) + ((unsigned char)b[1] << 16) + ((unsigned char)b[2] << 8) + (unsigned char)b[3];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ti];
                
        // Recover Device ID
        NSMutableString *deviceID = [NSMutableString string];
        b += 6;
        for (int i = 0; i < 32; i++) [deviceID appendFormat:@"%02x", (unsigned char)b[i]];

        // Add dictionary to results
        [results addObject:@{deviceID: date}];
        
    } while (processed > 0);
    
    return results;
}
@end
