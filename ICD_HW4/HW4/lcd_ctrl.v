module LCD_CTRL(clk, reset, IROM_Q, cmd, cmd_valid, IROM_EN, IROM_A, IRB_RW, IRB_D, IRB_A, busy, done);
input clk;
input reset;
input [7:0] IROM_Q;
input [2:0] cmd;
input cmd_valid;
output reg IROM_EN;
output reg [5:0] IROM_A;
output reg IRB_RW;
output reg [7:0] IRB_D;
output reg [5:0] IRB_A;
output reg busy;
output reg done;


//input output registers
//reg [7:0] _IROM_Q;
reg [2:0] _cmd;
reg _cmd_valid;
//reg IROM_EN_n;
reg [5:0] IROM_A_n;
//reg IRB_RW_n;
reg [7:0] IRB_D_n;
reg [5:0] IRB_A_n;
reg busy_n;
reg done_n;

//states for ctrl
localparam LOAD_IMG = 2'd0;
localparam CMD = 2'd1;
localparam WAIT = 2'd2;
localparam WRITE = 2'd3;

//states for cmd 
localparam _write = 3'd0;
localparam _up = 3'd1;
localparam _down = 3'd2;
localparam _left = 3'd3;
localparam _right = 3'd4;
localparam _avg = 3'd5;
localparam _m_x = 3'd6;
localparam _m_y = 3'd7;

//reg for states
reg [1:0] state_ctrl, state_ctrl_n;
//reg [2:0] state_cmd, state_cmd_n;

//memory
reg [7:0] DATA_TABLE [0:63];
reg [7:0] DATA_TABLE_nxt [0:63];
reg [9:0] GRID [0:3];
reg [9:0] GRID_n [0:3];

//reg for operation points
reg [5:0] x, x_n, y, y_n;
wire [5:0] y_up, y_down, x_left;

wire [7:0] avg_num;
wire [9:0] avg_num_tmp;

//counter
reg [6:0] counter, counter_n;
wire [6:0] counter_1, counter_2;

//wire writing;
wire writing;
wire loading;

assign loading = state_ctrl_n == LOAD_IMG;
assign writing = (state_ctrl_n == WRITE)|| (state_ctrl==WRITE && state_ctrl_n==CMD);
//assign IRB_RW = (state_ctrl_n == WRITE || (state_ctrl==WRITE && state_ctrl_n==CMD))? 1'd0: 1'd1;

assign counter_1 = counter + 7'd1;
assign counter_2 = counter + 7'd2;

