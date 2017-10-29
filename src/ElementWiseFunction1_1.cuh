
#pragma once

//成分毎に計算する関数(1変数)
//Func1_1 : 1変数関数


template<class Func1_1>
class ElementWiseFunction1_1
{
private:
	static void culculateBlockThreadCount
		(
			const DeviceMatrix& x,
			unsigned int& block_count,
			unsigned int& thread_count,
			unsigned int& thread_count_remain
		);
public:
	//関数の適用
	static DeviceMatrix& apply(const DeviceMatrix& x, DeviceMatrix& y);
};



namespace
{
	template<typename Func1_1>
	__global__
	void apply_kernel
		(
			unsigned int thread_index_offset,
			const float* const x,
			float* const y
		)
	{
		//ブロックインデックス、スレッドインデックスの読み替え
		unsigned int s = threadIdx.x + blockIdx.x * blockDim.x + thread_index_offset;
		
		//このスレッドが計算すべき成分のインデックス
		unsigned int ij = s;
		
		y[ij] = Func1_1::apply(x[ij]);
	}
}

template<typename Func1_1>
void ElementWiseFunction1_1<Func1_1>::culculateBlockThreadCount
	(
		const DeviceMatrix& x,
		unsigned int& block_count,
		unsigned int& thread_count,
		unsigned int& thread_count_remain
	)
{
	//1ブロックあたりのスレッド数の上限
	static unsigned int thread_count_local = CudaManager::getDeviceProp().maxThreadsPerBlock;
	thread_count = thread_count_local;
	
	//生成するスレッド数全体
	unsigned int thread_count_total = x.getRowCount() * x.getColumnCount();
	
	//スレッド数thread_countで実行するブロック数
	block_count         = thread_count_total / thread_count;
	//スレッド数の残り
	thread_count_remain = thread_count_total % thread_count;
}

template<typename Func1_1>
DeviceMatrix& ElementWiseFunction1_1<Func1_1>::apply(const DeviceMatrix& x, DeviceMatrix& y)
{
	//1ブロックあたりのスレッド数の上限
	static unsigned int thread_count;
	//スレッド数thread_countで実行するブロック数
	unsigned int block_count;
	//スレッド数の残り
	unsigned int thread_count_remain;
	
	ElementWiseFunction1_1<Func1_1>::culculateBlockThreadCount(x, block_count, thread_count, thread_count_remain);
	
	if(block_count != 0)
	{
		//カーネル実行
		apply_kernel<Func1_1><<<block_count, thread_count>>>
			(
				0,
				x.getAddress(),
				y.getAddress()
			);
		//カーネル実行時のエラーチェック
		CUDA_CALL(cudaGetLastError());
	}
	if(thread_count_remain != 0)
	{
		//カーネル実行
		apply_kernel<Func1_1><<<1, thread_count_remain>>>
			(
				block_count * thread_count,
				x.getAddress(),
				y.getAddress()
			);
		//カーネル実行時のエラーチェック
		CUDA_CALL(cudaGetLastError());
	}
	//直後にdelta[l]を使用するので同期する
	CUDA_CALL(cudaStreamSynchronize(0));
	
	return y;
}

