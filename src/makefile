#C++向けで、以下の前提で使用可能なmakefile
#
#・同一フォルダにヘッダ・ソースと実行ファイルが格納されている
#・実行ファイルはフォルダ名と同一
#・main関数を持つソースはフォルダ名.cpp
#・ソースの拡張子はcpp

#変数定義
###################################################

#makefile自体のデバッグ用
#OLD_SHELL := $(SHELL)
#SHELL = $(warning [Making: $@]   [Dependencies: $^]   [Changed: $?])$(OLD_SHELL)

#ターゲット
#作成する実行ファイル
#2個上のフォルダ名と同一
TARGET := $(shell basename `dirname \`pwd\``)

#テスト用のターゲット
#テストを実行する
TESTTARGET := unittest

#NVCC、g++共通のフラグ（デバッグ出力、最適化レベル）:デバッグ用
COMMON_FLAGS := -pg -g -O0
#COMMON_FLAGS := 

#CXX_LINKS
CXX_LINKS := -L/usr/local/lib -L/usr/local/cuda/lib64 -lgtest -lsqlite3 -lcudart -lcublas -lcurand -lcusolver

#ホームディレクトリのパス(末尾に"/"無し)
HOME := $(shell echo ~)

#g++のコンパイルのフラグ
CXXFLAGS := -Wall -fopenmp -I/usr/include -I/usr/local/cuda/include -I$(HOME)/programs/ATFViewer/include $(CXX_LINKS)
#CXXFLAGS := -Wall -fopenmp -I/usr/include -I/usr/local/include -I/usr/local/cuda/include -I$(HOME)/programs/ATFViewer/include $(CXX_LINKS)
CXXONLYFLAGS := -std=c++11 -Weffc++

#CUDA関連の設定

#CUDAコンパイラ
NVCC := nvcc

#CUDAコンパイルオプション(-Gはデバッグ情報出力)
NVCC_FLAGS := --std c++11 -G -Wno-deprecated-gpu-targets

#NVCC向けのg++オプション
NVCC_CXX_FLAGS := $(CXXFLAGS:%=-Xcompiler %)

#CUDAリンクオプション
NVCC_LINKS := -lcuda $(CXX_LINKS)


#ソースファイル
#フォルダ直下の.cppファイル
SRCS := $(shell find * -name "*.cpp")

#CUDAソース
#フォルダ直下の.cuファイル
CUDA_SRCS := $(shell find * -name "*.cu")

#中間ファイルの格納先
OBJDIR := ../obj

#出力ファイルの格納先
OUTDIR := ../out

#オブジェクトファイル
#.cppを.oに置換している
OBJS := $(addprefix $(OBJDIR)/, $(SRCS:.cpp=.o))

#CUDA用のオブジェクトファイル
#.cuを.oに置換している
CUDA_OBJS := $(addprefix $(OBJDIR)/, $(CUDA_SRCS:.cu=.o))

#ターゲット用のオブジェクトファイル
OBJSTARGET := $(filter-out $(OBJDIR)/$(TESTTARGET).o, $(OBJS)) $(filter-out $(OBJDIR)/$(TESTTARGET).o, $(CUDA_OBJS))

#テスト用のオブジェクトファイル
OBJSTEST := $(filter-out $(OBJDIR)/$(TARGET).o, $(OBJS)) $(filter-out $(OBJDIR)/$(TARGET).o, $(CUDA_OBJS))

#テストのコマンドラインオプション
TESTOPTION := --gtest_color=yes

#依存関係ファイル
DEPS := $(OBJS:.o=.d)

#CUDA用の依存関係ファイル
CUDA_DEPS := $(CUDA_OBJS:.o=.cu.d)

#gprof2dot.pyのコマンド
GPROF2DOT := ~/tools/gprof2dot/gprof2dot.py -s

#nvprof_graph.shのパス
NVPROFGRAPH := ~/tools/nvprof_graph/nvprof_graph.sh

#nvprofコマンド
NVPROF := nvprof --csv

#コマンド
###################################################

#全てコンパイルする
#先頭に書いたコマンドはmakeコマンドでオプション無しで実行される
.PHONY: all
all: $(OUTDIR)/$(TARGET) $(OUTDIR)/$(TESTTARGET)

.PHONY: run
run: $(OUTDIR)/$(TARGET)
	(\
		cd $(OUTDIR);\
		$(NVPROF) --log-file $(TARGET).nvprof $(TARGET);\
		if [ -f core ]; then banner core dumped!;fi;\
		gprof $(TARGET) | $(GPROF2DOT) | dot -Tpng -o gprof_call_graph_$(TARGET).png;\
	)

