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
output busy;
output done;

//parameters for Image Display Controller
localparam IDLE = 3'd0;
localparam LOAD_IMG = 3'd1;
localparam WAIT_CMD = 3'd2;
localparam WRITE = 3'd3;
localparam DONE = 3'd4;

//parameters for cmd states
localparam NON_CMD = 3'd0;
localparam SHIFT_UP = 3'd1;
localparam SHIFT_DOWN = 3'd2;
localparam SHIFT_LEFT = 3'd3;
localparam SHIFT_RIGHT = 3'd4;
localparam AVERAGE = 3'd5;
localparam MIRROR_X = 3'd6;
localparam MIRROR_Y = 3'd7;

//initial coordinator at (4,4) 
localparam x_origin = 4'd4;
localparam y_origin = 4'd4;

//assign neg clk
wire negclk;
assign negclk = ~clk;

//reg wire cmd_valid 
reg cmd_valid_r;
wire cmd_valid_nxt;

//reg wire IROM_Q
reg [7:0] IROM_Q_r;
wire [7:0] IROM_Q_nxt;

//state next state
reg [2:0] state_ctrl, state_ctrl_nxt; 
reg [2:0] state_cmd; 
wire [2:0] state_cmd_nxt;
//image data 64 * 8bits reg wire array
reg [7:0] DATA_TABLE [0:63];
reg [7:0] DATA_TABLE_nxt [0:63];
 
//reg for output
reg [7:0] IRB_D_r, IRB_D_nxt;
reg [6:0] IRB_A_r, IRB_A_nxt;
reg [6:0] IROM_A_r, IROM_A_nxt;
reg IROM_EN_r, IROM_EN_nxt;
reg done_r, done_nxt;
reg busy_r, busy_nxt;
reg IRB_RW_r, IRB_RW_nxt;

//reg for operation point
reg [5:0] x, x_nxt;
reg [5:0] y, y_nxt;
//wire x,y 
wire [5:0] y_up, y_down;
wire [5:0] x_left;
 
//reg for the 4x4 grid ready to be changed left->right top->down 0~3
reg [11:0] GRID [0:3]; 
reg [11:0] GRID_nxt [0:3];
//wire averge number
wire [7:0] avg_num;
wire [9:0] avg_num_tmp; //10bits

//assign cmd valid
assign cmd_valid_nxt = cmd_valid;

