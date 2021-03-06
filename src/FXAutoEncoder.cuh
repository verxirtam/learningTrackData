#pragma once

#include "nn/AutoEncoder.cuh"
#include "nn/Func1to1Tanh.cuh"

#include "FXAutoEncoderDBAccessor.cuh"
#include "util/TimeUtil.h"

#include "DBAccessor.h"

class FXAutoEncoder
{
private:
	//オートエンコーダの型
	using AutoEncoderType = nn::AutoEncoder<nn::Func1to1Tanh>;
	//オートエンコーダ
	AutoEncoderType autoEncoder;
	//DBファイル名
	std::string dbFileName;
	//DBアクセサ
	DBAccessor dbAccessorLearning;
	FXAutoEncoderDBAccessor dbAccessor;
	//訓練用データの開始時刻
	time_t trainingTimeBegin;
	//訓練用データの終了時刻
	time_t trainingTimeEnd;
	//テスト用データの開始時刻
	time_t testTimeBegin;
	//テスト用データの終了時刻
	time_t testTimeEnd;
	//1データの長さ(過去何分のデータを使用するか)
	unsigned int timeLength;
	//学習用のクエリのキャッシュ
	std::vector<float> learningQueryCache;
	//正規化用の情報を取得する
	void getNormarizeInput(cuda::DeviceMatrix& normarize_input);
	//学習用のクエリから指定したレコード数分情報取得する
	bool selectRecord(unsigned int record_count, std::vector<float>& output);
public:
	FXAutoEncoder():
		autoEncoder(),
		dbFileName(),
		dbAccessorLearning(),
		dbAccessor(),
		timeLength(10),
		learningQueryCache()
	{
	}
	void init(const std::string& db_file_name, unsigned int time_length, unsigned int layer_size, unsigned int minibatch_size);
	const AutoEncoderType& getAutoEncoder()
	{
		return autoEncoder;
	}
	bool learning();
	cuda::DeviceMatrix getAllInput()
	{
		std::vector<float> result_vector;
		while(selectRecord(1000, result_vector))
		{
		}
		unsigned int r = timeLength;
		unsigned int c = result_vector.size() / timeLength;
		cuda::DeviceMatrix result(r, c, result_vector);
		return result;
	}
};

