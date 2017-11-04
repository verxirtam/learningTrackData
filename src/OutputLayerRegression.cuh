#pragma once

#include <vector>
#include <string>

#include "DeviceMatrix.h"

//回帰問題のための出力層の設定
class OutputLayerRegression
{
public:
	//活性化関数 = 恒等写像
	static void activateFunction(const DeviceMatrix& u, DeviceMatrix& z)
	{
		z = u;
	}
};

