#ifndef WindowsFunction_h
#define WindowsFunction_h

class WindowsFunction {
    
private:
    
    bool windowsXP;
    bool windowsVista;
    bool windows7;
    bool enhancePointerPrecision;
    bool _gbNewMouseAccel;
    bool disableSubPixelation;
    int previousSegmentIndex;  // used for interpolation
    int FINDSEGMENT; // used for interpolation
    int previousMouseRawX;
    int previousMouseRawY;
    float previousMouseXRemainder;
    float previousMouseYRemainder;
    int screenResolution; // DPI
    int screenRefreshRate; // DPI
    float mouseSensitivity; // From registry HKEY_CURRENT_USER\Control Panel\Mouse\MouseSensitivity
    float pixelGain;
    
protected:
    
    float SmoothMouseGain(float deviceSpeed, int& segment);
    
public:

    int slider ; // temp :)

    /**
     The slider argument in the uri defines the mouse sensitivity.
     The sentitivity is controlled in the Windows mouse control panel by a slider with 11 tick positions.
     By default the slider position is at tick number 6. This corresponds to
     0 for the slider argument. A value of 3 for i.e. corresponds to moving the slider
     3 ticks right of the default position. A value of -3 corresponds to moving the
     slider 3 ticks left of the default slider position.
     -5 <= slider <= 5
     */
    WindowsFunction(int slider);
    
    void clearState(void) ;
    
    void apply(int dxMickey, int dyMickey, int *dxPixel, int *dyPixel) ;
    
    ~WindowsFunction() {}
    
} ; 

#endif
