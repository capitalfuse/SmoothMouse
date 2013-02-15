/* -*- mode: c++ -*-
 *
 * pointing-osx/transferfunctions/OSXFunction.h --
 *
 * Derived software from Apple under APSL licence
 * Authors: Nicolas Roussel, Géry Casiez
 * Copyright © Inria
 *
 * http://libpointing.org/
 *
 */

#include "OSXFunction.hpp"

//#include <pointing-osx/transferfunctions/OSXFunction.h>

//#include <pointing/utils/ByteOrder.h>
//#include <pointing/utils/FileUtils.h>
//#include <pointing/utils/Base64.h>

#ifdef __APPLE__
//#include <pointing/transferfunctions/osxSystemPointerAcceleration.h>
#endif

#include <iostream>
#include <sstream>

#include <assert.h>

#undef DEBUG
#ifdef DEBUG
#define LOG(fmt, ...) printf((fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#define LOG(...)
#endif



// -----------------------------------------------------------------------
// Inspired from /System/Library/Frameworks/Kernel.framework/Headers/IOKit/IOLib.h

#define IONew(type,number) new type [number]
#define IODelete(ptr,type,number) delete [] (type*)ptr



// -----------------------------------------------------------------------
// Inspired from /usr/include/libkern/OSTypes.h

#define SInt64 int64_t
#define SInt32 int32_t
#define UInt16 uint16_t
#define UInt32 uint32_t
#define UInt8 uint8_t
#define Boolean bool




namespace Base64 {
    std::string encode(std::string input) ;
    std::string decode(std::string input) ;
}

std::string
Base64::encode(std::string input) {
    std::string result ;

    unsigned char dtable[256] ;
    for(int i= 0;i<9;i++){
        dtable[i]= 'A'+i;
        dtable[i+9]= 'J'+i;
        dtable[26+i]= 'a'+i;
        dtable[26+i+9]= 'j'+i;
    }
    for(int i= 0;i<8;i++){
        dtable[i+18]= 'S'+i;
        dtable[26+i+18]= 's'+i;
    }
    for(int i= 0;i<10;i++) dtable[52+i]= '0'+i;
    dtable[62]= '+';
    dtable[63]= '/';

    unsigned int length = (unsigned int)input.length() ;
    for (unsigned int iInput=0; iInput<length;) {
        unsigned char igroup[3],ogroup[4];
        igroup[0]= igroup[1]= igroup[2]= 0;
        int n = 0 ;
        while (n<3 && iInput<length)
            igroup[n++]= (unsigned char)input[iInput++] ;
        if(n> 0){
            ogroup[0]= dtable[igroup[0]>>2];
            ogroup[1]= dtable[((igroup[0]&3)<<4)|(igroup[1]>>4)];
            ogroup[2]= dtable[((igroup[1]&0xF)<<2)|(igroup[2]>>6)];
            ogroup[3]= dtable[igroup[2]&0x3F];
            if(n<3){
                ogroup[3]= '=';
                if(n<2) ogroup[2]= '=';
            }
            for(int i= 0;i<4;i++) result = result + (char)ogroup[i] ;
        }
    }

    return result ;
}

