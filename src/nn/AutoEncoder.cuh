/*
 * =====================================================================================
 *
 *       Filename:  AutoEncoder.cuh
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2017年02月05日 19時19分44秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *   Organization:  
 *
 * =====================================================================================
 */

#pragma once

#include "Normalization.h"
#include "Backpropagation.cuh"
#include "OutputLayerRegression.cuh"

namespace nn
{

template <class AF>
class AutoEncoder
{
	//名前空間cudaを使用
	using DeviceMatrix = cuda::DeviceMatrix;
	using DeviceVector = cuda::DeviceVector;
private:
	Normalization normalization;
	const unsigned int layerCount;
	Backpropagation<AF, OutputLayerRegression> backpropagation;
	DeviceVector _1B;
public:
	AutoEncoder():
		normalization(),
		layerCount(3),
		backpropagation(layerCount),
		_1B()
	{
		
	}
	//normarize_input : 正規化するための入力(ランダムに抽出された複数データを想定)
	//layer_size : 中間層のレイヤのサイズ
	void init(const DeviceMatrix& normarize_input, unsigned int layer_size, unsigned int minibatch_size)
	{
		//normarize_inputを元に正規化を行う
		normalization.init(normarize_input);
		//BPの初期化を行う
		unsigned int n = normarize_input.getRowCount();
		backpropagation.init({n, layer_size, n}, minibatch_size);
		//ミニバッチの正規化に使用する1Vectorの初期化
		_1B = DeviceVector::get1Vector(minibatch_size);
	}
	//X : ミニバッチ
	DeviceMatrix forward(const DeviceMatrix& X)
	{
		//正規化されたミニバッチ
		DeviceMatrix nX = normalization.getPCAWhitening(X, _1B);
		
		DeviceMatrix nY;
		backpropagation.forward(nX, nY);
		
		return normalization.getInversePCAWhitening(nY, _1B);
	}
	DeviceMatrix learning(const DeviceMatrix& X)
	{
		//正規化されたミニバッチ
		DeviceMatrix nX = normalization.getPCAWhitening(X, _1B);
		
		DeviceMatrix nY;
		backpropagation.forward(nX, nY);
		backpropagation.back(nX);
		backpropagation.updateParameter();
		
		return normalization.getInversePCAWhitening(nY, _1B);
	}
	DeviceMatrix getWhiteningMatrix() const
	{
		return normalization.getPCAWhiteningMatrix();
	}
	DeviceMatrix getInverseWhiteningMatrix() const
	{
		return normalization.getInversePCAWhiteningMatrix();
	}
	void setEpsilon(float e)
	{
		this->backpropagation.setEpsilon(e);
	}
	float getEpsilon() const
	{
		return this->backpropagation.getEpsilon();
	}
	void setGamma(float g)
	{
		this->backpropagation.setGamma(g);
	}
	float getGamma() const
	{
		return this->backpropagation.getGamma();
	}
	const Backpropagation<AF, OutputLayerRegression>& getBackpropagation() const
	{
		return backpropagation;
	}
	const Normalization& getNormarization() const
	{
		return normalization;
	}
};

}