//assign coordinator
assign y_up = (y - 6'd1) << 3; //(y-1)*8
assign y_down =  y << 3; //y*8
assign x_left = x - 6'd1;

//assign average number of GRID
assign avg_num_tmp = ((GRID[0]+GRID[1]+GRID[2]+GRID[3]) >> 2); 
assign avg_num = avg_num_tmp[7:0];

//assign output
//assign IRB_D = IRB_D_r;
//assign IRB_A = IRB_A_r[5:0];
//assign IROM_A = IROM_A_r[5:0];
//assign IROM_EN = IROM_EN_r;
assign done = done_r;
assign busy = busy_r;
//assign IRB_RW = IRB_RW_r;


//assign input
assign IROM_Q_nxt = IROM_Q ;
assign state_cmd_nxt = cmd;

//combinational circuit for output reg
always @ (*) begin
	IRB_D = IRB_D_r;
	IRB_A = IRB_A_r[5:0];
	IROM_A = IROM_A_r[5:0];
	IROM_EN = IROM_EN_r;
	IRB_RW = IRB_RW_r;
end

//combinational circuit for ctrl: 
//regs will be change: state_ctrl_nxt state state_cmd_nxt IROM_EN_nxt IRB_D_r IRB_A_nxt done_nxt busy_nxt
always @ (*) begin

	state_ctrl_nxt = state_ctrl;
	IRB_A_nxt = IRB_A_r;
	IRB_D_nxt = IRB_D_r;
	IRB_RW_nxt = IRB_RW_r;
	done_nxt = done_r;
	busy_nxt = busy_r;
	IROM_EN_nxt = IROM_EN_r;

	case(state_ctrl)
		IDLE:
		begin
			IROM_EN_nxt = 1'd0;
			state_ctrl_nxt = LOAD_IMG;
		end 
		LOAD_IMG:
		begin
			if(IROM_A_r == 7'd65)begin //data load completed
				state_ctrl_nxt = WAIT_CMD;
				busy_nxt = 1'd0;
				IROM_EN_nxt = 1'd1; // close IROM
			end
		end
		WAIT_CMD:
		begin
			if(state_cmd == 3'd0) begin
				state_ctrl_nxt = WRITE;
				IRB_D_nxt = DATA_TABLE[IRB_A_r];
				IRB_RW_nxt = 1'd0; //rdy to write
			end
			if(cmd_valid && !busy_r)begin
				busy_nxt = 1'd1;
			end
			else busy_nxt = 1'd0;
		end
		WRITE:
		begin
			//state_ctrl_nxt = WRITE;
			//if IRB_RW is low: write data to IRB 	
			if(IRB_A_r != 7'd63) begin //write data for 64 address of IRB
				IRB_D_nxt = DATA_TABLE[IRB_A_r + 7'd1];
				IRB_A_nxt = IRB_A_r + 7'd1; 
			end
			else begin
				IRB_D_nxt = DATA_TABLE[IRB_A_r]; //for 6'd63th element
				done_nxt = 1'd1; // IRB_A_r == 63 -> write finished	
				state_ctrl_nxt = DONE;
				busy_nxt = 1'd0;
				IRB_RW_nxt = 1'd1;
			end
		
		end
		DONE:
		begin
			//set next state to IDLE && set nxt reg to 0(ready for the nxt cmd sequence) 
			done_nxt = 1'd0;
			IRB_A_nxt = 7'd0;
			IRB_D_nxt = 8'd0;
		end
		default:
		begin
			state_ctrl_nxt = state_ctrl;
			IRB_A_nxt = IRB_A_r;
			IRB_D_nxt = IRB_D_r;
			IRB_RW_nxt =IRB_RW_r;
			done_nxt = done_r;
		end
	endcase
end

//combinational circuit for cmd operation and load data (every thing will change data table)
//regs will be changed: DATA_TABLE_nxt IROM_A_nxt GRID_nxt GRID_tmp_nxt y_nxt x_nxt 
integer j;
always @ (*) begin
	//reg array 
	for(j=0; j<=63; j=j+1)begin
		DATA_TABLE_nxt[j] = DATA_TABLE[j];
	end
	for(j=0; j<=3; j=j+1)begin
		GRID_nxt[j] = GRID[j];
	end
	//reg
	x_nxt = x;
	y_nxt = y;
	IROM_A_nxt = IROM_A_r;

	case(state_ctrl)
		LOAD_IMG:
		begin
			if(IROM_A_r <= 7'd64) begin //start loading data from IROM
				if(IROM_A_r != 7'd0) DATA_TABLE_nxt [IROM_A_r - 7'd1] = IROM_Q_r;
				else DATA_TABLE_nxt[IROM_A_r] = IROM_Q_r;
				IROM_A_nxt = IROM_A_r + 7'd1;
			end 
			else begin //data loading complete	
		 		GRID_nxt[0] = DATA_TABLE[y_up+x_left]; //left up
				GRID_nxt[1] = DATA_TABLE[y_up+x]; //right up
				GRID_nxt[2] = DATA_TABLE[y_down+x_left]; //left down
				GRID_nxt[3] = DATA_TABLE[y_down+x]; //right down 
			end
		end
		WAIT_CMD:
		begin
			//set GRID values
			for(j=0; j<=3; j=j+1) begin
				GRID_nxt[j] = GRID[j];
				DATA_TABLE_nxt[y_up+x_left] = DATA_TABLE[y_up+x_left];
				DATA_TABLE_nxt[y_up+x] = DATA_TABLE[y_up+x];
				DATA_TABLE_nxt[y_down+x_left] = DATA_TABLE[y_down+x_left];
				DATA_TABLE_nxt[y_down+x] = DATA_TABLE[y_down+x];
			end

			if(cmd_valid && !busy_r) begin
				case(state_cmd)
				SHIFT_UP:
				begin
					if(y == 7'd1) y_nxt = y; // y can't smaller than 1
					else begin
						y_nxt = y - 7'd1;
						GRID_nxt[0][7:0] = DATA_TABLE[y_up-6'd8+x_left]; //left up
						GRID_nxt[1][7:0] = DATA_TABLE[y_up-6'd8+x]; //right up
						GRID_nxt[2][7:0] = DATA_TABLE[y_down-6'd8+x_left]; //left down
						GRID_nxt[3][7:0] = DATA_TABLE[y_down-6'd8+x]; //right down
						for(j=0; j<=4; j=j+1) GRID_nxt[j][9:8] = 2'd0; 
					end
				end
				SHIFT_DOWN:
				begin
					if(y == 7'd7) y_nxt = y; // y can't larger than 7
					else begin
						y_nxt = y + 7'd1;
						GRID_nxt[0][7:0] = DATA_TABLE[y_up+6'd8+x_left]; //left up
						GRID_nxt[1][7:0] = DATA_TABLE[y_up+6'd8+x]; //right up
						GRID_nxt[2][7:0] = DATA_TABLE[y_down+6'd8+x_left]; //left down
						GRID_nxt[3][7:0] = DATA_TABLE[y_down+6'd8+x]; //right down
						for(j=0; j<=4; j=j+1) GRID_nxt[j][9:8] = 2'd0;
					end
				end
				SHIFT_LEFT:
				begin
					if(x == 7'd1) x_nxt = x; //x can't smaller than 1
					else begin
						x_nxt = x - 7'd1; 
						GRID_nxt[0][7:0] = DATA_TABLE[y_up+x_left-6'd1]; //left up
						GRID_nxt[1][7:0] = DATA_TABLE[y_up+x-6'd1]; //right up
						GRID_nxt[2][7:0] = DATA_TABLE[y_down+x_left-6'd1]; //left down
						GRID_nxt[3][7:0] = DATA_TABLE[y_down+x-6'd1]; //right down
						for(j=0; j<=4; j=j+1) GRID_nxt[j][9:8] = 2'd0;
					end
				end
				SHIFT_RIGHT:
				begin
					if(x == 7'd7) x_nxt = x; //x can't larger than 7
					else begin
						x_nxt = x + 7'd1;
						GRID_nxt[0][7:0] = DATA_TABLE[y_up+x_left+6'd1]; //left up
						GRID_nxt[1][7:0] = DATA_TABLE[y_up+x+6'd1]; //right up
						GRID_nxt[2][7:0] = DATA_TABLE[y_down+x_left+6'd1]; //left down
						GRID_nxt[3][7:0] = DATA_TABLE[y_down+x+6'd1]; //right down
						for(j=0; j<=4; j=j+1) GRID_nxt[j][9:8] = 2'd0;
					end
				end
				AVERAGE:
				begin
					GRID_nxt[0][7:0] = avg_num;
					GRID_nxt[1][7:0] = avg_num;
					GRID_nxt[2][7:0] = avg_num;
					GRID_nxt[3][7:0] = avg_num;
					DATA_TABLE_nxt[y_up+x_left] = avg_num;
					DATA_TABLE_nxt[y_up+x] =avg_num;
					DATA_TABLE_nxt[y_down+x_left] = avg_num;
					DATA_TABLE_nxt[y_down+x] = avg_num;
				end
				MIRROR_X: //0123->2301
				begin
					GRID_nxt[0] = GRID[2];
					GRID_nxt[1] = GRID[3];
					GRID_nxt[2] = GRID[0];
					GRID_nxt[3] = GRID[1];
					DATA_TABLE_nxt[y_up+x_left] = GRID[2][7:0];
					DATA_TABLE_nxt[y_up+x] = GRID[3][7:0];
					DATA_TABLE_nxt[y_down+x_left] = GRID[0][7:0];
					DATA_TABLE_nxt[y_down+x] = GRID[1][7:0];
				end
				MIRROR_Y: //0123->1032
				begin
					GRID_nxt[0] = GRID[1];
					GRID_nxt[1] = GRID[0];
					GRID_nxt[2] = GRID[3];
					GRID_nxt[3] = GRID[2];
					DATA_TABLE_nxt[y_up+x_left] = GRID[1][7:0];
					DATA_TABLE_nxt[y_up+x] = GRID[0][7:0];
					DATA_TABLE_nxt[y_down+x_left] = GRID[3][7:0];
					DATA_TABLE_nxt[y_down+x] = GRID[2][7:0];
				end
				default:
				begin
					x_nxt = x;
					y_nxt = y;
				end
				endcase
			end
		end
			
		default:
		begin
			//need array default?
			x_nxt = x;
			y_nxt = y;
			IROM_A_nxt = IROM_A_r; 
		end
	endcase
end
//sequential circuit for cmd_valid
integer i; 
always @ (posedge clk or negedge reset) begin
	if(reset) begin
		//reset for ctrl cmd
		state_ctrl <= IDLE;
		state_cmd <= NON_CMD;
		done_r <= 1'd0;
		busy_r <= 1'd1;
		//reset (x,y)
		x <= 6'd4;
		y <= 6'd4;
		//reset DATA_TABLE && GRID to zero (can be trivial?)
		for(i=0; i<=63; i=i+1) DATA_TABLE[i] <= 8'd0;
		for(i=0; i<=3; i=i+1)begin
			GRID[i] <= 10'd0;
			//GRID_tmp[i] <= 8'd0;
 		end
 		//cmd_valid
 		cmd_valid_r <= 1'd0;
	end
	else begin
		state_ctrl <= state_ctrl_nxt;
		state_cmd <= state_cmd_nxt;

		done_r <= done_nxt;
		busy_r <= busy_nxt;
		//reg array
		for(i=0; i<=63; i=i+1)begin
			DATA_TABLE[i] <= DATA_TABLE_nxt[i];
		end
		for(i=0; i<=3; i=i+1)begin
			GRID[i] <= GRID_nxt[i];
		end
		//coordinator
		y <= y_nxt;
		x <= x_nxt;
		//cmd_valid
		cmd_valid_r <= cmd_valid_nxt;
	end
end
//Sequential circuit
integer k; 
always @ (posedge negclk or posedge reset) begin
	if (reset) begin
		//IROM or IRB
		IROM_Q_r <= 8'd0;
		IROM_EN_r <= 1'd1; //close IROM for available data
		IROM_A_r <= 7'd0;
		IRB_A_r <= 7'd0;
		IRB_D_r <= 8'd0;
		IRB_RW_r <= 1'd1;

		//others
		
		// //reset for ctrl cmd
		// state_ctrl <= IDLE;
		// state_cmd <= NON_CMD;
		// done_r <= 1'd0;
		// busy_r <= 1'd1;
		// //reset (x,y)
		// x <= 6'd4;
		// y <= 6'd4;
		// //reset DATA_TABLE && GRID to zero (can be trivial?)
		// for(i=0; i<=63; i=i+1) DATA_TABLE[i] <= 8'd0;
		// for(i=0; i<=3; i=i+1)begin
		// 	GRID[i] <= 10'd0;
		// 	//GRID_tmp[i] <= 8'd0;
 	// 	end
 	// 	//cmd_valid
 	// 	cmd_valid_r <= 1'd0;
	end

	else begin
		//IROM or IRB
		IROM_Q_r <= IROM_Q_nxt;
		IROM_EN_r <= IROM_EN_nxt;
		IROM_A_r <= IROM_A_nxt;
		IRB_A_r <= IRB_A_nxt;
		IRB_D_r <= IRB_D_nxt;
		IRB_RW_r <= IRB_RW_nxt;

		//others
		// state_ctrl <= state_ctrl_nxt;
		// state_cmd <= state_cmd_nxt;

		// done_r <= done_nxt;
		// busy_r <= busy_nxt;
		// //reg array
		// for(i=0; i<=63; i=i+1)begin
		// 	DATA_TABLE[i] <= DATA_TABLE_nxt[i];
		// end
		// for(i=0; i<=3; i=i+1)begin
		// 	GRID[i] <= GRID_nxt[i];
		// end
		// //coordinator
		// y <= y_nxt;
		// x <= x_nxt;
		// //cmd_valid
		// cmd_valid_r <= cmd_valid_nxt;
	end
end

endmodule

