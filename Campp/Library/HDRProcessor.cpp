//
//  HDRWrapper.cpp
//  Campp
//
//  Created by Lingen Li on 2020/2/23.
//  Copyright © 2020 Apple. All rights reserved.
//

#include "HDRProcessor.hpp"

// embedded image saving
//#define STB_IMAGE_WRITE_IMPLEMENTATION
//#include "stb_image_write.h"
//#include <string>
//static bool save_png(std::string dir_path, std::string img_name, Halide::Runtime::Buffer<uint8_t> &img) {
//    std::string img_path = dir_path + "/" + img_name;
//    std::remove(img_path.c_str());
//    int stride_in_bytes = img.width() * img.channels();
//    LOG("SAVING PNG: img width=%d; height=%d; channels=%d; stride_in_bytes=%d", img.width(), img.height(), img.channels(), stride_in_bytes);
//    if (!stbi_write_png(img_path.c_str(), img.width(), img.height(), img.channels(), img.data(), stride_in_bytes)) {
//        LOG( "Unable to write output PNG image %s", img_path.c_str());
//        return false;
//    }
//    return true;
//}

// static util methods
void _copy_raw_to_buffer(Halide::Runtime::Buffer<uint16_t> &target_buffer, uint16_t* raw_image_data, int raw_width, int raw_height, int top_margin, int left_margin) {
    Halide::Runtime::Buffer<uint16_t> raw_buffer(raw_image_data, raw_width, raw_height);
    target_buffer.copy_from(raw_buffer.translated({-left_margin, -top_margin}));
}

// class method implementation
HDRProcessor::HDRProcessor(int raw_width, int raw_height, int margin_top, int margin_left, int black_level, int white_level, float wb_r, float wb_g, float wb_b) {
    _raw_width = raw_width;
    _raw_height = raw_height;
    _margin_top = margin_top;
    _margin_left = margin_left;
    _balck_level = black_level;
    _white_level = white_level;
    _image_width = 0;
    _image_height = 0;
    _raws_stack = new std::vector<uint16_t*>();
    _depth_data_stack = new std::vector<float*>();
    _wb_r = wb_r;
    _wb_g = wb_g;
    _wb_b = wb_b;
    // LOG("Initilized: raw_width: %d, raw_height: %d, bl: %d, wl: %d, margin_top: %d, margin_left: %d", _raw_width, _raw_height, _balck_level, _white_level, _margin_top, _margin_left);
}

HDRProcessor::~HDRProcessor() {
    delete static_cast<std::vector<uint16_t*>*>(_raws_stack);
    delete static_cast<std::vector<float*>*>(_depth_data_stack);
    delete static_cast<Halide::Runtime::Buffer<uint8_t>*>(_output_image);
}

int HDRProcessor::_get_width() {
    if (_image_width != 0) {
        return _image_width;
    }
    _image_width = _raw_width-(_margin_left*2);
    return _image_width;
}
int HDRProcessor::_get_height() {
    if (_image_height != 0) {
        return _image_height;
    }
    _image_height = _raw_height-(_margin_top*2);
    return _image_height;
}

void HDRProcessor::hdr_submit_raw_data(uint16_t* image_data) {
    if(_raw_width == 0 || _raw_height == 0) {
        // 数据未初始化
        LOG("Have not be intialized!");
        return;
    }
    static_cast<std::vector<uint16_t*>*>(_raws_stack)->push_back(image_data);
    LOG("RAW frame received. Current stack size = %lu.", static_cast<std::vector<uint16_t*>*>(_raws_stack)->size());
}

void HDRProcessor::hdr_submit_depth_data(float depth_data[], int width, int height) {
    LOG("Depth data readability test: [0]=%f, w=%d, h=%d.", depth_data[0], width, height);
    float* depth_data_pointer = (float*)malloc(width*height*sizeof(float));
    // 对Swift侧的数据拷贝后使用防止非法内存访问
    memcpy(depth_data_pointer, depth_data, width*height);
    _depth_data_width = width;
    _depth_data_height = height;
    static_cast<std::vector<float*>*>(_depth_data_stack)->push_back(depth_data_pointer);
//    _input_depth_data = new Halide::Runtime::Buffer<float>(width, height);
//    Halide::Runtime::Buffer<float> depth_buffer(depth_data, width, height);
//    _input_depth_data -> copy_from(depth_buffer);
//    delete[] copied_pointer;
    LOG("Depth data received: size=%d*%d.", width, height);
}