std::string
Base64::decode(std::string input) {
    std::string result ;

    unsigned char dtable[256] ;
    for(int i= 0;i<255;i++) dtable[i]= 0x80;
    for(int i= 'A';i<='I';i++) dtable[i]= 0+(i-'A');
    for(int i= 'J';i<='R';i++) dtable[i]= 9+(i-'J');
    for(int i= 'S';i<='Z';i++) dtable[i]= 18+(i-'S');
    for(int i= 'a';i<='i';i++) dtable[i]= 26+(i-'a');
    for(int i= 'j';i<='r';i++) dtable[i]= 35+(i-'j');
    for(int i= 's';i<='z';i++) dtable[i]= 44+(i-'s');
    for(int i= '0';i<='9';i++) dtable[i]= 52+(i-'0');
    dtable[(int)'+']= 62;
    dtable[(int)'/']= 63;
    dtable[(int)'=']= 0;

    unsigned int length = (unsigned int)input.length() ;
    for (unsigned int iInput=0 ;;) {
        unsigned char a[4],b[4],o[3];

        for(int i= 0;i<4;i++){
            if (iInput==length) {
                // Incomplete input
                return result ;
            }
            int c = (int)input[iInput++] ;
            if(dtable[c]&0x80){
                i--; // Illegal character
                continue;
            }
            a[i]= (unsigned char)c;
            b[i]= (unsigned char)dtable[c];
        }

        o[0]= (b[0]<<2)|(b[1]>>4);
        o[1]= (b[1]<<4)|(b[2]>>2);
        o[2]= (b[2]<<6)|b[3];

        int i= a[2]=='='?1:(a[3]=='='?2:3);
        result.append((char*)o,i) ;
        if(i<3) return result ;
    }

    return result ;
}



bool isLittleEndian(void) {
    static uint32_t littleEndianTest = 1 ;
    return (*(char *)&littleEndianTest == 1) ;
}

uint16_t swap16(uint16_t arg) {
    return ((((arg) & 0xff) << 8) | (((arg) >> 8) & 0xff)) ;
}

uint16_t swap16ifle(uint16_t arg) {
    return isLittleEndian() ? swap16(arg) : arg ;
}

uint32_t swap32(uint32_t arg) {
    return ((((arg) & 0xff000000) >> 24) | \
            (((arg) & 0x00ff0000) >> 8)  | \
            (((arg) & 0x0000ff00) << 8)  | \
            (((arg) & 0x000000ff) << 24)) ;
}

uint32_t swap32ifle(uint32_t arg) {
    return isLittleEndian() ? swap32(arg) : arg ;
    return arg ;
}


// -----------------------------------------------------------------------
// Inspired from /System/Library/Frameworks/Kernel.framework/Headers/libkern/OSByteOrder.h

static inline uint16_t
OSReadBigInt16(const volatile void *base, uintptr_t byteOffset) {
    char *ptr = (char*)base+byteOffset ;
    return swap16ifle(*(uint16_t*)ptr) ;
}

static inline uint32_t
OSReadBigInt32(const volatile void *base, uintptr_t byteOffset) {
    char *ptr = (char*)base+byteOffset ;
    return swap32ifle(*(uint32_t*)ptr) ;
}


// -----------------------------------------------------------------------
// Inspired from /System/Library/Frameworks/Kernel.framework/Headers/libkern/c++/OSData.h
class OSData {
    int retainCount ;
    void *data ;
    unsigned int length ;
public:
    OSData(void *bytes, unsigned int numBytes) : retainCount(1), data(bytes), length(numBytes) {}
    void release(void) {
        retainCount-- ;
        if (!retainCount) delete this ;
    }
    const void *getBytesNoCopy(void) {
        return data ;
    }
    static OSData *withBytesNoCopy(void *bytes, unsigned int numBytes) {
        return new OSData(bytes, numBytes) ;
    }
} ;


// -----------------------------------------------------------------------
// From /System/Library/Frameworks/IOKit.framework/Headers/IOTypes.h

typedef UInt32		IOItemCount;

// -----------------------------------------------------------------------
// From /System/Library/Frameworks/Kernel.framework/Headers/IOKit/IOTypes.h

typedef SInt32		IOFixed;

// -----------------------------------------------------------------------
// From /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/CarbonCore.framework/Headers/MacTypes.h

typedef SInt32                          Fixed;

// -----------------------------------------------------------------------
// From /System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Headers/FixMath.h

#define fixed1              ((Fixed) 0x00010000L)
#define fract1              ((Fract) 0x40000000L)
#define positiveInfinity    ((Fixed)  0x7FFFFFFFL)
#define negativeInfinity    ((Fixed)  -0x80000000L)

