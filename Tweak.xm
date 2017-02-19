#import <substrate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <libkern/OSAtomic.h>

NSString* kMicFilePath = @"/var/mobile/Media/DCIM/mic.caf";
NSString* kSpeakerFilePath = @"/var/mobile/Media/DCIM/speaker.caf";
NSString* kResultFilePath = @"/var/mobile/Media/DCIM/recless.m4a";

OSSpinLock recordIsActiveLock = 0;
OSSpinLock speakerLock = 0;
OSSpinLock micLock = 0;

ExtAudioFileRef micFile = NULL;
ExtAudioFileRef speakerFile = NULL;

BOOL recordIsActive = NO;

void convertMicSpeaker() {
    NSLog(@"convertMicSpeaker called");
    //File URLs
    CFURLRef micUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kMicFilePath, kCFURLPOSIXPathStyle, false);
    CFURLRef speakerUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kSpeakerFilePath, kCFURLPOSIXPathStyle, false);
    CFURLRef resultUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kResultFilePath, kCFURLPOSIXPathStyle, false);

    ExtAudioFileRef micFile = NULL;
    ExtAudioFileRef speakerFile = NULL;
    ExtAudioFileRef resultFile = NULL;

    //Opening input files (speaker and mic)
    ExtAudioFileOpenURL(micUrl, &micFile);
    ExtAudioFileOpenURL(speakerUrl, &speakerFile);

    //Reading input file audio format (mono LPCM)
    AudioStreamBasicDescription inputFormat, outputFormat;
    UInt32 descSize = sizeof(inputFormat);
    ExtAudioFileGetProperty(micFile, kExtAudioFileProperty_FileDataFormat, &descSize, &inputFormat);
    int sampleSize = inputFormat.mBytesPerFrame;

    //Filling input stream format for output file (stereo LPCM)
    FillOutASBDForLPCM(inputFormat, inputFormat.mSampleRate, 2, inputFormat.mBitsPerChannel, inputFormat.mBitsPerChannel, true, false, false);

    //Filling output file audio format (AAC)
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mFormatID = kAudioFormatMPEG4AAC;
    outputFormat.mSampleRate = 8000;
    outputFormat.mFormatFlags = kMPEG4Object_AAC_Main;
    outputFormat.mChannelsPerFrame = 2;

    //Opening output file
    ExtAudioFileCreateWithURL(resultUrl, kAudioFileM4AType, &outputFormat, NULL, kAudioFileFlags_EraseFile, &resultFile);
    ExtAudioFileSetProperty(resultFile, kExtAudioFileProperty_ClientDataFormat, sizeof(inputFormat), &inputFormat);

    //Freeing URLs
    CFRelease(micUrl);
    CFRelease(speakerUrl);
    CFRelease(resultUrl);

    //Setting up audio buffers
    int bufferSizeInSamples = 64 * 1024;

    AudioBufferList micBuffer;
    micBuffer.mNumberBuffers = 1;
    micBuffer.mBuffers[0].mNumberChannels = 1;
    micBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples;
    micBuffer.mBuffers[0].mData = malloc(micBuffer.mBuffers[0].mDataByteSize);

    AudioBufferList speakerBuffer;
    speakerBuffer.mNumberBuffers = 1;
    speakerBuffer.mBuffers[0].mNumberChannels = 1;
    speakerBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples;
    speakerBuffer.mBuffers[0].mData = malloc(speakerBuffer.mBuffers[0].mDataByteSize);

    AudioBufferList resultBuffer;
    resultBuffer.mNumberBuffers = 1;
    resultBuffer.mBuffers[0].mNumberChannels = 2;
    resultBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples * 2;
    resultBuffer.mBuffers[0].mData = malloc(resultBuffer.mBuffers[0].mDataByteSize);

    //Converting
    while (true) {
        //Reading data from input files
        UInt32 framesToRead = bufferSizeInSamples;
        ExtAudioFileRead(micFile, &framesToRead, &micBuffer);
        ExtAudioFileRead(speakerFile, &framesToRead, &speakerBuffer);
        if (framesToRead == 0) {
            break;
        }

        //Building interleaved stereo buffer - left channel is mic, right - speaker
        for (int i = 0; i < framesToRead; i++) {
            memcpy((char*)resultBuffer.mBuffers[0].mData + i * sampleSize * 2, (char*)micBuffer.mBuffers[0].mData + i * sampleSize, sampleSize);
            memcpy((char*)resultBuffer.mBuffers[0].mData + i * sampleSize * 2 + sampleSize, (char*)speakerBuffer.mBuffers[0].mData + i * sampleSize, sampleSize);
        }

        //Writing to output file - LPCM will be converted to AAC
        ExtAudioFileWrite(resultFile, framesToRead, &resultBuffer);
    }

    //Closing files
    ExtAudioFileDispose(micFile);
    ExtAudioFileDispose(speakerFile);
    ExtAudioFileDispose(resultFile);

    //Freeing audio buffers
    free(micBuffer.mBuffers[0].mData);
    free(speakerBuffer.mBuffers[0].mData);
    free(resultBuffer.mBuffers[0].mData);
}

