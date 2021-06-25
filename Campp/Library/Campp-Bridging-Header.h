//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#include "HDRWrapper.h"

void* wrapped_hdr_init(int raw_width, int raw_height, int margin_top, int margin_left, int black_level, int white_level, float wb_r, float wb_g, float wb_b);
void wrapped_hdr_submit_raw_data(void* _this, uint16_t* image_data);
void wrapped_hdr_submit_depth_data(void* _this, float depth_data[], int depth_width, int depth_height);
uint8_t* wrapped_hdr_process(void* _this);
void wrapped_dispose_hdr_processor(void* _this);
