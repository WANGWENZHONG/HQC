# HQC
## 1. 算法调研与总体架构

HQC-128 是基于 Hamming Quasi-Cyclic 码的 KEM，主要流程包括密钥生成、封装和解封装。硬件实现中的高频路径为 SHAKE/seed expander、固定重量向量采样、GF(2) 环上稀疏向量乘密集向量、RS/RM 纠错编解码以及打包解析。

本设计采用 PS+PL 协处理架构：

- 控制入口：AXI4-Lite 寄存器、SPI 帧接口、UART 调试帧接口。
- 数据窗口：片上 BRAM 字节窗口保存 `seed/pk/sk/ct/ss/scratch`。
- 调度层：`hqc_kem_scheduler` 将 KEYGEN、ENCAP、DECAP 展开成固定顺序微操作。
- 算法原语层：复用已有 `hqc_shake_rng_v`、`hqc_fixed_weight_sampler_v`、`vector_multi_top`、`HQC_encode_top`、`HQC_decode_top`。
- 安全层：命令 CRC、常数时间比较、无早退解封装、故障锁存、zeroize、watchdog/非法状态检测接口。

推荐使用 SPI 作为主接口。4481 字节密文在 50 MHz SPI 下理论传输时间约 0.72 ms；115200 UART 约 0.31 s，只适合调试。

## 2. 关键模块实现

- `hqc_accel_top.v`：系统顶层，连接 SPI/UART、AXI4-Lite、BRAM、命令解析、响应发送与 KEM 调度器。
- `hqc_axi4lite_regs.v`：寄存器包含 CMD、STATUS、IRQ_EN、LEN、ADDR、ERR、FAULT、ZEROIZE、SEED0..7。
- `hqc_cmd_frame_rx.v`：统一命令帧解析，检查 SOF、长度和 CRC-16/CCITT，WRITE_MEM payload 直接写 BRAM。
- `hqc_resp_frame_tx.v`：统一响应帧发送，支持从 BRAM 回读 READ_MEM 数据。
- `hqc_kem_scheduler.v`：KEYGEN/ENCAP/DECAP 固定序列调度；解封装始终执行重加密、哈希、常数时间比较和最终 KDF。
- `hqc_rng_sampler_cluster.v`：把已有 SHAKE SeedExpander 与固定重量采样器接成可复用采样单元。
- `hqc_pack_engine.v`：用于 pack/unpack/zeroize 的字节 copy/fill 引擎。
- `hqc_security.v`：常数时间比较、掩码选择、watchdog 和故障锁存辅助模块。
- `hqc_buffer_ram.v`：统一 BRAM 数据窗口，并补充已有乘法器需要的 `vector_ram`。

## 3. 性能与资源分析

性能目标为 HQC-128 encaps 小于或接近 5 ms。设计选择：

- SPI 主接口避免 UART 传输成为瓶颈。
- 调度层复用 SHAKE、采样、乘法和编解码核，降低面积。
- `vector_multi_top` 已采用双子核并行处理稀疏坐标，适合封装中的 `h*r2` 与 `s*r2`。
- 固定重量采样输出 dense 128-bit block，便于直接喂给 128-bit 数据通路。

待综合后补充：

- LUT/FF/BRAM/DSP 使用量。
- KEYGEN/ENCAP/DECAP 周期数。
- SPI 接口、采样器、乘法器、编解码器分别的瓶颈占比。

## 4. 仿真与测试

已有仓库包含 SHAKE、固定重量采样、vector multiply、RS/RM 编解码测试平台。新增：

- `tb/tb_hqc_kem_scheduler.v`：使用 `hqc_primitive_done_model.v` 检查 KEYGEN/ENCAP/DECAP/SELFTEST 调度序列能正常结束。
- 命令帧可通过 WRITE_MEM/READ_MEM 做 BRAM 回环测试。
- 后续建议加入 HQC 官方 KAT：PS 侧加载 seed/pk/sk/ct，PL 侧执行 opcode 后回读结果比对。

当前环境未发现 `iverilog/verilator/xvlog/vivado/procise` 命令，尚未完成工具级编译仿真。

## 5. 安全机制与未来改进

已实现或预留的安全点：

- 解封装无早退：无论比较是否失败，都执行完整重加密与最终 KDF 路径。
- 常数时间比较和失败掩码选择接口。
- 命令帧 CRC 与长度检查。
- 故障标志锁存、watchdog、zeroize 接口。
- 建议在 Procise/Vivado 中启用 BRAM ECC/parity、安全 FSM 编码和关键寄存器复制。

可作为加分优化方向：

- 多路 SHAKE/Keccak 或双缓冲 seed expander，隐藏采样等待。
- `vector_multi_top` 扩展为 4 路稀疏坐标并行。
- 针对 `u/v` pack 使用 128/256-bit burst BRAM 搬运，减少字节接口开销。
- 固定重量采样采用固定候选窗口和掩码写入，进一步降低时序/功耗泄漏。
- 在 FMQL45T900/Procise 上形成完整综合、布局布线和功耗报告。
