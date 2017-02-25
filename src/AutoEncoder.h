/*
 * =====================================================================================
 *
 *       Filename:  AutoEncoder.h
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
#include "Backpropagation.h"

class AutoEncoder
{
private:
	Normalization normalization;
	const unsigned int layerCount;
	Backpropagation backpropagation;
public:
	AutoEncoder():
		normalization(),
		layerCount(3),
		backpropagation(layerCount)
	{
		
	}
	//normarize_input : 正規化するための入力(ランダムに抽出された複数データを想定)
	//layer_size : 中間層のレイヤのサイズ
	void init(const DeviceMatrix& normarize_input, unsigned int layer_size)
	{
		//normarize_inputを元に正規化を行う
		normalization.init(normarize_input);
		//BPの初期化を行う
		unsigned int n = normarize_input.getRowCount();
		backpropagation.init({n, layer_size, n});
	}
	//X : ミニバッチ
	DeviceMatrix learning(const DeviceMatrix& X)
	{
		//正規化されたミニバッチ
		DeviceVector nX = normalization.getPCAWhitening(X);
		
		DeviceMatrix Y;
		backpropagation.forward(nX, Y);
		backpropagation.back(nX);
		backpropagation.updateParameter();
		
		return Y;
	}
};