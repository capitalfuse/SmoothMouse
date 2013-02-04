/*
 LICENSE
 Libpointing can be redistributed and/or modified under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

 Ad-hoc licences can be provided upon request.

 We appreciate credit when you use it (cite the following paper), but don't require it:

 G. Casiez and N. Roussel. No more bricolage! Methods and tools to characterize, replicate and compare pointing transfer functions. In Proceedings of UIST'11, the 24th ACM Symposium on User Interface Software and Technology, pages 603-614, October 2011. ACM.
 */

#include "WindowsFunction.hpp"

#include <iostream>
#include <sstream>
#include <cmath>

#define Sign(X) ((X>0)?(1):(-1))

#ifndef min
#define min(a,b) ((a) < (b) ? (a) : (b))
#endif

#ifndef max
#define max(a,b) ((a) > (b) ? (a) : (b))
#endif

#ifndef abs
#define abs(_a)	((_a >= 0) ? _a : -_a)
#endif

#define WINDOWS_DEFAULT_SLIDER 0
#define WINDOWS_DEFAULT_NOSUBPIX false
#define WINDOWS_DEFAULT_ENHANCE true
#define WINDOWS_USE_DEFAULT_CONSTANTS 1

WindowsFunction::WindowsFunction(int slider) {
    
    windowsXP = false ;
    windowsVista = false ;
    windows7 = true ;
    disableSubPixelation = WINDOWS_DEFAULT_NOSUBPIX ;
    enhancePointerPrecision = WINDOWS_DEFAULT_ENHANCE ;
    
    /*    windowsXP = uri.opaque=="xp" ;
     windowsVista = uri.opaque=="vista" ;
     windows7 = uri.opaque=="7" ;
     if (!windowsXP && !windowsVista && !windows7) windows7 = true ;
     
     slider = WINDOWS_DEFAULT_SLIDER ;
     URI::getQueryArg(uri.query, "slider", &slider) ;
     URI::getQueryArg(uri.query, "nosubpix", &disableSubPixelation) ;
     URI::getQueryArg(uri.query, "enhancePointerPrecision", &enhancePointerPrecision) ;
     URI::getQueryArg(uri.query, "epp", &enhancePointerPrecision) ;
     */
    
    windowsXP = 0;
    windowsVista = 0;
    windows7 = 1;
    this->slider = slider;
    disableSubPixelation = false;
    enhancePointerPrecision = true;
    
    if (slider == -5)
        mouseSensitivity = 1;
    else
        mouseSensitivity = 10 + slider * 2;
    
    _gbNewMouseAccel = true;
    previousSegmentIndex = 0;
    FINDSEGMENT = -1;
    previousMouseRawX = 0;
    previousMouseRawY = 0;
    previousMouseXRemainder = 0.0;
    previousMouseYRemainder = 0.0;
    pixelGain = 0.0;
}

float WindowsFunction::SmoothMouseGain(float deviceSpeed, int& segment)
{
    /*
     values of threshold that give the pointer speed in inches/s from
     the speed of the device in inches/s intermediate values are
     interpolated
     http://www.microsoft.com/whdc/archive/pointer-bal.mspx
     
     [HKEY_CURRENT_USER\Control Panel\Mouse]
     "SmoothMouseXCurve"=hex:00,00,00,00,00,00,00,00,	\
     15,6e,00,00,00,00,00,00,				\
     00,40,01,00,00,00,00,00,				\
     29,dc,03,00,00,00,00,00,				\
     00,00,28,00,00,00,00,00
     "SmoothMouseYCurve"=hex:00,00,00,00,00,00,00,00,	\
     b8,5e,01,00,00,00,00,00,				\
     cd,4c,05,00,00,00,00,00,				\
     cd,4c,18,00,00,00,00,00,				\
     00,00,38,02,00,00,00,00
     */
    
    if (deviceSpeed == 0.0) {
        segment = 0;
        return deviceSpeed;
    }
    
    float smoothX[5] = {0.0, 0.43, 1.25,  3.86,  40.0};
    float smoothY[5] = {0.0, 1.37, 5.30, 24.30, 568.0};
    
    int i;
    if (segment == FINDSEGMENT) {
        for (i=0; i<3; i++) {
            if (deviceSpeed < smoothX[i+1])
                break;
        }
        segment = i;
    } else {
        i = segment;
    }
    
    float slope = (smoothY[i+1] - smoothY[i]) / (smoothX[i+1] - smoothX[i]);
    float intercept = smoothY[i] - slope * smoothX[i];
    return slope + intercept/deviceSpeed;
}

void
WindowsFunction::clearState(void) {
    previousSegmentIndex = 0;
    FINDSEGMENT = -1;
    previousMouseRawX = 0;
    previousMouseRawY = 0;
    previousMouseXRemainder = 0.0;
    previousMouseYRemainder = 0.0;
    pixelGain = 0.0;
}

