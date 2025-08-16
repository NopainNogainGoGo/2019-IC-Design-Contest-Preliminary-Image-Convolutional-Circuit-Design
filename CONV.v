module CONV(
	input			clk,              // 時鐘輸入
	input			reset,            // 重置信號
	output reg		busy,	           // 模組是否忙碌
	input			ready,	           // 控制訊號，啟動模組運作
	output reg[11:0]	iaddr,           // 輸入資料的讀取地址
	input signed[19:0]	idata,           // 從輸入記憶體讀取的資料
	output reg 	     cwr,             // 控制信號，寫入資料至 SRAM
	output reg[11:0] 	caddr_wr,        // 寫入 SRAM 的地址
	output reg[19:0] 	cdata_wr,        // 寫入 SRAM 的資料
	output reg	 crd,              // 控制信號，讀取資料從 SRAM
	output reg[11:0]	caddr_rd,        // 讀取 SRAM 的地址
	input	[19:0]		cdata_rd,        // 從 SRAM 讀取的資料
	output reg[2:0] 	csel             // SRAM 選擇控制訊號
);

//==============================
// Kernel 參數設定
//==============================
parameter bias = 40'h0013100000;   // 偏移值 (bias)
parameter K0_0 = 20'h0A89E;        // Kernel[0][0]
parameter K0_1 = 20'h092D5;        // Kernel[0][1]
parameter K0_2 = 20'h06D43;        // Kernel[0][2]
parameter K0_3 = 20'h01004;        // Kernel[1][0]
parameter K0_4 = 20'hF8F71;        // Kernel[1][1]
parameter K0_5 = 20'hF6E54;        // Kernel[1][2]
parameter K0_6 = 20'hFA6D7;        // Kernel[2][0]
parameter K0_7 = 20'hFC834;        // Kernel[2][1]
parameter K0_8 = 20'hFAC19;        // Kernel[2][2]

//==============================
// 有限狀態機 FSM 狀態定義
//==============================
parameter IDLE       = 3'd0;   // 等待開始
parameter READ_CONV  = 3'd1;   // 讀取並計算卷積
parameter WRITE_L0   = 3'd2;   // 將卷積結果寫入 Layer 0
parameter DELAY1     = 3'd3;   // 等待狀態
parameter READ_L0    = 3'd4;   // 讀取 Layer 0 進行 MaxPooling
parameter WRITE_L1   = 3'd5;   // 將最大值寫入 Layer 1
parameter DELAY2     = 3'd6;   // 等待狀態
parameter FINISH     = 3'd7;   // 完成處理

//==============================
// 內部暫存與控制變數
//==============================
reg [5:0] x, y, L1_x, L1_y;            // 座標計數器（卷積與池化）
reg [3:0] counter_kdata, counter_kaddr;  // 計數器：控制讀取順序與Kernel對應
reg [2:0] counter_layer1;	           // 計數器：控制MaxPooling位置
reg [2:0] current_state, next_state;   // FSM 狀態暫存
reg signed [19:0] Kernel;              // 當前使用的Kernel值
reg signed [39:0] conv_sum;            // 卷積累加結果
reg signed [19:0] idata_tmp;           // idata輸入做 Zero padding 後暫存值

//==============================
// 組合邏輯（卷積計算）
//==============================
wire signed [39:0] data_conv;
wire signed [19:0] conv_result;
assign data_conv = Kernel * idata_tmp;             // 乘上Kernel值
assign conv_result[19:0] = conv_sum[35:16] + conv_sum[15];  // 取捨與rounding後的最終值

//==============================
// 根據 counter_kdata 對應 Kernel 值
//==============================
always@(*) begin
	case(counter_kdata)
		4'd1: Kernel = K0_0;
		4'd2: Kernel = K0_1;
		4'd3: Kernel = K0_2;
		4'd4: Kernel = K0_3;
		4'd5: Kernel = K0_4;
		4'd6: Kernel = K0_5;
		4'd7: Kernel = K0_6;
		4'd8: Kernel = K0_7;
		4'd9: Kernel = K0_8;
		default: Kernel = 0;
	endcase
end

//==============================
// 1. cs
//==============================
always@(posedge clk or posedge reset) begin
	if(reset) 
		current_state <= IDLE;
	else 
		current_state <= next_state;
end