void convertMic() {
    NSLog(@"convertMic called");
    //File URLs
    CFURLRef micUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kMicFilePath, kCFURLPOSIXPathStyle, false);
    CFURLRef resultUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kResultFilePath, kCFURLPOSIXPathStyle, false);

    ExtAudioFileRef micFile = NULL;
    ExtAudioFileRef resultFile = NULL;

    //Opening input files (speaker)
    ExtAudioFileOpenURL(micUrl, &micFile);

    //Reading input file audio format (mono LPCM)
    AudioStreamBasicDescription inputFormat, outputFormat;
    UInt32 descSize = sizeof(inputFormat);
    ExtAudioFileGetProperty(micFile, kExtAudioFileProperty_FileDataFormat, &descSize, &inputFormat);
    int sampleSize = inputFormat.mBytesPerFrame;

    //Filling input stream format for output file (stereo LPCM)
    FillOutASBDForLPCM(inputFormat, inputFormat.mSampleRate, 2, inputFormat.mBitsPerChannel, inputFormat.mBitsPerChannel, true, false, false);

    //Filling output file audio format (AAC)
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mFormatID = kAudioFormatMPEG4AAC;
    outputFormat.mSampleRate = 8000;
    outputFormat.mFormatFlags = kMPEG4Object_AAC_Main;
    outputFormat.mChannelsPerFrame = 2;

    //Opening output file
    ExtAudioFileCreateWithURL(resultUrl, kAudioFileM4AType, &outputFormat, NULL, kAudioFileFlags_EraseFile, &resultFile);
    ExtAudioFileSetProperty(resultFile, kExtAudioFileProperty_ClientDataFormat, sizeof(inputFormat), &inputFormat);

    //Freeing URLs
    CFRelease(micUrl);
    CFRelease(resultUrl);

    //Setting up audio buffers
    int bufferSizeInSamples = 64 * 1024;

    AudioBufferList micBuffer;
    micBuffer.mNumberBuffers = 1;
    micBuffer.mBuffers[0].mNumberChannels = 1;
    micBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples;
    micBuffer.mBuffers[0].mData = malloc(micBuffer.mBuffers[0].mDataByteSize);

    AudioBufferList resultBuffer;
    resultBuffer.mNumberBuffers = 1;
    resultBuffer.mBuffers[0].mNumberChannels = 2;
    resultBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples * 2;
    resultBuffer.mBuffers[0].mData = malloc(resultBuffer.mBuffers[0].mDataByteSize);

    //Converting
    while (true) {
        //Reading data from input files
        UInt32 framesToRead = bufferSizeInSamples;
        ExtAudioFileRead(micFile, &framesToRead, &micBuffer);
        if (framesToRead == 0) {
            break;
        }

        //Building interleaved stereo buffer - left channel is mic, right - mic
        for (int i = 0; i < framesToRead; i++) {
            memcpy((char*)resultBuffer.mBuffers[0].mData + i * sampleSize * 2, (char*)micBuffer.mBuffers[0].mData + i * sampleSize, sampleSize);
        }

        //Writing to output file - LPCM will be converted to AAC
        ExtAudioFileWrite(resultFile, framesToRead, &resultBuffer);
    }

    //Closing files
    ExtAudioFileDispose(micFile);
    ExtAudioFileDispose(resultFile);

    //Freeing audio buffers
    free(micBuffer.mBuffers[0].mData);
    free(resultBuffer.mBuffers[0].mData);
}