assign y_up = (y-6'd1) << 3;
assign y_down = y << 3;
assign x_left = x - 6'd1;

assign avg_num_tmp = (GRID[0]+GRID[1]+GRID[2]+GRID[3])>>2;
assign avg_num = avg_num_tmp[7:0];

//for IROM IRB
always @ (*) begin
	//IROM_EN_n = IROM_EN;
	IROM_A_n = IROM_A;
	//IRB_RW_n = IRB_RW;
	IRB_A_n = IRB_A;
	IRB_D_n = IRB_D;
	busy_n = busy;
	done_n = done;
	case(state_ctrl)
		LOAD_IMG:
		begin
			if(counter == 7'd63) begin
				//IROM_EN_n = 1'd1;
				busy_n = 1'd0;
			end
			else begin
				//IROM_EN_n = 1'd0;
				busy_n = 1'd1;
			end
			IROM_A_n = counter_2[5:0];
		end
		CMD:
		begin
			//IRB_RW_n = 1'd1;
			if(_cmd_valid && (_cmd ==3'd0 )) busy_n = 1'd1;
			else busy_n = 1'd0;
		end
		WAIT:
		begin
			IRB_D_n = DATA_TABLE[0];
			//IRB_RW_n = 1'd0;
			IRB_A_n = 6'd0;
		end
		WRITE:
		begin
			if(counter == 7'd64) begin
				//IRB_RW_n = 1'd1;
				busy_n = 1'd0;
				done_n = 1'd1;
			end
			else begin
				//IRB_RW_n = 1'd0;
				busy_n =1'd1;
				done_n = 1'd0;
			end 	
			IRB_A_n = counter;
			IRB_D_n = DATA_TABLE[counter[5:0]];
		end
		default:
		begin
			//IROM_EN_n = IROM_EN;
			IROM_A_n = IROM_A;
			//IRB_RW_n = IRB_RW;
			IRB_A_n = IRB_A;
			IRB_D_n = IRB_D;
			busy_n = busy;
			done_n = done;
		end
	endcase
end
 
//DATA_TABLE
integer i ;
always @(*) begin
	for (i=0; i<=63; i=i+1) DATA_TABLE_nxt[i] = DATA_TABLE[i];

	case(state_ctrl)
		LOAD_IMG:
		begin
			if(counter <= 7'd63) DATA_TABLE_nxt[counter[5:0]] = IROM_Q;
		end
		CMD:
		begin
			if(_cmd_valid) begin
				case(_cmd)
					_avg:
					begin
						DATA_TABLE_nxt[y_up+x_left] = avg_num;
						DATA_TABLE_nxt[y_up+x] = avg_num;
						DATA_TABLE_nxt[y_down+x_left] = avg_num;
						DATA_TABLE_nxt[y_down+x] = avg_num;
					end
					_m_x:
					begin
						DATA_TABLE_nxt[y_up+x_left] = GRID[2][7:0];
						DATA_TABLE_nxt[y_up+x] = GRID[3][7:0];
						DATA_TABLE_nxt[y_down+x_left] = GRID[0][7:0];
						DATA_TABLE_nxt[y_down+x] = GRID[1][7:0];
					end
					_m_y:
					begin
						DATA_TABLE_nxt[y_up+x_left] = GRID[1][7:0];
						DATA_TABLE_nxt[y_up+x] = GRID[0][7:0];
						DATA_TABLE_nxt[y_down+x_left] = GRID[3][7:0];
						DATA_TABLE_nxt[y_down+x] = GRID[2][7:0];
					end
					default:
					begin
						for (i=0; i<=63; i=i+1) DATA_TABLE_nxt[i] = DATA_TABLE[i];
					end
				endcase
			end
		end
		default:
		begin
			for (i=0; i<=63; i=i+1) DATA_TABLE_nxt[i] = DATA_TABLE[i];
		end
	endcase
end 

//state
always @(*) begin
	state_ctrl_n = state_ctrl;
	counter_n = counter;
	x_n = x;
	y_n = y;
	for(i=0; i<=3; i=i+1) GRID_n[i] = GRID[i];
	case(state_ctrl)
		LOAD_IMG:
		begin
			if(counter == 7'd63) state_ctrl_n = CMD;
			counter_n = counter + 7'd1;
		end
		CMD:
		begin
			counter_n = 7'd0;
			if(_cmd_valid)begin
				if(_cmd == _write) state_ctrl_n = WAIT;
				for(i=0; i<=3; i =i+1) GRID_n[i] = GRID[i];
				x_n = x;
				y_n = y;
				case(_cmd)
					_up:
					begin
						if(y == 7'd1) y_n = y; // y can't smaller than 1
						else begin
							y_n = y - 7'd1;
							GRID_n[0][7:0] = DATA_TABLE[y_up-6'd8+x_left]; //left up
							GRID_n[1][7:0] = DATA_TABLE[y_up-6'd8+x]; //right up
							GRID_n[2][7:0] = DATA_TABLE[y_down-6'd8+x_left]; //left down
							GRID_n[3][7:0] = DATA_TABLE[y_down-6'd8+x]; //right down
							for(i=0; i<=3; i=i+1) GRID_n[i][9:8] = 2'd0; 
						end
					end
					_down:
					begin
						if(y == 7'd7) y_n = y; // y can't larger than 7
						else begin
							y_n = y + 7'd1;
							GRID_n[0][7:0] = DATA_TABLE[y_up+6'd8+x_left]; //left up
							GRID_n[1][7:0] = DATA_TABLE[y_up+6'd8+x]; //right up
							GRID_n[2][7:0] = DATA_TABLE[y_down+6'd8+x_left]; //left down
							GRID_n[3][7:0] = DATA_TABLE[y_down+6'd8+x]; //right down
							for(i=0; i<=3; i=i+1) GRID_n[i][9:8] = 2'd0;
						end
					end
					_left:
					begin
						if(x == 7'd1) x_n = x; //x can't smaller than 1
						else begin
							x_n = x - 7'd1; 
							GRID_n[0][7:0] = DATA_TABLE[y_up+x_left-6'd1]; //left up
							GRID_n[1][7:0] = DATA_TABLE[y_up+x-6'd1]; //right up
							GRID_n[2][7:0] = DATA_TABLE[y_down+x_left-6'd1]; //left down
							GRID_n[3][7:0] = DATA_TABLE[y_down+x-6'd1]; //right down
							for(i=0; i<=3; i=i+1) GRID_n[i][9:8] = 2'd0;
						end
					end
					_right:
					begin
						if(x == 7'd7) x_n = x; //x can't larger than 7
						else begin
							x_n = x + 7'd1;
							GRID_n[0][7:0] = DATA_TABLE[y_up+x_left+6'd1]; //left up
							GRID_n[1][7:0] = DATA_TABLE[y_up+x+6'd1]; //right up
							GRID_n[2][7:0] = DATA_TABLE[y_down+x_left+6'd1]; //left down
							GRID_n[3][7:0] = DATA_TABLE[y_down+x+6'd1]; //right down
							for(i=0; i<=3; i=i+1) GRID_n[i][9:8] = 2'd0;
						end
					end
					_avg:
					begin
						GRID_n[0][7:0] = avg_num;
						GRID_n[1][7:0] = avg_num;
						GRID_n[2][7:0] = avg_num;
						GRID_n[3][7:0] = avg_num;
					end
					_m_x:
					begin
						GRID_n[0] = GRID[2];
						GRID_n[1] = GRID[3];
						GRID_n[2] = GRID[0];
						GRID_n[3] = GRID[1];
					end
					_m_y:
					begin
						GRID_n[0] = GRID[1];
						GRID_n[1] = GRID[0];
						GRID_n[2] = GRID[3];
						GRID_n[3] = GRID[2];
					end
					default:
					begin
						for(i=0; i<=3; i =i+1) GRID_n[i] = GRID[i];
						x_n = x;
						y_n = y;
					end
				endcase
			end
		end
		WAIT:
		begin
			state_ctrl_n = WRITE;
			counter_n = 7'd1;
		end
		WRITE:
		begin
			if(counter == 7'd64) begin
				state_ctrl_n = CMD;
				counter_n = 7'd0;
			end
			else begin
				state_ctrl_n = WRITE;
				counter_n = counter + 7'd1;
			end
		end
		default:
		begin
			state_ctrl_n = state_ctrl;
			counter_n = counter;
		end
	endcase
end

always @(negedge clk) begin
	if (loading) begin
		IROM_EN = 1'd0;
	end
	else begin
		IROM_EN = 1'd1;
	end
end
always @(negedge clk) begin
	if (writing) begin
		IRB_RW <= 1'd0;
	end
	else  begin
		IRB_RW <= 1'd1;
	end
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		// reset
		//IROM_EN <= 1'd0;
		IROM_A <= 6'd0;
		//_IROM_Q <= 8'd0;
		//IRB_RW <= 1'd1;
		IRB_D <= 8'd0;
		IRB_A <= 6'd0;
		busy <= 1'd1;
		done <= 1'd0;
		_cmd <= 3'd0;
		_cmd_valid <= 1'd0;

		//state
		state_ctrl <= LOAD_IMG;
		counter <= 7'b1111110;

		for(i=0; i<=63; i=i+1) DATA_TABLE[i] <= 8'd0;
		for(i=0; i<=3; i=i+1) GRID[i] <= 10'd0;

		x <= 6'd4;
		y <= 6'd4;
		
	end
	else begin
		//IROM_EN <= IROM_EN_n;
		IROM_A <= IROM_A_n;
		//_IROM_Q <= IROM_Q;
		//IRB_RW <= IRB_RW_n;
		IRB_D <= IRB_D_n;
		IRB_A <= IRB_A_n;
		busy <= busy_n;
		done <= done_n;
		_cmd <= cmd;
		_cmd_valid <= cmd_valid;

		//state
		state_ctrl <= state_ctrl_n;
		counter <= counter_n;

		for(i=0; i<=63; i=i+1) DATA_TABLE[i] <= DATA_TABLE_nxt[i];
		for(i=0; i<=3; i=i+1) GRID[i] <= GRID_n[i];

		x <= x_n;
		y <= y_n;
	end
end

endmodule