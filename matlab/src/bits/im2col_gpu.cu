/** @file im2col.cu
 ** @brief Image to columns and back (GPU)
 ** @author Andrea Vedaldi
 **/

#include "im2col.cpp"
#include "gpu.hpp"

/* ---------------------------------------------------------------- */
/*                                                     im2col (GPU) */
/* ---------------------------------------------------------------- */

template <typename Dtype>
__global__ void
im2col_gpu_kernel(const int n, const Dtype* data_im,
                  const int height, const int width,
                  const int kheight, const int kwidth,
                  const int stride, const int pad,
                  const int height_col, const int width_col, Dtype* data_col)
{
  /* each kernel copies the pixels in an image patch for one channel */
  int index = threadIdx.x + blockIdx.x * blockDim.x ;
  if (index < n) {
    int x_out = index % width_col;
    index /= width_col;
    int y_out = index % height_col;
    int channel_in = index / height_col;
    int channel_out = channel_in * kheight * kwidth ;
    int y_in = y_out * stride - pad;
    int x_in = x_out * stride - pad;

    data_col += (channel_out * height_col + y_out) * width_col + x_out;
    data_im += (channel_in * height + y_in) * width + x_in;

    for (int i = 0; i < kheight ; ++i) {
      for (int j = 0; j < kwidth ; ++j) {
        if (y_in + i >= 0 &&
            y_in + i < height &&
            x_in + j >= 0 &&
            x_in + j < width) {
          *data_col = data_im[i * width + j];
        } else {
          *data_col = 0;
        }
        data_col += height_col * width_col;
      }
    }
  }
}

template <typename Dtype>
void im2col_gpu(const Dtype* data_im, const int channels,
                const int height, const int width,
                const int kheight, const int kwidth,
                const int stride, const int pad,
                Dtype* data_col)
{
  // We are going to launch channels * height_col * width_col kernels, each
  // kernel responsible for copying a single-channel grid.
  int height_col = (height + 2 * pad - kheight) / stride + 1;
  int width_col = (width + 2 * pad - kwidth) / stride + 1;
  int num_kernels = channels * height_col * width_col;

  im2col_gpu_kernel<Dtype> <<<CAFFE_GET_BLOCKS(num_kernels), CAFFE_CUDA_NUM_THREADS>>>
  (num_kernels, data_im,
   height, width,
   kheight, kwidth,
   stride, pad,
   height_col, width_col, data_col) ;

  if (cudaPeekAtLastError() != cudaSuccess) {
    std::cout
    <<"im2col: CUDA kernel error ("
    <<cudaGetErrorString(cudaPeekAtLastError())
    <<")"<<std::endl ;
  }
}

// Explicit instantiation
template void im2col_gpu<float>(const float* data_im, const int channels,
                                const int height, const int width,
                                const int kheight, const int kwidth,
                                const int stride, const int pad,
                                float* data_col);

template void im2col_gpu<double>(const double* data_im, const int channels,
                                 const int height, const int width,
                                 const int kheight, const int kwidth,
                                 const int stride, const int pad,
                                 double* data_col);

/* ---------------------------------------------------------------- */
/*                                                     col2im (GPU) */
/* ---------------------------------------------------------------- */

