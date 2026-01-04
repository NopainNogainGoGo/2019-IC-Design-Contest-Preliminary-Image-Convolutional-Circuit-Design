以下為我寫這題學到的一些東西：

### 1. 定點數運算與 Bias 對齊 (Q-Format)

這是硬體運算中最核心的部分，強調在進行加法前必須手動對齊小數點（Binary Point）。
**小數點對齊原理**：硬體加法器預設只會對齊最低位元（LSB）。若直接將 Input (e.g., Q8.8) 與 Bias (e.g., Q4.16) 相加，數學結果會完全錯誤 。
**Bias 擴展步驟**：假設累加器為 40-bit (Q12.28)，而原始 Bias 為 20-bit (Q4.16)，需要進行轉換 ：
**符號擴展 (Sign Extension)**：在左側（高位）補上符號位元（正數補 0，負數補 1）以補齊整數部分 。
**補零 (Zero Padding)**：在右側（低位）補 0 以對齊小數精度 。
**Verilog 注意事項**：運算中若混合 Signed 與 Unsigned，Verilog 會將全體視為 Unsigned 。



### 2. 卷積運算 (Convolution) 實作細節
**定址與狀態控制**：使用 X, Y 計數器從 (0,0) 數到 63。當計數器溢位至 64 (`1_000000`) 時歸零，並以此信號判斷 FSM 狀態跳轉 。
 **Zero Padding 處理**：
透過 `Counter_kaddr` 產生地址給 Testbench 抓取資料 (`idata`) 。
使用 `idata_tmp` 暫存資料，若座標位於邊界（最外圍），則強制填入 0 (Zero Padding) 。
**時序控制**：Kernel 的計數器是組合電路（當下更新），而讀取地址 `iaddr` 是序向電路（會慢一個 Cycle 更新），需注意此時序差 。
**運算優化**：不需使用二維陣列儲存資料，讀取到的 `idata` 直接與 Kernel 相乘並累加至 `conv_sum`。前 9 次進行卷積累加，第 10 次加上 Bias 。


### 3. 後處理：Rounding 與 ReLU
**四捨五入 (Rounding)**：題目要求「0 捨 1 入」。實作方式是截取累加結果的高位 `conv_sum[35:16]` 並加上第 15 位 (`conv_sum[15]`) 來進位 。
**ReLU 激活函數**：檢查符號位 (MSB)。若 `conv_sum[39]` 為 1（負數），輸出 0；否則輸出原始計算結果 。



### 4. 最大池化 (Max Pooling - Layer 1)
**流程**：從 Layer 0 記憶體讀取卷積後的資料，同樣使用 X, Y 定址 。
**比較邏輯**：使用比較器更新最大值。若讀取到的 `cdata_rd` 大於 `current_max`，則更新 `current_max` 。
**寫回**：比較完 4 筆資料後，將最終的 `current_max` 寫入 SRAM，完成池化運算 。
