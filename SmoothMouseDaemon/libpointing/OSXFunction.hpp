/* -*- mode: c++ -*-
 *
 * pointing-osx/transferfunctions/OSXFunction.h --
 *
 * Initial software
 * Authors: Nicolas Roussel, G�ry Casiez
 * Copyright � Inria
 *
 * http://libpointing.org/
 *
 * This software may be used and distributed according to the terms of
 * the GNU General Public License version 2 or any later version.
 *
 */

#pragma once

//#include <pointing/transferfunctions/TransferFunction.h>
//#include <pointing/utils/URI.h>

#include <string>
#include <stdint.h>

class OSXFunction {

    std::string accltable ;
    float setting ;
    int32_t fractX, fractY ;
    uint32_t scaleSegCount ;
    void *scaleSegments ;

    void loadTable(std::string nameOrPath) ;

public:

    float speed; // temp :)

    OSXFunction(std::string deviceType, float speed) ;

    void clearState(void) ;
    void configure(float setting) ;
    void apply(int dxMickey, int dyMickey, int *dxPixel, int *dyPixel) ;
} ;