#define IntToFixed(a)       ((Fixed)(a) << 16)
#define FloatToFixed(a) (_IntSaturate((a) * fixed1))

// -----------------------------------------------------------------------
// From IOHIDFamily-315.7.13/IOHIDSystem/IOHIPointing.cpp

#ifndef abs
#define abs(_a)	((_a >= 0) ? _a : -_a)
#endif

#define FRAME_RATE                  (67 << 16)
#define SCREEN_RESOLUTION           (96 << 16)

#define MAX_DEVICE_THRESHOLD        0x7fffffff

struct CursorDeviceSegment {
    SInt32	devUnits;
    SInt32	slope;
    SInt32	intercept;
};
typedef struct CursorDeviceSegment CursorDeviceSegment;

// -----------------------------------------------------------------------
// From /System/Library/Frameworks/Kernel.framework/Headers/IOKit/IOLib.h

static inline IOFixed IOFixedMultiply(IOFixed a, IOFixed b)
{
    return (IOFixed)((((SInt64) a) * ((SInt64) b)) >> 16);
}

static inline IOFixed IOFixedDivide(IOFixed a, IOFixed b)
{
    return (IOFixed)((((SInt64) a) << 16) / ((SInt64) b));
}

// -----------------------------------------------------------------------
// From IOHIDFamily-315.7.13/IOHIDSystem/IOHIPointing.cpp

/*
 Routine:    Interpolate
 This routine interpolates to find a point on the line [x1,y1] [x2,y2] which
 is intersected by the line [x3,y3] [x3,y"].  The resulting y' is calculated
 by interpolating between y3 and y", towards the higher acceleration curve.
 */

static SInt32 Interpolate(  SInt32 x1, SInt32 y1,
                          SInt32 x2, SInt32 y2,
                          SInt32 x3, SInt32 y3,
                          SInt32 scale, Boolean lower )
{

    SInt32 slope;
    SInt32 intercept;
    SInt32 resultY;

    slope = (x2 == x1) ? 0 : IOFixedDivide( y2 - y1, x2 - x1 );
    intercept = y1 - IOFixedMultiply( slope, x1 );
    resultY = intercept + IOFixedMultiply( slope, x3 );
    if( lower)
        resultY = y3 - IOFixedMultiply( scale, y3 - resultY );
    else
        resultY = resultY + IOFixedMultiply( scale, y3 - resultY );

    return( resultY );
}

// -----------------------------------------------------------------------
// From IOHIDFamily-315.7.13/IOHIDSystem/IOHIPointing.cpp