void
WindowsFunction::apply(int mouseRawX, int mouseRawY, int *mouseX, int *mouseY) {
    if (enhancePointerPrecision) {
        // Handle remainders same as XP
        if (windowsXP) {
            if (Sign(mouseRawX) != Sign(previousMouseRawX) || mouseRawX == 0)
                previousMouseXRemainder = 0.0;
            previousMouseRawX = mouseRawX;
            if (Sign(mouseRawY) != Sign(previousMouseRawY) || mouseRawY == 0)
                previousMouseYRemainder = 0.0;
            previousMouseRawY = mouseRawY;
        }
        
        // Handle remainders same as Vista
        if (windowsVista) {
            if (mouseRawX != 0) {
                if (Sign(mouseRawX) != Sign(previousMouseRawX))
                    previousMouseXRemainder = 0.0;
                previousMouseRawX = mouseRawX ;
            }
            if (mouseRawY != 0) {
                if (Sign(mouseRawY) != Sign(previousMouseRawY))
                    previousMouseYRemainder = 0.0;
                previousMouseRawY = mouseRawY;
            }
        }
        
        // (Windows 7 does not clear remainders)
#ifdef WINDOWS_USE_DEFAULT_CONSTANTS
        float resolution = 96.0;
        float refreshRate = 60.0;
#else
        float resolution = max((double)screenResolution, 96.0);
        float refreshRate = max((double)screenRefreshRate, 60.0);
#endif
        float screenResolutionFactor;
        if (windows7 && _gbNewMouseAccel) {
            screenResolutionFactor = resolution / 150.0;
        } else {
            screenResolutionFactor = refreshRate / resolution;
        }
        
        // Calculate accelerated mouse deltas
        float mouseMag = max(abs(mouseRawX), abs(mouseRawY))
        + min(abs(mouseRawX), abs(mouseRawY)) / 2.0;
        int currentSegmentIndex;
        pixelGain =
        screenResolutionFactor
        * (mouseSensitivity / 10.0)
        * SmoothMouseGain(mouseMag / 3.5, currentSegmentIndex = FINDSEGMENT)
        / 3.5;
        
        if (currentSegmentIndex > previousSegmentIndex) {
            // Average with calculation using previous curve segment
            float pixelGainUsingPreviousSegment =
            screenResolutionFactor
            * (mouseSensitivity / 10.0)
            * SmoothMouseGain(mouseMag / 3.5, previousSegmentIndex)
            / 3.5;
            pixelGain = (pixelGain + pixelGainUsingPreviousSegment) / 2.0;
        }
        previousSegmentIndex = currentSegmentIndex;
        
        // Calculate accelerated mouse deltas
        float mouseXplusRemainder = mouseRawX * pixelGain + previousMouseXRemainder;
        float mouseYplusRemainder = mouseRawY * pixelGain + previousMouseYRemainder;
        
        // Split mouse delta into integer part (applied now) and remainder part (saved for next time)
        // (NOTE: Only when disableSubPixelation==true does this have any significant or cumulative effect)
        
        if (windows7) {
            // Windows 7
            if (mouseXplusRemainder >= 0) {
                *mouseX = (int)floor(mouseXplusRemainder);
            } else {
                *mouseX = -(int)floor(-mouseXplusRemainder);
            }
            previousMouseXRemainder = mouseXplusRemainder - *mouseX;
        } else if (disableSubPixelation && fabs(mouseXplusRemainder) <= abs(mouseRawX)) {
            // XP & Vista when disableSubPixelation (never set, AFAIK)
            *mouseX = mouseRawX;
            previousMouseXRemainder = 0.0;
            pixelGain = 1.0;
        } else {
            // XP & Vista
            *mouseX = (int)floor(mouseXplusRemainder);
            previousMouseXRemainder = mouseXplusRemainder - *mouseX;
        }
        
        if (windows7) {
            // Windows 7
            if (mouseYplusRemainder >= 0) {
                *mouseY = (int)floor(mouseYplusRemainder);
            } else {
                *mouseY = -(int)floor(-mouseYplusRemainder);
            }
            previousMouseYRemainder = mouseYplusRemainder - *mouseY;
        } else if (disableSubPixelation && fabs(mouseYplusRemainder) <= abs(mouseRawY)) {
            // XP & Vista when disableSubPixelation (never set, AFAIK)
            *mouseY = mouseRawY;
            previousMouseYRemainder = 0.0;
            pixelGain = 1.0;
        } else {
            // XP & Vista
            *mouseY = (int)floor(mouseYplusRemainder);
            previousMouseYRemainder = mouseYplusRemainder - *mouseY;
        }
    } else {
        if (mouseSensitivity == 10) { // Slider = 0, no remainder to handle
            *mouseX = mouseRawX;
            *mouseY = mouseRawY;
        }
        else {
            float pixelGain[11] = {0.03125, 0.0625, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5};
            
            // Calculate accelerated mouse deltas
            float mouseXplusRemainder = mouseRawX * pixelGain[slider+5] + previousMouseXRemainder;
            float mouseYplusRemainder = mouseRawY * pixelGain[slider+5] + previousMouseYRemainder;
            
            if (mouseXplusRemainder >= 0) {
                *mouseX = (int)floor(mouseXplusRemainder);
            } else {
                *mouseX = -(int)floor(-mouseXplusRemainder);
            }
            previousMouseXRemainder = mouseXplusRemainder - *mouseX;
            
            if (mouseYplusRemainder >= 0) {
                *mouseY = (int)floor(mouseYplusRemainder);
            } else {
                *mouseY = -(int)floor(-mouseYplusRemainder);
            }
            previousMouseYRemainder = mouseYplusRemainder - *mouseY;
            
        }
    }
}

