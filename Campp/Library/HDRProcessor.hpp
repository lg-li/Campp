//
//  HDRWrapper.h
//  Campp
//
//  Created by Lingen Li on 2020/2/22.
//  Copyright © 2020 Apple. All rights reserved.
//

#ifndef HDRProcessor_hpp
#define HDRProcessor_hpp

#include <stdio.h>
#include <string.h>

// 自定义数据结构类型
#ifndef _UINT16_T
#define _UINT16_T
typedef unsigned short uint16_t;
#endif /* _UINT16_T */

#ifndef _UINT8_T
#define _UINT8_T
typedef unsigned char uint8_t;
#endif /* _UINT8_T */

// LOG 开关
#ifndef DEBUG
#define DEBUG
#endif /* DEBUG */

// 启用 LOG 宏
#define __FILENAME__ (strrchr(__FILE__, '/') + 1) // 文件名
#ifdef DEBUG
#define LOG(format, ...) printf("[%s][%s][%d]: " format "\n", __FILENAME__, __FUNCTION__,\
                            __LINE__, ##__VA_ARGS__)
#else
#define LOG(format, ...)
#endif

#include "HDRCore.h"
#include "HalideBuffer.h"

class HDRProcessor {
public:
    HDRProcessor(int raw_width, int raw_height, int margin_top, int margin_left, int black_level, int white_level, float wb_r, float wb_g, float wb_b);
    ~HDRProcessor();
    void hdr_submit_raw_data(uint16_t* image_data);
    void hdr_submit_depth_data(float* depth_data, int width, int height);
    uint8_t* hdr_process();
    
private:
    int _raw_width = 0, _raw_height = 0, _margin_top = 0, _margin_left = 0, _balck_level = 0, _white_level = 0;
    int _image_width = 0, _image_height = 0, _depth_data_width = 0, _depth_data_height = 0;
    float _wb_r = 1.0, _wb_g = 1.0, _wb_b = 1.0;
    // 因此文件不可使用std库，使用 void* 定义非原型成员
    void* _raws_stack; // (vector<uint16_t*>)
    // 深度数据buffer
    void* _depth_data_stack; // (vector<float*>)
    // 输出图像buffer
    Halide::Runtime::Buffer<uint8_t>* _output_image;
    Halide::Runtime::Buffer<uint16_t> _load_raws_stack_to_buffer(void* raw_stack);
    int _get_width();
    int _get_height();
};

#endif /* HDRProcessor_hpp */