// RY: This function contains the original portions of
// setupForAcceleration.  This was separated out to
// accomidate the acceleration of scroll axes
bool SetupAcceleration (OSData * data, IOFixed desired, IOFixed devScale, IOFixed crsrScale, void ** scaleSegments, IOItemCount * scaleSegCount) {
    const UInt16 *	lowTable = 0;
    const UInt16 *	highTable;

    SInt32	x1, y1, x2, y2, x3, y3;
    SInt32	prevX1, prevY1;
    SInt32	upperX, upperY;
    SInt32	lowerX, lowerY;
    SInt32	lowAccl = 0, lowPoints = 0;
    SInt32	highAccl, highPoints;
    SInt32	scale;
    UInt32	count;
    Boolean	lower;

    SInt32	scaledX1, scaledY1;
    SInt32	scaledX2, scaledY2;

    CursorDeviceSegment *	segments;
    CursorDeviceSegment *	segment;
    SInt32			segCount;

    if( !data || !devScale || !crsrScale)
        return false;

    if( desired < (IOFixed) 0) {
        // disabling mouse scaling
        if(*scaleSegments && *scaleSegCount)
            IODelete( *scaleSegments,
                     CursorDeviceSegment, *scaleSegCount );
        *scaleSegments = NULL;
        *scaleSegCount = 0;
        data->release();
        return false;
    }

    highTable = (const UInt16 *) data->getBytesNoCopy();

    scaledX1 = scaledY1 = 0;

    scale = OSReadBigInt32((volatile void *)highTable, 0);
    highTable += 4;

    // normalize table's default (scale) to 0.5
    if( desired > 0x8000) {
        desired = IOFixedMultiply( desired - 0x8000,
                                  0x10000 - scale );
        desired <<= 1;
        desired += scale;
    } else {
        desired = IOFixedMultiply( desired, scale );
        desired <<= 1;
    }

    count = OSReadBigInt16((volatile void *)(highTable++), 0);
    scale = (1 << 16);

    // find curves bracketing the desired value
    do {
        highAccl = OSReadBigInt32((volatile void *)highTable, 0);
        highTable += 2;
        highPoints = OSReadBigInt16((volatile void *)(highTable++), 0);

        if( desired <= highAccl)
            break;

        if( 0 == --count) {
            // this much over the highest table
            scale = (highAccl) ? IOFixedDivide( desired, highAccl ) : 0;
            lowTable	= 0;
            break;
        }

        lowTable	= highTable;
        lowAccl		= highAccl;
        lowPoints	= highPoints;
        highTable	+= lowPoints * 4;

    } while( true );

    // scale between the two
    if( lowTable) {
        scale = (highAccl == lowAccl) ? 0 :
        IOFixedDivide((desired - lowAccl), (highAccl - lowAccl));

    }

    // or take all the high one
    else {
        lowTable	= highTable;
        //lowAccl		= highAccl; // dead store
        lowPoints	= 0;
    }

    if( lowPoints > highPoints)
        segCount = lowPoints;
    else
        segCount = highPoints;
    segCount *= 2;
    /*    IOLog("lowPoints %ld, highPoints %ld, segCount %ld\n",
     lowPoints, highPoints, segCount); */
    segments = IONew( CursorDeviceSegment, segCount );
    assert( segments );
    segment = segments;

    x1 = prevX1 = y1 = prevY1 = 0;

    lowerX = OSReadBigInt32((volatile void *)lowTable, 0);
    lowTable += 2;
    lowerY = OSReadBigInt32((volatile void *)lowTable, 0);
    lowTable += 2;
    upperX = OSReadBigInt32((volatile void *)highTable, 0);
    highTable += 2;
    upperY = OSReadBigInt32((volatile void *)highTable, 0);
    highTable += 2;

    do {
        // consume next point from first X
        lower = (lowPoints && (!highPoints || (lowerX <= upperX)));

        if( lower) {
            /* highline */
            x2 = upperX;
            y2 = upperY;
            x3 = lowerX;
            y3 = lowerY;
            if( lowPoints && (--lowPoints)) {
                lowerX = OSReadBigInt32((volatile void *)lowTable, 0);
                lowTable += 2;
                lowerY = OSReadBigInt32((volatile void *)lowTable, 0);
                lowTable += 2;
            }
        } else  {
            /* lowline */
            x2 = lowerX;
            y2 = lowerY;
            x3 = upperX;
            y3 = upperY;
            if( highPoints && (--highPoints)) {
                upperX = OSReadBigInt32((volatile void *)highTable, 0);
                highTable += 2;
                upperY = OSReadBigInt32((volatile void *)highTable, 0);
                highTable += 2;
            }
        }
        {
            // convert to line segment
            assert( segment < (segments + segCount) );

            scaledX2 = IOFixedMultiply( devScale, /* newX */ x3 );
            scaledY2 = IOFixedMultiply( crsrScale,
                                       /* newY */    Interpolate( x1, y1, x2, y2, x3, y3,
                                                                 scale, lower ) );
            if( lowPoints || highPoints)
                segment->devUnits = scaledX2;
            else
                segment->devUnits = MAX_DEVICE_THRESHOLD;

            segment->slope = ((scaledX2 == scaledX1)) ? 0 :
            IOFixedDivide((scaledY2 - scaledY1), (scaledX2 - scaledX1));

            segment->intercept = scaledY2
            - IOFixedMultiply( segment->slope, scaledX2 );
            /*        IOLog("devUnits = %08lx, slope = %08lx, intercept = %08lx\n",
             segment->devUnits, segment->slope, segment->intercept); */

            scaledX1 = scaledX2;
            scaledY1 = scaledY2;
            segment++;
        }

        // continue on from last point
        if( lowPoints && highPoints) {
            if( lowerX > upperX) {
                prevX1 = x1;
                prevY1 = y1;
            } else {
                /* swaplines */
                prevX1 = x1;
                prevY1 = y1;
                x1 = x3;
                y1 = y3;
            }
        } else {
            x2 = x1;
            y2 = y1;
            x1 = prevX1;
            y1 = prevY1;
            prevX1 = x2;
            prevY1 = y2;
        }

    } while( lowPoints || highPoints );

    if( *scaleSegCount && *scaleSegments)
        IODelete( *scaleSegments,
                 CursorDeviceSegment, *scaleSegCount );
    *scaleSegCount = segCount;
    *scaleSegments = (void *) segments;

    return true;
}

