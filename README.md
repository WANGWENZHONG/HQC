# HQC
HQC-128 是基于 Hamming Quasi-Cyclic 码的 KEM，主要流程包括密钥生成、封装和解封装。硬件实现中的高频路径为 SHAKE/seed expander、固定重量向量采样、GF(2) 环上稀疏向量乘密集向量、RS/RM 纠错编解码以及打包解析。
