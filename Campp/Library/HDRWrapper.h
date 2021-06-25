//
//  HDRWrapper.h
//  Campp
//
//  Created by Lingen Li on 2020/2/24.
//  Copyright © 2020 Apple. All rights reserved.
//

#ifndef HDRWrapper_h
#define HDRWrapper_h

// 自定义数据结构类型
#ifndef _UINT16_T
#define _UINT16_T
typedef unsigned short uint16_t;
#endif /* _UINT16_T */

#ifndef _UINT8_T
#define _UINT8_T
typedef unsigned char uint8_t;
#endif /* _UINT8_T */

#ifdef __cplusplus
extern "C"{
#endif
void* wrapped_hdr_init(int raw_width, int raw_height, int margin_top, int margin_left, int black_level, int white_level, float wb_r, float wb_g, float wb_b);
void wrapped_hdr_submit_raw_data(void* _this, uint16_t* image_data);
void wrapped_hdr_submit_depth_data(void* _this, float depth_data[], int depth_width, int depth_height);
uint8_t* wrapped_hdr_process(void* _this);
void wrapped_dispose_hdr_processor(void* _this);
#ifdef __cplusplus
}
#endif

#endif /* HDRWrapper_h */