// -----------------------------------------------------------------------
// From IOHIDFamily-315.7.13/IOHIDSystem/IOHIPointing.cpp

// RY: This function contains the original portions of
// scalePointer.  This was separated out to accomidate
// the acceleration of other axes
void ScaleAxes (void * scaleSegments, int * axis1p, IOFixed *axis1Fractp, int * axis2p, IOFixed *axis2Fractp)
{
    SInt32			dx, dy;
    SInt32			absDx, absDy;
    SInt32			mag;
    IOFixed			scale;
    CursorDeviceSegment	*	segment;

    if( !scaleSegments)
        return;

    dx = (*axis1p) << 16;
    dy = (*axis2p) << 16;
    absDx = abs(dx);
    absDy = abs(dy);

    if( absDx > absDy)
        mag = (absDx + (absDy / 2));
    else
        mag = (absDy + (absDx / 2));

    if( !mag)
        return;

    // scale
    for(
        segment = (CursorDeviceSegment *) scaleSegments;
        mag > segment->devUnits;
        segment++)	{}

    scale = IOFixedDivide(
                          segment->intercept + IOFixedMultiply( mag, segment->slope ),
                          mag );


    dx = IOFixedMultiply( dx, scale );
    dy = IOFixedMultiply( dy, scale );

    // add fract parts
    dx += *axis1Fractp;
    dy += *axis2Fractp;

    *axis1p = dx / 65536;
    *axis2p = dy / 65536;

    // get fractional part with sign extend
    if( dx >= 0)
        *axis1Fractp = dx & 0xffff;
    else
        *axis1Fractp = dx | 0xffff0000;
    if( dy >= 0)
        *axis2Fractp = dy & 0xffff;
    else
        *axis2Fractp = dy | 0xffff0000;
}


// -----------------------------------------------------------------------
// Adapted from /System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Headers/FixMath.h

/*  The _IntSaturate macro converts a float to an int with saturation:

 If x <= -2**31, the result is 0x80000000.
 If -2**31 < x < 2**31, the result is x truncated to an integer.
 If 2**31 <= x, the result is 0x7fffffff.
 */
#if (defined (__i386__) || defined(__x86_64__)) && __GNUC__ && defined(__APPLE__) // NR: added __APPLE__

#define _IntSaturate(x) ((int) (x))
/*
 // Assume result will be x.
 int _Result = (x);
 __asm__("
 // Compare x to the floating-point limit.
 ucomisd %[LimitFloat], %[xx]    \n
 // If xx is too large, set _Result to the integer limit.
 cmovae  %[LimitInt], %[_Result]
 // _Result is input and output, in a general register.
 :   [_Result] "+r" (_Result)
 // LimitFloat is 0x1p31f and may be in memory or an XMM
 // register.
 :   [LimitFloat] "mx" (0x1p31f),
 // LimitInt is 0x7fffffff and may be in memory or a general
 // register.
 [LimitInt] "mr" (0x7fffffff),
 // xx is x and must be in an XMM register.
 [xx] "x" ((double)(x))
 // The condition code is changed.
 :   "cc"
 );
 // Return _Result.
 _Result;
 */

