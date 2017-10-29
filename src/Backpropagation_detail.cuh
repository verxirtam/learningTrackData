#pragma once

//Backpropagation.cuhのテンプレートクラスの実装

//////////////////////////////////////////////////////////////////////////////////////////////////
// cudaカーネルを含む関数
//////////////////////////////////////////////////////////////////////////////////////////////////

namespace
{
	template<class AF>
	__global__
	void obtainDeltaFromFdUWTDelta_kernel
		(
			unsigned int thread_index_offset,
			const float* const u_l,
			const float* const wtdelta_lp1,
			float* const delta_l
		)
	{
		//ブロックインデックス、スレッドインデックスの読み替え
		unsigned int s = threadIdx.x + blockIdx.x * blockDim.x + thread_index_offset;
		
		//このスレッドが計算すべき成分のインデックス
		unsigned int j = s;
		
		delta_l[j] = AF::applyDiff(u_l[j]) * wtdelta_lp1[j];
	}
	
	/*
	//dEdW[l] = delta[l] * (z[l])^T;
	template<unsigned int D>
	__global__
	void obtainDEDW_kernel
		(
			unsigned int data_index_offset,
			unsigned int row_count,
			const float* const delta_l,
			const float* const z_lm1,
			float* const dedw_l
		)
	{
		for(unsigned int d =0; d < D; d++)
		{
			//ブロックインデックス、スレッドインデックスの読み替え
			unsigned int s = threadIdx.x + d * blockDim.x + blockIdx.x * D * blockDim.x + data_index_offset;
			unsigned int i = s % row_count;
			unsigned int j = s / row_count;
			unsigned int k = s;
			
			//dEdW[l] = delta[l] * (z[l])^T;
			dedw_l[k] = delta_l[i] * z_lm1[j];
		}
	}
	*/
}

template<class AF>
void Backpropagation_Base<AF>::obtainZFromU(unsigned int l)
{
	
	//最後のレイヤ(l == layerCount - 2)の場合は恒等写像なので単にコピーする
	if(l == layerCount - 2)
	{
		z[l + 1] = u[l + 1];
		return;
	}
	
	ActivateFunction<AF>::activate(u[l + 1], z[l + 1]);
}


//delta[l] = f'(u[l]) ** WTdelta[l + 1];
template<class AF>
void Backpropagation_Base<AF>::obtainDeltaFromFdUWTDelta(unsigned int l)
{
	//1ブロックあたりのスレッド数の上限
	static unsigned int thread_count = CudaManager::getDeviceProp().maxThreadsPerBlock;
	
	//生成するスレッド数全体
	unsigned int thread_count_total = u[l].getRowCount() * u[l].getColumnCount();
	
	//スレッド数thread_countで実行するブロック数
	unsigned int block_count         = thread_count_total / thread_count;
	//スレッド数の残り
	unsigned int thread_count_remain = thread_count_total % thread_count;
	
	if(block_count * thread_count != 0)
	{
		//カーネル実行
		obtainDeltaFromFdUWTDelta_kernel<AF><<<block_count, thread_count>>>
			(
				0,
				u[l].getAddress(),
				WTdelta[l + 1].getAddress(),
				delta[l].getAddress()
			);
		//カーネル実行時のエラーチェック
		CUDA_CALL(cudaGetLastError());
	}
	if(thread_count_remain != 0)
	{
		//カーネル実行
		obtainDeltaFromFdUWTDelta_kernel<AF><<<1, thread_count_remain>>>
			(
				block_count * thread_count,
				u[l].getAddress(),
				WTdelta[l + 1].getAddress(),
				delta[l].getAddress()
			);
		//カーネル実行時のエラーチェック
		CUDA_CALL(cudaGetLastError());
	}
	//直後にdelta[l]を使用するので同期する
	CUDA_CALL(cudaStreamSynchronize(0));
}




//////////////////////////////////////////////////////////////////////////////////////////////////
// cudaカーネルを含まない関数
//////////////////////////////////////////////////////////////////////////////////////////////////