template <typename Dtype>
__global__ void col2im_gpu_kernel(const int n, const Dtype* data_col,
                                  const int height, const int width,
                                  const int channels,
                                  const int kheight, const int kwidth,
                                  const int stride, const int pad,
                                  const int height_col, const int width_col,
                                  Dtype* data_im)
{
  int index = threadIdx.x + blockIdx.x * blockDim.x;

  if (index < n)
  {
    Dtype val = 0;
    /*
     Each kernel computes one pixel of the output image. This is obtained
     by summing all the values in the columnised data that were generated as copies of
     that particular pixel.
     */

    /*
     recover the (x,y,c) coordinate of the input pixel based on the kernel
     index, using the fact that index = x + width * y + width*height * c.
     */
    int x = (index % width) ;
    int y = ((index / width) % height) ;
    int c = index / (width * height) ;

    /*
     Let xc be the top left coordinate of the patch(xc,yc) packed at location
     (xc,yc) in the columnised data. patch(xc,yc) includes all input image
     pixels in the interval:

     x1 <= x <= x2,   x1(xc) = stride * xc - pad,   x2(xc) = x1(xc) + kwidth - 1,
     y1 <= y <= y2,   y1(yc) = stride * yc - pad,   y2(yc) = y1(yc) + kheight - 1.

     Hence pixel (x,y) is integrated in patch(xc,yc) if, and only if,

     (x + pad - kwidth + 1) / stride <= xc <= (x + pad) / stride.

     Here to find the minimum and maximum value of xc we need to take the ceil
     of the left-hand side and the floor of the right hand side. With C integer
     math:

     xc1 <= xc <= xc2,  xc1 = (x + pad - kwidth + 1 + stride - 1)/stride
                            = (x + pad - kwidth)/stride + 1,
     xc2 = (x + pad) / stride

     Some care must be given to the first expression for xc1 as this works
     only if the numerator is non-negative (division is otherwise
     undefined C89 or truncated upwards C99).

     Within a patch(xc,yc), pixel (x,y) has relative coordinates
     (dx,dy) given by

     dx = x - (xc * stride - pad),  dy = y - (yc * stride - pad).

     This result in an additional patch-relative offset of

     doffset(dx,dy,c)
        = (x + pad - xc*stride)
          + (y + pad - yc*stride)*kwidth
          + c*kwidth*kheight
        = (x + pad)
          + (y+pad)*kwidth + c*(kwidth*kheight)
          - xc*stride - yc*stride*kwidth.

     Thus pixel (x,y) in patch(xc,yc) should be read in the columnised
     output with a total offset of

     offset(x,y,xc,yc,c)
        = xc + yc * widht_col + doffset(dx,dy,c) * width_col*height_col
        = ((x+pad) + (y+pad)*kwidth + c*(kwidth*kheight)) * width_col*height_col
          + xc * (1 - stride * width_col*height_col)
          + yc * (1 - stride * kwidth*height_col) * width_col.
     */
    int xc1 = (x + pad - kwidth >= 0) ? (x + pad - kwidth) / stride + 1 : 0 ;
    int yc1 = (y + pad - kheight >= 0) ? (y + pad - kheight) / stride + 1 : 0 ;
    int xc2 = min((x + pad) / stride, width_col - 1) ;
    int yc2 = min((y + pad) / stride, height_col - 1) ;
    int offset = (c * kwidth * kheight + (y+pad) * kwidth + (x+pad)) * height_col * width_col;
    int deltax = (1 - stride * height_col * width_col);
    int deltay = (1 - stride * kwidth * height_col) * width_col;

    for (int yc = yc1 ; yc <= yc2 ; ++ yc) {
      for (int xc = xc1 ; xc <= xc2 ; ++ xc) {
        val += data_col[offset + yc * deltay + xc * deltax];
      }
    }
    data_im[index] = val;
  }
}

template <typename Dtype>
void col2im_gpu(const Dtype* data_col, const int channels,
                const int height, const int width,
                const int kheight, const int kwidth,
                const int stride, const int pad,
                Dtype* data_im)
{
  int height_col = (height + 2 * pad - kheight) / stride + 1;
  int width_col = (width + 2 * pad - kwidth) / stride + 1;
  int num_kernels = channels * height * width;
  col2im_gpu_kernel<Dtype> <<<CAFFE_GET_BLOCKS(num_kernels), CAFFE_CUDA_NUM_THREADS>>>
  (num_kernels, data_col,
   height, width, channels,
   kheight, kwidth,
   stride, pad,
   height_col, width_col, data_im);

  if (cudaPeekAtLastError() != cudaSuccess) {
    std::cout
    <<"col2im: CUDA kernel error ("
    <<cudaGetErrorString(cudaPeekAtLastError())
    <<")"<<std::endl ;
  }
}

template void col2im_gpu<float>(const float* data_col, const int channels,
                                const int height, const int width,
                                const int kheight, const int kwidth,
                                const int stride, const int pad,
                                float* data_im);

template void col2im_gpu<double>(const double* data_col, const int channels,
                                 const int height, const int width,
                                 const int kheight, const int kwidth,
                                 const int stride, const int pad,
                                 double* data_im);