uint8_t* HDRProcessor::hdr_process() {
    Halide::Runtime::Buffer<uint16_t> input_images = _load_raws_stack_to_buffer(_raws_stack);
    Halide::Runtime::Buffer<float> depth_data;//(*static_cast<std::vector<float*>*>(_depth_data_stack))[0], _depth_data_width, _depth_data_height);
    // output Runtime Buffer: size of 3 channels (RGB), width and height.
    // _output_image 必须堆上创建，否则将导致swift侧访问无效的内存地址
    _output_image = new Halide::Runtime::Buffer<uint8_t>(3, _get_width(), _get_height());
    // execute pipeline
    clock_t start_time = clock();
    int err = hdr(input_images,
                  _balck_level, // black_level
                  _white_level, // white_level
                  _wb_r, // white_balance.r
                  _wb_g, // white_balance.g0
                  _wb_g, // white_balance.g1
                  _wb_b, // white_balance.b
                  3.7, // tone_mapping_compression
                  1.0, // tone_mapping_gain
                  3.0, // sharpen_strength
                  3, // nlm_search_area
                  3, // nlm_patch_size
                  80, // nlm_sigma
                  depth_data,
                  *_output_image // output_image
                  );
    clock_t end_time = clock();
    LOG("HDR Process result: %d. \n Time escaped: %ld ms", err, (end_time - start_time)/CLOCKS_PER_SEC);
    // transpose to account for interleaved layout
    _output_image->transpose(0, 1);
    _output_image->transpose(1, 2);
//    save_png(getenv("HOME"), "Documents/output.png", output_image);
    uint8_t* res_data = _output_image->data();
    return res_data;
}

Halide::Runtime::Buffer<uint16_t> HDRProcessor::_load_raws_stack_to_buffer(void* raw_stack){
    unsigned long raws_size = static_cast<std::vector<uint16_t*>*>(raw_stack)->size();
    Halide::Runtime::Buffer<uint16_t> result(_get_width(), _get_height(), raws_size);
    for (int i = 0; i < raws_size; ++i) {
        LOG("Converting Raw to Buffer (%d/%lu)", i+1, raws_size);
        auto resultSlice = result.sliced(2, i);
        _copy_raw_to_buffer(resultSlice, (*static_cast<std::vector<uint16_t*>*>(raw_stack))[i], _raw_width, _raw_height, _margin_top, _margin_left);
    }
    return result;
}

// 对 Swift 暴露的函数必须符合 C 规范
#ifdef __cplusplus
extern "C"{
#endif
void* wrapped_hdr_init(int raw_width, int raw_height, int margin_top, int margin_left, int black_level, int white_level, float wb_r, float wb_g, float wb_b) {
    return new HDRProcessor(raw_width, raw_height, margin_top, margin_left, black_level, white_level, wb_r, wb_g, wb_b);
}

void wrapped_hdr_submit_raw_data(void* _this, uint16_t* image_data){
    static_cast<HDRProcessor*>(_this)->hdr_submit_raw_data(image_data);
};

void wrapped_hdr_submit_depth_data(void* _this, float depth_data[], int depth_width, int depth_height) {
    static_cast<HDRProcessor*>(_this)->hdr_submit_depth_data(depth_data, depth_width, depth_height);
};

uint8_t* wrapped_hdr_process(void* _this){
    return static_cast<HDRProcessor*>(_this)->hdr_process();
}

void wrapped_dispose_hdr_processor(void* _this) {
    delete static_cast<HDRProcessor*>(_this);
}
#ifdef __cplusplus
}
#endif