//初期化
//下記を実行する
//delta[layer_count - 1] = u[layer_count - 1] - D;
//下記の2式に分けて実行する
//delta[layerCount -1] = u[layer_count - 1];
//delta[layer_count - 1] = (-1.0f) * D + delta[layerCount -1];
template<class AF>
void Backpropagation_Base<AF>::obtainDeltaLast(const DeviceMatrix& D)
{
	
	//delta[layerCount -1] = u[layer_count - 1];
	delta[layerCount -1] = u[layerCount - 1];
	
	//delta[layer_count - 1] = (-1.0f) * D + delta[layerCount -1];
	float alpha = -1.0f;
	Saxpy(&alpha, D, delta[layerCount -1]);
	
	//ストリーム完了待ち
	CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
}

//逆伝播でのdeltaの算出
//lについて降順に逐次実行("**"は要素ごとの積(cudaで実行))
//delta[l] = f'(u[l]) ** ((W[l + 1])^T * delta[l+1]);
//l = layerCount - 2, ... , 1
template<class AF>
void Backpropagation_Base<AF>::obtainDelta(unsigned int l)
{
	//WTdelta[l +1] = (W[l + 1])^T * delta[l+1];
	//<=>
	//WTdelta[l +1] = 1.0f * (W[l + 1])^T * delta[l+1] + 0.0f * WTdelta[l +1];
	float alpha = 1.0f;
	float beta  = 0.0f;
	Sgemm(&alpha, CUBLAS_OP_T, weight[l + 1], CUBLAS_OP_N, delta[l + 1], &beta, WTdelta[l + 1]);
	
	//ストリーム完了待ち
	CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
	
	//delta[l] = f'(u[l]) ** WTdelta[l + 1];
	obtainDeltaFromFdUWTDelta(l);
	
	//ストリーム完了待ち
	CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
}

template<class AF>
void Backpropagation_Base<AF>::init(const std::vector<unsigned int>& unit_count, unsigned int minibatch_size)
{
	//NULL Streamを使用する
	CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), 0));
	
	if(layerCount != unit_count.size())
	{
		throw BackpropagationException("error at Backpropagation_Base<AF>::init() : layerCount != unit_count.size().");
	}
	unitCount = unit_count;
	
	if(minibatch_size == 0)
	{
		throw BackpropagationException("error at Backpropagation_Base<AF>::init() : minibatch_size == 0.");
	}
	miniBatchSize = minibatch_size;
	
	u.clear();
	z.clear();
	weight.clear();
	bias.clear();
	WTdelta.clear();
	delta.clear();
	deltaWeight.clear();
	deltaBias.clear();

	for(unsigned int l = 0; l < layerCount; l++)
	{
		if(unitCount[l] == 0)
		{
			std::stringstream msg;
			msg << "error at Backpropagation_Base<AF>::init() : unitCount[" << l << "] == 0.";
			throw BackpropagationException(msg.str());
		}
		
		z.push_back(DeviceMatrix(unitCount[l], miniBatchSize));
		if(l == 0)
		{
			//インデックスl = 0は使用しないのでダミーの値を格納する。
			u.push_back(      DeviceMatrix(1, 1, {0.0f}));
			weight.push_back( DeviceMatrix(1, 1, {0.0f}));
			bias.push_back(   DeviceVector{0.0f}        );
			WTdelta.push_back(DeviceMatrix(1, 1, {0.0f}));
			delta.push_back(  DeviceMatrix(1, 1, {0.0f}));
			deltaWeight.push_back( DeviceMatrix(1, 1, {0.0f}));
			deltaBias.push_back(   DeviceVector{0.0f}        );
		}
		else
		{
			u.push_back(      DeviceMatrix(unitCount[l], miniBatchSize));
			weight.push_back( DeviceMatrix(unitCount[l],unitCount[l-1]));
			bias.push_back(   DeviceVector(unitCount[l]));
			WTdelta.push_back(DeviceMatrix(unitCount[l-1], miniBatchSize));
			delta.push_back(  DeviceMatrix(unitCount[l], miniBatchSize));
			deltaWeight.push_back( DeviceMatrix(unitCount[l],unitCount[l-1]));
			deltaBias.push_back(   DeviceVector(unitCount[l]));
		}
	}
	
	_1B = DeviceVector::get1Vector(miniBatchSize);
	
	//weightとbiasをランダムに初期化する
	this->initRandom();
	
	//deltaWeightを0.0fで初期化
	for(DeviceMatrix& dw : deltaWeight)
	{
		unsigned int N = dw.getRowCount();
		unsigned int M = dw.getColumnCount();
		dw.set(std::vector<float>(N * M, 0.0f));
	}
	//deltaBiasを0.0fで初期化
	for(DeviceVector& db : deltaBias)
	{
		unsigned int N = db.getDimension();
		db.set(std::vector<float>(N, 0.0f));
	}

}