//==============================
// 2. ns
//==============================
always @(*) begin
	case (current_state)
		IDLE:       next_state = (ready) ? READ_CONV : IDLE;
		READ_CONV:  next_state = (counter_kdata == 4'd10) ? WRITE_L0 : READ_CONV; //前9次做累加，第10次加上 bias
		WRITE_L0:   next_state = DELAY1;
		DELAY1:     next_state = (x == 6'd0 && y == 6'd0) ? READ_L0 : READ_CONV;
		READ_L0:    next_state = (counter_layer1 == 3'd4) ? WRITE_L1 : READ_L0;
		WRITE_L1:   next_state = DELAY2;
		DELAY2:     next_state = (L1_x == 6'd0 && L1_y == 6'd0) ? FINISH : READ_L0;
		FINISH:     next_state = FINISH;
		default:    next_state = IDLE;
	endcase
end

//==============================
// 3. ol
//==============================

//=======READ_CONV=======
// 控制輸入記憶體讀取地址 iaddr（依據 filter 位置）
always@(posedge clk or posedge reset) begin
	if(reset) begin 
		iaddr <= 12'd0;
	end
	else if(current_state == READ_CONV) begin//指示欲索取哪個灰階圖像像素(pixel)的位址 用x,y去定址
		case(counter_kaddr)
			4'd0: iaddr <= (y-1)*64 + x-1;
			4'd1: iaddr <= (y-1)*64 + x;
			4'd2: iaddr <= (y-1)*64 + x+1;
			4'd3: iaddr <= y*64 + x-1;
			4'd4: iaddr <= y*64 + x;		// center
			4'd5: iaddr <= y*64 + x+1;		
			4'd6: iaddr <= (y+1)*64 + x-1;
			4'd7: iaddr <= (y+1)*64 + x;
			4'd8: iaddr <= (y+1)*64 + x+1;
			default: iaddr <= iaddr;
		endcase
	end
end

// counter_kaddr 控制卷積讀取順序
always@(posedge clk or posedge reset) begin
	if(reset) 
		counter_kaddr <= 4'd0;
	else if(current_state == READ_CONV) 
		counter_kaddr <= counter_kaddr + 4'd1;
	else 
		counter_kaddr <= counter_kaddr; // 最後的 else 不要賦新值 這樣Design Complier可以幫忙做clk gating
end

// idata_tmp 控制：根據邊界情況做 zero padding
always@(posedge clk or posedge reset) begin
	if(reset) 
		idata_tmp <= 0;
	else if(current_state == READ_CONV) begin
		case(counter_kdata)
			4'd0: idata_tmp <= (x == 0 || y == 0) ? 20'd0 : idata;
			4'd1: idata_tmp <= (y == 0) ? 20'd0 : idata;
			4'd2: idata_tmp <= (x == 63 || y == 0) ? 20'd0 : idata;
			4'd3: idata_tmp <= (x == 0) ? 20'd0 : idata;
			4'd4: idata_tmp <= idata;
			4'd5: idata_tmp <= (x == 63) ? 20'd0 : idata;
			4'd6: idata_tmp <= (x == 0 || y == 63) ? 20'd0 : idata;
			4'd7: idata_tmp <= (y == 63) ? 20'd0 : idata;
			4'd8: idata_tmp <= (x == 63 || y == 63) ? 20'd0 : idata;
			default: idata_tmp <= idata_tmp;
		endcase
	end 
end

// 卷積累加器：前9次做累加，第10次加上 bias
always@(posedge clk or posedge reset) begin
	if(reset) 
		conv_sum <= 40'd0;
	else if(current_state == READ_CONV) begin
		if(counter_kdata == 0) 
			conv_sum <= 40'd0;
		else if(counter_kdata == 10)    // 第10次：加上bias
			conv_sum <= conv_sum + bias;
		else  
			conv_sum <= conv_sum + data_conv; // 0-8 (9) 次：累加卷積結果
	end
end


// busy 信號控制：表示模組是否正在運作中
always@(posedge clk or posedge reset) begin
	if(reset) 
		busy <= 0;
	else if(ready) 
		busy <= 1; 
	else if(current_state == FINISH) 
		busy <= 0;
end

// cwr 控制：寫入 Layer 0 / Layer 1
always@(posedge clk or posedge reset) begin
	if(reset) 
		cwr <= 1'd0;
	else if(current_state == WRITE_L0 || current_state == WRITE_L1)
		cwr <= 1'd1;
	else 
		cwr <= 1'd0;
end

// crd 控制：從 Layer 0 讀取資料（池化階段）
always@(posedge clk or posedge reset) begin
	if(reset) 
		crd <= 1'd0;
	else if(current_state == READ_L0) 
		crd <= 1'd1;
	else 
		crd <= 1'd0;
end

// csel 控制：SRAM選擇控制（分別對應 Layer0/1）
always@(posedge clk or posedge reset) begin
	if(reset) 
		csel <= 3'b000;
	else if(current_state == WRITE_L0) 
		csel <= 3'b001;
	else if(current_state == WRITE_L1) 
		csel <= 3'b011;
	else if(current_state == READ_L0) 
		csel <= 3'b001;
	else 
		csel <= csel;
end

// caddr_rd 控制：讀取 Layer 0 資料地址（用於池化）
always@(posedge clk or posedge reset) begin
	if(reset) 
		caddr_rd <= 12'd0;
	else if(current_state == READ_L0) begin
		case(counter_layer1)
			3'd0: caddr_rd <= L1_y*64 + L1_x;
			3'd1: caddr_rd <= L1_y*64 + L1_x+1;
			3'd2: caddr_rd <= (L1_y+1)*64 + L1_x;
			3'd3: caddr_rd <= (L1_y+1)*64 + L1_x+1;
		endcase 
	end
end

// caddr_wr 控制：寫入 Layer 0 / Layer 1 的地址
always@(posedge clk or posedge reset) begin
	if(reset) 
		caddr_wr <= 0;
	else if(current_state == WRITE_L0) //寫入 Layer 0 地址（卷積結果）
		caddr_wr <= y * 64 + x; 
	else if(current_state == WRITE_L1) // 寫入 Layer 1 地址（MaxPooling 結果）
		caddr_wr <= (L1_y/2) * 32 + (L1_x/2); // 池化後圖片大小為原來1/4，故右移
end

//使用 {y,x} 和 {L1_y[5:1],L1_x[5:1]} 的優勢：
//硬體效率：避免乘法器，直接用位操作
//速度更快：位串接比乘法運算更快
//資源節省：不需要額外的乘法電路


//conv_sum[39] 是符號位（MSB）
//如果 conv_sum[39] = 1：表示卷積結果為負數 → 輸出 0
//如果 conv_sum[39] = 0：表示卷積結果為正數 → 輸出 conv_result
reg signed [19:0] current_max;
always@(posedge clk or posedge reset) begin
	if(reset) begin
		cdata_wr <= 20'd0;
		current_max <= 20'd0; 
	end
	else begin
		case(current_state)
			WRITE_L0: begin
				// ReLU 激活函數：負數變0，正數保持
				cdata_wr <= (conv_sum[39]) ? 20'd0 : conv_result;
			end
			
			READ_L0: begin
				// MaxPooling：持續更新最大值
				if(counter_layer1 == 3'd1) begin
					current_max <= cdata_rd; // 第一次讀取
				end else begin
					current_max <= (cdata_rd > current_max) ? cdata_rd : current_max;
				end
			end
			
			WRITE_L1: begin
				// 寫入 MaxPooling 結果並重置
				cdata_wr <= current_max;
				current_max <= 20'h80000; // 重置為最小值
			end
			
			default: begin
				// 其他狀態保持不變
			end
		endcase
	end
end

//==============================
// 卷積與池化流程內部控制邏輯
//==============================

// 卷積座標更新 (L0 每次+1 pixel)
always@(posedge clk or posedge reset) begin
	if(reset) begin
		x <= 6'd0; 
		y <= 6'd0;
	end
	else if(current_state == WRITE_L0) begin
		// better {y, x} <= {y, x} + 12'd1;
		if(x == 6'd63) begin
			x <= 6'd0;
			y <= y + 6'd1;
		end else begin
			x <= x + 6'd1;
		end
	end
end

// 池化座標更新 (L1 每次+2 pixels，因為 stride=2)
always@(posedge clk or posedge reset) begin
	if(reset) begin
		L1_x <= 6'd0; 
		L1_y <= 6'd0;
	end
	else if(current_state == WRITE_L1) begin
		if(L1_x == 6'd62) begin
			L1_x <= 0;
			L1_y <= L1_y + 2;
		end else begin
			L1_x <= L1_x + 2;
		end
	end
end


// counter_kdata = counter_kaddr 對應Kernel用
always@(posedge clk or posedge reset) begin
	if(reset) 
		counter_kdata <= 4'd0;
	else 
		counter_kdata <= counter_kaddr;
end

// counter_layer1 控制池化階段讀取次數（共4次）
always@(posedge clk or posedge reset) begin
	if(reset) 
		counter_layer1 <= 0;
	else if(current_state == READ_L0) 
		counter_layer1 <= counter_layer1 + 3'd1;
	else 
		counter_layer1 <= 0;
end

endmodule