#elif defined __ppc__ || __ppc64__ || _MSC_VER // Visual Studio C++

#define _IntSaturate(x) ((int) (x))

#else

//#error "Unknown architecture." // NR: commented out
// To use unoptimized standard C code, remove above line.
#define _IntSaturate(x) ((x) <= -0x1p31f ? (int) -0x80000000 :		\
0x1p31f <= (x) ? (int) 0x7fffffff : (int) (x))

#endif



// -----------------------------------------------------------------------

extern "C" int
Wrapped_SetupAcceleration(void *data, uint32_t datasize,
                          int32_t inResolution, float desiredAcceleration,
                          void **scaleSegments, uint32_t *scaleSegCount) {
    IOFixed devScale  = IOFixedDivide(IntToFixed(inResolution), FRAME_RATE) ;
    IOFixed crsrScale = IOFixedDivide(SCREEN_RESOLUTION, FRAME_RATE) ;
    OSData *table = OSData::withBytesNoCopy(data, datasize) ;
    int ok = SetupAcceleration(table, FloatToFixed(desiredAcceleration), devScale, crsrScale, scaleSegments, scaleSegCount) ;
    if (ok) table->release() ;
    LOG("Wrapped_SetupAcceleration: OK: %d\n", ok);
    return ok ;
}

extern "C" void
Wrapped_ScaleAxes(void *scaleSegments,
                  int32_t *axis1p, int32_t *axis1Fractp,
                  int32_t *axis2p, int32_t *axis2Fractp) {
    ScaleAxes(scaleSegments, axis1p, axis1Fractp, axis2p, axis2Fractp) ;
}

// -----------------------------------------------------------------------

#define OSX_DEFAULT_SETTING 0.6875

OSXFunction::OSXFunction(std::string deviceType, float speed) {
    scaleSegments = 0 ;
    scaleSegCount = 0 ;

    clearState() ;
    loadTable(deviceType) ;
    configure(speed) ;
    LOG("OSXFunction, deviceType: %s, speed: %f\n", deviceType.c_str(), speed);
}