template<class AF>
void Backpropagation_Base<AF>::initRandom(void)
{
	//NULL Streamを使用する
	CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), 0));
	/*
	std::random_device rdev;
	std::mt19937 engine(rdev());
	std::uniform_real_distribution<float> urd(0.0f, 1.0f);
	*/
	for(DeviceMatrix& w : weight)
	{
		unsigned int M = w.getRowCount();
		unsigned int N = w.getColumnCount();
		/*
		std::vector<float> h_w;
		for(unsigned int i =0; i < M * N; i++)
		{
			//定義域の次元が大きい時に絶対値が大きくなると
			//活性化関数の値が1に上げ止まってしまうので
			//乱数の値をNで割る
			h_w.push_back(urd(engine) / static_cast<float>(N));
		}
		w.set(h_w);
		*/
		
		//wのデバイスメモリに値域(0.0, 1.0]の一様分布に従う乱数を生成
		CURAND_CALL(curandGenerateUniform(CuRandManager::getGenerator(), w.getAddress(), M * N));
		//wを1/Nでスカラー倍する
		float alpha = 1.0f / static_cast<float>(N);
		//float alpha = 0.01f / static_cast<float>(N);
		Sscal(&alpha, w);
		
	}
	//biasは一律0で初期化する
	for(auto&& b : bias)
	{
		unsigned int N = b.getDimension();
		std::vector<float> h_b(N, 0.0f);
		b.set(h_b);
	}
}

template<class AF>
void Backpropagation_Base<AF>::forward(const std::vector<float>& x, std::vector<float>& y)
{
	DeviceMatrix X(x.size(), 1, x);
	DeviceMatrix Y;
	forward(X, Y);
	y = Y.get();
}
template<class AF>
void Backpropagation_Base<AF>::forward(const DeviceMatrix& X, DeviceMatrix& Y)
{
	//使用するStreamをMainStreamに設定
	//CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), this->getMainStream()));
	CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), 0));
	
	z[0] = X;
	//ストリーム完了待ち
	//CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
	for(unsigned int l = 0; l < layerCount - 1; l++)
	{
		//z[l], weight[l+1], bias[l+1]からu[l+1]を得る
		obtainUFromZ(l);
		//ストリーム完了待ち
		//CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
		//u[l+1]からz[l+1]を得る
		obtainZFromU(l);
		//ストリーム完了待ち
		//CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
	}
	//y = z[L-1]を設定
	Y = z[layerCount - 1];
	//ストリーム完了待ち
	//CUDA_CALL(cudaStreamSynchronize(this->getMainStream()));
}

template<class AF>
void Backpropagation_Base<AF>::back(const std::vector<float>& d)
{
	DeviceMatrix D(d.size(), 1, d);
	back(D);
}
template<class AF>
void Backpropagation_Base<AF>::back(const DeviceMatrix& D)
{
	//使用するStreamをMainStreamに設定
	CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), this->getMainStream()));
	
	//初期化
	//delta[layer_count - 1] = u[layer_count - 1] - dd;
	obtainDeltaLast(D);
	
	//lについて降順に逐次実行("**"は要素ごとの積(cudaで実行))
	//delta[l] = f'(u[l]) ** ((W[l + 1])^T * delta[l+1]);
	//l = layerCount - 2, ... , 1
	for(unsigned int l = layerCount - 2; l >= 1; l--)
	{
		obtainDelta(l);
	}
	
	
	
}