#テストの実行ファイルを実行する
#プロファイルは実行しない
#ログと標準出力両方に出力する
.PHONY: test
test: $(OUTDIR)/$(TESTTARGET)
	(\
		cd $(OUTDIR);\
		./$(TESTTARGET) $(TESTOPTION) 2>&1 | tee -a $(TESTTARGET).log;\
		if [ -f core ]; then banner core dumped!;fi;\
	)

#テストとプロファイルを実行する
#ログと標準出力両方に出力する
.PHONY: testprof
testprof: $(OUTDIR)/$(TESTTARGET)
	(\
		cd $(OUTDIR);\
		$(NVPROF) --log-file $(TESTTARGET).nvprof ./$(TESTTARGET) $(TESTOPTION) 2>&1 | tee -a $(TESTTARGET).log;\
		if [ -f core ]; then banner core dumped!;fi;\
		gprof $(TESTTARGET) | $(GPROF2DOT) | dot -Tpng -o gprof_call_graph_$(TESTTARGET).png;\
		$(NVPROFGRAPH) $(TESTTARGET) nvprof_$(TESTTARGET).png;\
	)

#githubにアップロードする
.PHONY: git
git: $(OUTDIR)/$(TARGET) 
	(cd ..; git add --all .;)
	(cd ..; git commit -a;)
	(cd ..; git push -u origin `git branch | grep "*" | cut -d " " -f 2`;)

.PHONY: doc
doc: $(OUTDIR)/$(TARGET)
	(cd ..; doxygen;)
	(cd ../docs; git add .;)
	(cd ../docs; git commit -m "update docs.";)
#	(cd ../docs; git push origin gh-pages;)
#	(cd ..; git add docs/;)
#	(cd ..; git commit -m "update docs.";)


#makefile自体のテスト用
MAKETEST_EXIST = glunittest
MAKETEST_NOTEXIST = notexistfile
.PHONY: maketest
maketest:
	$(warning OBJS = $(OBJS))
	$(warning DEPS = $(DEPS))
	$(warning CUDA_OBJS = $(CUDA_OBJS))
	$(warning CUDA_DEPS = $(CUDA_DEPS))

#実行ファイルの作成
#オプションは最後に指定する
#先頭に書くとコンパイルが通らない
#<ターゲット>: ターゲットに依存するファイル
#$@ : ターゲット名
#$* : ターゲット名からサフィックスを除いたもの
#$< : 最初の依存ファイル名(":"の右側の最初(一番左)の項目)
#$^ : 依存ファイル全体
$(OUTDIR)/$(TARGET): $(OBJSTARGET)
	$(NVCC) $(NVCC_LINKS) $(COMMON_FLAGS) $(NVCC_FLAGS) -o $(OUTDIR)/$@ $^ $(NVCC_CXX_FLAGS)

#テスト用の実行ファイルを作成
$(OUTDIR)/$(TESTTARGET): $(OBJSTEST)
	$(NVCC) $(NVCC_LINKS) $(COMMON_FLAGS) $(NVCC_FLAGS) -o $(OUTDIR)/$@ $^ $(NVCC_CXX_FLAGS)

#オブジェクトファイルの作成
#"-MMD"オプションによって依存関係ファイル(*.d)も同時に作成する
$(OBJDIR)/%.o: %.cpp
	$(CXX) -c -MMD -MF $(@:%.o=%.d) $< $(COMMON_FLAGS) $(CXXONLYFLAGS) $(CXXFLAGS) -o $@

$(OBJDIR)/%.o: %.cu
	$(NVCC) $(COMMON_FLAGS) $(NVCC_LINKS) $(NVCC_FLAGS) $(NVCC_CXX_FLAGS) -c $< -o $@
	$(NVCC) $(COMMON_FLAGS) $(NVCC_LINKS) $(NVCC_FLAGS) $(NVCC_CXX_FLAGS) -M $< -odir $(OBJDIR) > $(@:.o=.cu.d)

#実行ファイル・中間ファイルの削除
#".PHONY"はターゲットではなくコマンドであることを明示するためのコマンド
.PHONY: clean
clean:
	$(RM) $(TARGET) $(TESTTARGET) $(OBJS) $(DEPS) $(CUDA_OBJS) $(CUDA_DEPS)

#依存関係ファイルをインクルードする
#先頭に”-”を書いているので依存関係ファイルがなくてもエラーとならない
-include $(DEPS)
-include $(CUDA_DEPS)