void
OSXFunction::loadTable(std::string nameOrPath) {
    // Generic mouse, OS X 10.6.0
    static const char *accl_afe940c03abcb5d03e6d4e1e4bca1470be2fe550 = "AACAAFVTQioABwAAAAAAAQABAAAAAQAAAAAgAAAQAABxOwAATOMABE7FAA03BAAFRAAAFIAAAAcsAAAj4AAACQAAADSwAAAK2AAARfAAAA0IAABXkAAAD2AAAGkAAAASEAAAeoAAABUAAACJAAAAF8AAAJEAAAAawAAAlrAAAB2QAACZsAAAIKAAAJswAAAj8AAAnDAAACewAACcMAAAAIAAABIAAHE7AABWfwAESgAADqAAAAY6AAAfQAAABygAACkAAAAI2AAAPGAAAAm4AABHQAAACrAAAFMwAAALwAAAYDAAAAzAAABsIAAADuAAAIQgAAARYAAAnSAAABQAAAC0AAAAFsAAAMcAAAAZoAAA1AAAABzgAADbAAAAIIAAAOAAAAAkQAAA4wAAACegAADjAAAAALAAABQAAHE7AABhTgAESgAAD2AAAAUyAAAXYAAABjIAACCgAAAHLAAALCAAAAgIAAA3oAAACOQAAENAAAAJwAAAUIAAAAqgAABfIgAAC5AAAG1wAAAMcAAAewAAAA6AAACYoAAAEMAAALYAAAATQAAA0gAAABZgAADpAAAAGiAAAPoAAAAdoAABAwAAACEgAAEHAAAAJIAAAQoAAAAnoAABDAAAAADgAAARAABxOwAAbXcABBoAABHwAAAFGgAAG/AAAAXwAAAmYAAABvwAADQAAAAITAAAT+AAAAlsAABt4AAACngAAI3AAAALsAAAtkAAAA1QAADZgAAAEQAAAPeAAAAVwAABEQAAABlgAAEgAAAAHUAAASgAAAAhAAABLgAAACSAAAEyAAAAJ4AAATUAAAAAUAAAEgAAcTsAAEuwAARMAAAOAAAABUAAABVQAAAHJAAAJiAAAAi0AAA1wAAACpAAAEmAAAAL6AAAVoAAAA0gAABiAAAADhgAAGrQAAAPGAAAdAAAABGQAACHgAAAFFAAAJoAAAAXYAAAqYAAABpgAAC0AAAAHVAAALkAAAAg0AAAvIAAACQgAAC9gAAAJ7AAAL6AAAABAAAAEAAAcTsAAFZ/AAO4AAASoAAABSAAACVAAAAGCAAAN4AAAAbwAABfAAAAB/AAAIoAAAAJKAAAyyAAAArwAAD3gAAADSAAARyAAAAQAAABOAAAABRAAAFKAAAAGQAAAVMAAAAc0AABVwAAACDgAAFbgAAAJCAAAV2AAAAnoAABXgAAAFJwAAAJlNEAWTAAAAoSaQBf8AAACpAAAGawAAAA4AAAHAABGFUAATAAAAGyKAAC8AAAAlNpAAagAAADb0oAENAAAAOteAAUWAAAA+ulABfgAAAEKdMAG2gAAARoAAAe8AAABKIBACKYAAAE2VYAJiAAAAUUqwApaAAABVAAACywAAAFgAEAMcgAAAW1VgA2QAAABeqrADq4AAAGIAAAPzAAAAZiAABD3AAABp6rAEh4AAAG21YATRQAAAcYAABRsAAAB3oBAFbcAAAH2VYAW/gAAAg4qwBhFAAACJgAAGYwAAAJFgEAbAAAAAmRVgBx0AAACgyrAHegAAAKiAAAfXAAAAEAAAATAAEYVQABMAAAAbIoAAMQAAACU2kABxAAAAMvSgARgAAAA6z7AByIAAAEOqsAKOAAAASBVgAwiAAABMgAADgwAAAFDVYAQJgAAAVQAABI8AAABcarAFKwAAAGOAAAXHAAAAbxVgBnwAAAB0yrAG1YAAAHqAAAcvAAAAhMAAB5BAAACPAAAH8YAAAJlAAAhSwAAAo4AACLQAA=" ;

    // Multitouch, OS X 10.6.0
    static const char *accl_6cae1281d58cf4db979ee8e0be48e55200a933d8 = "AACAAFVTQioABwAAAAAAAgAEAAAABAAAABAAAAAQAAAAACAAAA0AAIAAAACAAAABQAAAAYAAAAIAAAAC4AAAAwAAAATgAAAEAAAAB0AAAAUAAAAKAAAABgAAAA1AAAAIAAAAFgAAAArAAAAjAAAADQAAAC8AAAAOwAAAOMAAABBAAABBAAAAEcAAAEjAAAAAUAAADwAAgAAAAIAAAAEAAAABQAAAAYAAAAJAAAACAAAAA4AAAAKAAAAE4AAAAwAAAAZgAAAEAAAACgAAAAUAAAAOQAAABgAAABNAAAAIAAAAHsAAAArAAAAuwAAADQAAADyAAAAOwAAARwAAABBAAABPwAAAEcAAAFiAAAAAgAAADwAAgAAAAIAAAAEAAAABYAAAAYAAAAKgAAACAAAABEAAAAKAAAAGAAAAAwAAAAgAAAAEAAAADQAAAAUAAAASwAAABgAAABkAAAAIAAAAKAAAAArAAAA7wAAADQAAAEuAAAAOwAAAV0AAABBAAABgQAAAEcAAAGkAAAAAsAAADwAAgAAAAIAAAAEAAAABoAAAAYAAAAMAAAACAAAABQAAAAKAAAAHQAAAAwAAAAnAAAAEAAAAEEAAAAUAAAAXgAAABgAAAB/AAAAIAAAAMgAAAArAAABKAAAADQAAAFyAAAAOwAAAaQAAABBAAABywAAAEcAAAHrAAAAA4AAADwAAgAAAAKAAAAEAAAABwAAAAYAAAANgAAACAAAABeAAAAKAAAAIoAAAAwAAAAvAAAAEAAAAE8AAAAUAAAAdQAAABgAAACfAAAAIAAAAPcAAAArAAABZAAAADQAAAG3AAAAOwAAAe0AAABBAAACFQAAAEcAAAIxAAAABAAAADwAAgAAAAMAAAAEAAAACAAAAAYAAAAPgAAACAAAABsAAAAKAAAAKQAAAAwAAAA5gAAAEAAAAGMAAAAUAAAAkwAAABgAAADLAAAAIAAAATUAAAArAAABugAAADQAAAIMAAAAOwAAAj0AAABBAAACXAAAAEcAAAJxAAA==" ;

    static const char *accl_cc3ffdf944e6aeb717d6c93b47f8fc44cf659119 = "AACAAEAyMDAAAgAAAAAAAQABAAAAAQAAAAEAAAAJAABxOwAAYAAABE7FABCAAAAMAAAAXwAAABbsTwCLAAAAHTsUAJSAAAAidicAlgAAACRidgCWAAAAJgAAAJYAAAAoAAAAlgAA" ;

    if (nameOrPath.empty() || nameOrPath=="mouse") {
        accltable = Base64::decode(accl_afe940c03abcb5d03e6d4e1e4bca1470be2fe550) ;
        // std::cerr << "Using builtin mouse acceleration table" << std::endl ;
    } else if (nameOrPath=="touchpad") {
        accltable = Base64::decode(accl_6cae1281d58cf4db979ee8e0be48e55200a933d8) ;
        // std::cerr << "Using builtin touchpad acceleration table" << std::endl ;
    } else if (nameOrPath=="IOHIPointing") {
        accltable = Base64::decode(accl_cc3ffdf944e6aeb717d6c93b47f8fc44cf659119) ;
        // std::cerr << "Using hard-coded IOHIPointing acceleration table" << std::endl ;
    } else {
        LOG("invalid nameOrPath: %s\n", nameOrPath.c_str());
        exit(0);
    }
}

void
OSXFunction::clearState(void) {
    fractX = fractY = 0 ;
}

void
OSXFunction::configure(float s) {
    if (Wrapped_SetupAcceleration((void*)accltable.c_str(), (uint32_t)accltable.size(),
                                  400 /*dpi, TODO*/, s,
                                  &scaleSegments, &scaleSegCount)) {
        setting = s ;
        clearState() ;
    } else
        configure(OSX_DEFAULT_SETTING) ;
}

void
OSXFunction::apply(int dxMickey, int dyMickey, int *dxPixel, int *dyPixel) {
    Wrapped_ScaleAxes(scaleSegments, &dxMickey, &fractX, &dyMickey, &fractY) ;
    // std::cerr << "OSXFunction::apply: " << dxMickey << " " << dyMickey << std::endl ;
    
#if 0
    int num=1, div=1 ;
    *dxPixel = (num * dxMickey) / div ;
    *dyPixel = (num * dyMickey) / div ;
#else
    *dxPixel = dxMickey ;
    *dyPixel = dyMickey ;
#endif
}