void convertSpeaker() {
    NSLog(@"convertSpeaker called");
    //File URLs
    CFURLRef speakerUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kSpeakerFilePath, kCFURLPOSIXPathStyle, false);
    CFURLRef resultUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)kResultFilePath, kCFURLPOSIXPathStyle, false);

    ExtAudioFileRef speakerFile = NULL;
    ExtAudioFileRef resultFile = NULL;

    //Opening input files (speaker)
    ExtAudioFileOpenURL(speakerUrl, &speakerFile);

    //Reading input file audio format (mono LPCM)
    AudioStreamBasicDescription inputFormat, outputFormat;
    UInt32 descSize = sizeof(inputFormat);
    ExtAudioFileGetProperty(speakerFile, kExtAudioFileProperty_FileDataFormat, &descSize, &inputFormat);
    int sampleSize = inputFormat.mBytesPerFrame;

    //Filling input stream format for output file (stereo LPCM)
    FillOutASBDForLPCM(inputFormat, inputFormat.mSampleRate, 2, inputFormat.mBitsPerChannel, inputFormat.mBitsPerChannel, true, false, false);

    //Filling output file audio format (AAC)
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mFormatID = kAudioFormatMPEG4AAC;
    outputFormat.mSampleRate = 8000;
    outputFormat.mFormatFlags = kMPEG4Object_AAC_Main;
    outputFormat.mChannelsPerFrame = 2;

    //Opening output file
    ExtAudioFileCreateWithURL(resultUrl, kAudioFileM4AType, &outputFormat, NULL, kAudioFileFlags_EraseFile, &resultFile);
    ExtAudioFileSetProperty(resultFile, kExtAudioFileProperty_ClientDataFormat, sizeof(inputFormat), &inputFormat);

    //Freeing URLs
    CFRelease(speakerUrl);
    CFRelease(resultUrl);

    //Setting up audio buffers
    int bufferSizeInSamples = 64 * 1024;

    AudioBufferList speakerBuffer;
    speakerBuffer.mNumberBuffers = 1;
    speakerBuffer.mBuffers[0].mNumberChannels = 1;
    speakerBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples;
    speakerBuffer.mBuffers[0].mData = malloc(speakerBuffer.mBuffers[0].mDataByteSize);

    AudioBufferList resultBuffer;
    resultBuffer.mNumberBuffers = 1;
    resultBuffer.mBuffers[0].mNumberChannels = 2;
    resultBuffer.mBuffers[0].mDataByteSize = sampleSize * bufferSizeInSamples * 2;
    resultBuffer.mBuffers[0].mData = malloc(resultBuffer.mBuffers[0].mDataByteSize);

    //Converting
    while (true) {
        //Reading data from input files
        UInt32 framesToRead = bufferSizeInSamples;
        ExtAudioFileRead(speakerFile, &framesToRead, &speakerBuffer);
        if (framesToRead == 0) {
            break;
        }

        //Building interleaved stereo buffer - left channel is speaker, right - speaker
        for (int i = 0; i < framesToRead; i++) {
            memcpy((char*)resultBuffer.mBuffers[0].mData + i * sampleSize * 2, (char*)speakerBuffer.mBuffers[0].mData + i * sampleSize, sampleSize);
        }

        //Writing to output file - LPCM will be converted to AAC
        ExtAudioFileWrite(resultFile, framesToRead, &resultBuffer);
    }

    //Closing files
    ExtAudioFileDispose(speakerFile);
    ExtAudioFileDispose(resultFile);

    //Freeing audio buffers
    free(speakerBuffer.mBuffers[0].mData);
    free(resultBuffer.mBuffers[0].mData);
}

void cleanupMicSpeaker() {
    NSLog(@"cleanupMicSpeaker called");
    //[[NSFileManager defaultManager] removeItemAtPath:kMicFilePath error:NULL];
    //[[NSFileManager defaultManager] removeItemAtPath:kSpeakerFilePath error:NULL];
}

void cleanupMic() {
    NSLog(@"cleanupMic called");
    [[NSFileManager defaultManager] removeItemAtPath:kMicFilePath error:NULL];
}

void cleanupSpeaker() {
    NSLog(@"cleanupSpeaker called");
    [[NSFileManager defaultManager] removeItemAtPath:kSpeakerFilePath error:NULL];
}

void startMicSpeakerNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"startMicSpeakerNotificationCallback called");

    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = YES;
    OSSpinLockUnlock(&recordIsActiveLock);
}

void stopMicSpeakerNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"stopMicSpeakerNotificationCallback called");

    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = NO;
    OSSpinLockUnlock(&recordIsActiveLock);

    //Closing mic file
    OSSpinLockLock(&micLock);
    if (micFile != NULL) {
        ExtAudioFileDispose(micFile);
    }
    micFile = NULL;
    OSSpinLockUnlock(&micLock);

    //Closing speaker file
    OSSpinLockLock(&speakerLock);
    if (speakerFile != NULL) {
        ExtAudioFileDispose(speakerFile);
    }
    speakerFile = NULL;
    OSSpinLockUnlock(&speakerLock);

    convertMicSpeaker();
    cleanupMicSpeaker();
}

void startMicNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"startMicNotificationCallback called");

    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = YES;
    OSSpinLockUnlock(&recordIsActiveLock);
}

void stopMicNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"stopMicNotificationCallback called");

    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = NO;
    OSSpinLockUnlock(&recordIsActiveLock);

    //Closing mic file
    OSSpinLockLock(&micLock);
    if (micFile != NULL) {
        ExtAudioFileDispose(micFile);
    }
    micFile = NULL;
    OSSpinLockUnlock(&micLock);

    //Closing speaker file
    OSSpinLockLock(&speakerLock);
    if (speakerFile != NULL) {
        ExtAudioFileDispose(speakerFile);
    }
    speakerFile = NULL;
    OSSpinLockUnlock(&speakerLock);

    convertMic();
    cleanupMic();
}

void startSpeakerNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"startSpeakerNotificationCallback called");

    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = YES;
    OSSpinLockUnlock(&recordIsActiveLock);
}

void stopSpeakerNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"stopSpeakerNotificationCallback called");
    OSSpinLockLock(&recordIsActiveLock);
    recordIsActive = NO;
    OSSpinLockUnlock(&recordIsActiveLock);

    //Closing mic file
    OSSpinLockLock(&micLock);
    if (micFile != NULL) {
        ExtAudioFileDispose(micFile);
    }
    micFile = NULL;
    OSSpinLockUnlock(&micLock);

    //Closing speaker file
    OSSpinLockLock(&speakerLock);
    if (speakerFile != NULL) {
        ExtAudioFileDispose(speakerFile);
    }
    speakerFile = NULL;
    OSSpinLockUnlock(&speakerLock);

    convertSpeaker();
    cleanupSpeaker();
}

OSStatus(*AudioUnitProcess_orig)(AudioUnit unit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inNumberFrames, AudioBufferList *ioData);
OSStatus AudioUnitProcess_hook(AudioUnit unit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSSpinLockLock(&recordIsActiveLock);
    if (recordIsActive == NO) {
        OSSpinLockUnlock(&recordIsActiveLock);
        return AudioUnitProcess_orig(unit, ioActionFlags, inTimeStamp, inNumberFrames, ioData);
    }
    OSSpinLockUnlock(&recordIsActiveLock);

    ExtAudioFileRef* currentFile = NULL;
    OSSpinLock* currentLock = NULL;

    AudioComponentDescription unitDescription = {0};
    AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit), &unitDescription);
    //'agcc', 'mbdp' - iPhone 4S, iPhone 5
    //'agc2', 'vrq2' - iPhone 5C, iPhone 5S
    if (unitDescription.componentSubType == 'agcc' || unitDescription.componentSubType == 'agc2') {
        currentFile = &micFile;
        currentLock = &micLock;
    } else if (unitDescription.componentSubType == 'mbdp' || unitDescription.componentSubType == 'vrq2') {
        currentFile = &speakerFile;
        currentLock = &speakerLock;
    }

    if (currentFile != NULL) {
        OSSpinLockLock(currentLock);

        //Opening file
        if (*currentFile == NULL) {
            //Obtaining input audio format
            AudioStreamBasicDescription desc;
            UInt32 descSize = sizeof(desc);
            AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &desc, &descSize);

            //Opening audio file
            CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)((currentFile == &micFile) ? kMicFilePath : kSpeakerFilePath), kCFURLPOSIXPathStyle, false);
            ExtAudioFileRef audioFile = NULL;
            OSStatus result = ExtAudioFileCreateWithURL(url, kAudioFileCAFType, &desc, NULL, kAudioFileFlags_EraseFile, &audioFile);
            if (result != 0) {
                *currentFile = NULL;
            } else {
                *currentFile = audioFile;

                //Writing audio format
                ExtAudioFileSetProperty(*currentFile, kExtAudioFileProperty_ClientDataFormat, sizeof(desc), &desc);
            }
            CFRelease(url);
        } else {
            //Writing audio buffer
            ExtAudioFileWrite(*currentFile, inNumberFrames, ioData);
        }

        OSSpinLockUnlock(currentLock);
    }

    return AudioUnitProcess_orig(unit, ioActionFlags, inTimeStamp, inNumberFrames, ioData);
}

__attribute__((constructor))
static void initialize() {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, startMicSpeakerNotificationCallback, CFSTR("recless.start.mic.speaker"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, stopMicSpeakerNotificationCallback, CFSTR("recless.stop.mic.speaker"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, startMicNotificationCallback, CFSTR("recless.start.mic"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, stopMicNotificationCallback, CFSTR("recless.stop.mic"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, startSpeakerNotificationCallback, CFSTR("recless.start.speaker"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, stopSpeakerNotificationCallback, CFSTR("recless.stop.speaker"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    MSHookFunction(AudioUnitProcess, AudioUnitProcess_hook, &AudioUnitProcess_orig);
}