template<class AF>
void Backpropagation_Base<AF>::updateParameter()
{
	//l,W,b について非同期に実行
	
	unsigned int substream_count = getSubStreamCount();
	
	for(unsigned int l = 1; l < layerCount; l++)
	{
		//使用するStreamを設定
		unsigned int si = (2 * l) % substream_count;
		CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), this->getSubStream(si)));
		
		//モメンタム
		//-----------------------------------------------
		// deltaWeight[l] = gamma * deltaWeight[l] - epsilon * dEdW[l]
		// weight[l] = weight[l] + deltaWeight[l]
		
		// deltaWeight[l] = gamma * deltaWeight[l] - epsilon * dEdW[l]
		//                = gamma * deltaWeight[l] - epsilon * (1 / B) * delta[l] * z[l - 1]^T
		//                = - (epsilon / B) * delta[l] * z[l - 1]^T + gamma * deltaWeight[l]
		float alpha = - epsilon / miniBatchSize;
		float beta = gamma;
		Sgemm(&alpha, CUBLAS_OP_N, delta[l], CUBLAS_OP_T, z[l - 1], &beta, deltaWeight[l]);
		// weight[l] = weight[l] + deltaWeight[l]
		//           = 1.0f * weight[l] + 1.0f * deltaWeight[l]
		alpha = 1.0f;
		beta  = 1.0f;
		Sgeam(&alpha, CUBLAS_OP_N, weight[l], &beta, CUBLAS_OP_N, deltaWeight[l], weight[l]);
		//-----------------------------------------------
		
		
		//モメンタムなし
		//-----------------------------------------------
		//W[l] = W[l] - epsilon * dEdW[l]
		//     = W[l] - epsilon * (1 / B) * delta[l] * z[l - 1]^T
		//     = W[l] - (epsilon / B) * delta[l] * z[l - 1]^T
		//     = - (epsilon / B) * delta[l] * z[l - 1]^T + 1.0f * W[l]
		//alpha = - epsilon / miniBatchSize;
		//beta = 1.0f;
		//Sgemm(&alpha, CUBLAS_OP_N, delta[l], CUBLAS_OP_T, z[l - 1], &beta, weight[l]);
		//-----------------------------------------------
		
		//使用するStreamを設定
		si = (2 * l + 1) % substream_count;
		CUBLAS_CALL(cublasSetStream(CuBlasManager::getHandle(), this->getSubStream(si)));
		
		//モメンタム
		//-----------------------------------------------
		// deltaBias[l] = gamma * deltaBias[l] - epsilon * dEdb[l]
		// bias[l] = bias[l] + deltaBias[l]
		
		// deltaBias[l] = gamma * deltaBias[l] - epsilon * dEdb[l]
		//              = gamma * deltaBias[l] - epsilon * ((1.0f / B) * delta[l] * _1B)
		//              = gamma * deltaBias[l] - (epsilon / B) * delta[l] * _1B
		//              = - (epsilon / B) * delta[l] * _1B + gamma * deltaBias[l]
		alpha = - epsilon / miniBatchSize;
		beta = 1.0f;
		Sgemv(&alpha, CUBLAS_OP_N, delta[l], _1B, &beta, deltaBias[l]);
		
		// bias[l] = bias[l] + deltaBias[l]
		//         = 1.0f * deltaBias[l] + bias[l]
		alpha = 1.0f;
		Saxpy(&alpha, deltaBias[l], bias[l]);
		//-----------------------------------------------
		
		
		//モメンタムなし
		//-----------------------------------------------
		//b[l] = b[l] - epsilon * dEdb[l]
		//     = b[l] - epsilon * ((1.0f / B) * delta[l] * _1B)
		//     = b[l] - (epsilon / B) * delta[l] * _1B
		//     = - (epsilon / B) * delta[l] * _1B + 1.0f * b[l]
		//alpha = - epsilon / miniBatchSize;
		//beta = 1.0f;
		//Sgemv(&alpha, CUBLAS_OP_N, delta[l], _1B, &beta, bias[l]);
		//-----------------------------------------------
		
	}
	
	//完了待ち
	for(unsigned int s = 0; s < substream_count; s++)
	{
		CUDA_CALL(cudaStreamSynchronize(getSubStream(s)));
	}
}
