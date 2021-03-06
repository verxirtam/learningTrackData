/*
 * =====================================================================================
 *
 *       Filename:  Statistics.h
 *
 *    Description:  DeviceMatrixに格納された、
 *                  サンプルが列ベクトル(縦ベクトル)になっているデータについての統計処理を行う
 *
 *        Version:  1.0
 *        Created:  2017年10月01日 05時37分02秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *   Organization:  
 *
 * =====================================================================================
 */
#pragma once

#include "../cuda/CuBlasFunction.h"


namespace nn
{

//平均と分散共分散行列を求める
void getMeanAndVarCovMatrix(const cuda::DeviceMatrix& sample, cuda::DeviceVector& mean, cuda::DeviceMatrix& varCovMatrix, cudaStream_t stream);


}




