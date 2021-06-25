# Campp
<div align=center><img width="150" height="150" src="https://github.com/Cheelem/Campp/raw/master/image/Campp-Logo.png"/></div>

An iOS camera app for capturing RAW images and generate HDR image with multiple RAW exposures (based on the HDR-plus algorithm).

## Functionalities

- Basic camera control (exposure duration, ISO, white balance, etc).
- RAW image capture.
- Built-in HDR+ processor (with burst exposure and NLM denoising).
- Real-time histogram viewer.

## Implementation Details

### HDR+

The HDR plus core is implemented in Halide and compiled as a static library in the app.

### Invoke C++ Code in Swift

We wrapped the C++ module with several C functions and bridge the C functions with Swift application with Objective-C header.

<div align=center><img width="496" height="193" src="https://github.com/Cheelem/Campp/raw/master/image/Objective-C-Bridging.png"/></div>

### Real-time Histogram

Histogram viewer is implemented using the library GPUImage, which takes preview images into a GPU pipeline then calculate and render the histgram.

## License
[MIT](https://github.com/Cheelem/Campp/blob/master/README.md)
