
`timescale 1ns/10ps

module  CONV(
	input		clk,
	input		reset,
	output	reg	busy,	//set low after all processes are done.
	input		ready,	
			
	output	reg	[11:0] iaddr,
	input	wire	[19:0] idata, //4 bits MSB + 16 bits LSB (signed)
	
	output	reg 	cwr,
	output	reg 	[11:0] caddr_wr,
	output	reg 	[19:0] cdata_wr,
	
	output		 crd, 
	output	 	[11:0] caddr_rd,
	input	 	[19:0] cdata_rd,
	
	output	reg	[2:0] csel //rw to which MEM 0:NONE 1:L0K0 2:L0k0 3:L1K0 4:L1k0 5:L2
	);


//assign useless output wire 
assign crd = 1'd0;
assign caddr_rd = 12'd0;

//states 
localparam IDLE = 1'd0;		//initial state
localparam WORK = 1'd1;		//processing state, busy set to high	

//states for loading and processing data: due to padding
//not useless
localparam FIRSTROW = 2'd0;   
localparam INTERROW = 2'd1;
localparam LASTROW  = 2'd2;
localparam FIRSTCOLUMN = 2'd0;
localparam INTERCOLUMN = 2'd1;
localparam LASTCOLUMN = 2'd2;

//read memory
localparam READ_IDLE = 3'd0;
localparam READ_INIT = 3'd1;
localparam READ_UP = 3'd2;
localparam READ_DOWN= 3'd3;
localparam READ_WAIT = 3'd4;

//states for conv order: due to 4x4 tmp grid -> during conv and output
localparam FIRST_TYPE = 2'd0;
localparam SECOND_TYPE = 2'd1;
localparam FOURTH_TYPE = 2'd2;

//STATES for calculation
localparam CAL_IDLE = 3'd0;
localparam CAL_LOAD = 3'd1;
localparam CAL_0 = 3'd2;
localparam CAL_1 = 3'd3;
localparam CAL_WAIT = 3'd4;

//maxpool: every four conv do one maxpool
localparam MAXPOOL_IDLE = 2'd0; 
localparam MAXPOOL_FIRST_STEP = 2'd1; //2 pairs comparison
localparam MAXPOOL_LAST_STEP = 2'd2; //one pair comparison and output to layer 1(maxpool) and 2(flatten)

//output states
localparam OUT_IDLE = 3'd0;
localparam OUT_LAYER_0_KERNEL_0 = 3'd1;
localparam OUT_LAYER_0_KERNEL_1 = 3'd2;
localparam OUT_LAYER_1_KERNEL_0 = 3'd3;
localparam OUT_LAYER_1_KERNEL_1 = 3'd4;
localparam OUT_LAYER_2_KERNEL_0 = 3'd5;
localparam OUT_LAYER_2_KERNEL_1 = 3'd6;

//counter states
localparam COUNTER_0 = 2'd0;
localparam COUNTER_1 = 2'd1;
localparam COUNTER_2 = 2'd2;
localparam COUNTER_3 = 2'd3;

//reg wire for state
reg state_process;
reg state_process_n;
reg [1:0] state_conv, state_row,   state_maxpool, state_column,  state_counter;
reg [1:0] state_conv_n, state_row_n,   state_maxpool_n, state_column_n,  state_counter_n;
reg [2:0] state_read, state_output, state_calculate;
reg [2:0] state_read_n, state_output_n, state_calculate_n;

//temp memory
//for convolution tmp 3x3 grid memory
reg signed [39:0] convolution1_0[0:8], convolution2_0[0:8], convolution3_0[0:8], convolution4_0[0:8], convolution1_0_n[0:8], convolution2_0_n[0:8], convolution3_0_n[0:8], convolution4_0_n [0:8];    
reg signed [39:0] convolution1_1[0:8], convolution2_1[0:8], convolution3_1[0:8], convolution4_1[0:8], convolution1_1_n[0:8], convolution2_1_n[0:8], convolution3_1_n[0:8], convolution4_1_n [0:8];    
//convolution result for kernel0 and kernel1
reg signed [19:0] kernel0[0:3], kernel1[0:3], kernel0_n[0:3], kernel1_n [0:3];
//temp result for maxPooling
reg signed [19:0] interPooling0[0:1], interPooling1[0:1], interPooling0_n[0:1], interPooling1_n [0:1];
reg signed [19:0] maxPooling0, maxPooling1, maxPooling0_n, maxPooling1_n;


//TABLE && GRID
//memory for reading data
reg signed [19:0] TABLE [0:255];
reg signed [19:0] TABLE_n [0:255];
//memory for remember 4 3x3 working grid
reg signed [19:0] Grid [0:15];		
reg signed [19:0] Grid_n [0:15];

//counter
reg [3:0] cal_counter;
reg [3:0] cal_counter_n;
reg [4:0] out_column_counter, out_column_counter_n;
reg [5:0] column_counter, row_counter;
reg [5:0] column_counter_n, row_counter_n;
reg [11:0] output_counter, output_counter_n;
reg [9:0] maxpool_counter, maxpool_counter_n;
reg [10:0] flatten_counter, flatten_counter_n;

//output wire
reg busy_n, cwr_n; 
reg [11:0] iaddr_n, caddr_wr_n;
reg signed [19:0] cdata_wr_n;
reg [2:0] csel_n; 

//wire for not yet relu and rounding
wire signed [43:0] k0_0, k0_1, k0_2, k0_3;
wire signed [43:0] k1_0, k1_1, k1_2, k1_3;
wire signed [41:0] k0_0_tmp1, k0_1_tmp1, k0_2_tmp1, k0_3_tmp1, k1_0_tmp1, k1_1_tmp1, k1_2_tmp1, k1_3_tmp1;
wire signed [42:0] k0_0_tmp2, k0_1_tmp2, k0_2_tmp2, k0_3_tmp2, k1_0_tmp2, k1_1_tmp2, k1_2_tmp2, k1_3_tmp2;

assign k0_0_tmp1 = convolution1_0[0] + convolution1_0[1] + convolution1_0[2] + convolution1_0[3];
assign k0_0_tmp2 = k0_0_tmp1 + convolution1_0[4] + convolution1_0[5] + convolution1_0[6]; 
assign k0_0 = k0_0_tmp2 + convolution1_0[7] + convolution1_0[8] + $signed(44'h00013100000);

assign k0_1_tmp1 = convolution2_0[0] + convolution2_0[1] + convolution2_0[2] + convolution2_0[3]; 
assign k0_1_tmp2 = k0_1_tmp1 + convolution2_0[4] + convolution2_0[5] + convolution2_0[6];
assign k0_1 = k0_1_tmp2 + convolution2_0[7] + convolution2_0[8] + $signed(44'h00013100000); 

assign k0_2_tmp1 = convolution3_0[0] + convolution3_0[1] + convolution3_0[2] + convolution3_0[3]; 
assign k0_2_tmp2 = k0_2_tmp1 + convolution3_0[4] + convolution3_0[5] + convolution3_0[6];
assign k0_2 = k0_2_tmp2 + convolution3_0[7] + convolution3_0[8] + $signed(44'h00013100000);

assign k0_3_tmp1 = convolution4_0[0] + convolution4_0[1] + convolution4_0[2] + convolution4_0[3]; 
assign k0_3_tmp2 = k0_3_tmp1 + convolution4_0[4] + convolution4_0[5] + convolution4_0[6]; 
assign k0_3 = k0_3_tmp2 + convolution4_0[7] + convolution4_0[8] + $signed(44'h00013100000);

assign k1_0_tmp1 = convolution1_1[0] + convolution1_1[1] + convolution1_1[2] + convolution1_1[3]; 
assign k1_0_tmp2 = k1_0_tmp1 + convolution1_1[4] + convolution1_1[5] + convolution1_1[6];
assign k1_0 = k1_0_tmp2 + convolution1_1[7] + convolution1_1[8] + $signed(44'hFFF72950000);

assign k1_1_tmp1 = convolution2_1[0] + convolution2_1[1] + convolution2_1[2] + convolution2_1[3]; 
assign k1_1_tmp2 = k1_1_tmp1 + convolution2_1[4] + convolution2_1[5] + convolution2_1[6];
assign k1_1 = k1_1_tmp2 + convolution2_1[7] + convolution2_1[8] + $signed(44'hFFF72950000);

assign k1_2_tmp1 = convolution3_1[0] + convolution3_1[1] + convolution3_1[2] + convolution3_1[3]; 
assign k1_2_tmp2 = k1_2_tmp1 + convolution3_1[4] + convolution3_1[5] + convolution3_1[6]; 
assign k1_2 = k1_2_tmp2 + convolution3_1[7] + convolution3_1[8] + $signed(44'hFFF72950000);

assign k1_3_tmp1 = convolution4_1[0] + convolution4_1[1] + convolution4_1[2] + convolution4_1[3]; 
assign k1_3_tmp2 = k1_3_tmp1 + convolution4_1[4] + convolution4_1[5] + convolution4_1[6];
assign k1_3 = k1_3_tmp2 + convolution4_1[7] + convolution4_1[8] + $signed(44'hFFF72950000);

// For overall state transition
always @ (*) begin
	busy_n = busy;
	state_process_n = state_process;

	case(state_process)
		IDLE:
		begin	
			if (ready == 1'd1)
			begin
				busy_n = 1'd1;
				state_process_n = WORK;
			end
		end
		WORK:
		begin
			if ( state_output == OUT_LAYER_2_KERNEL_1 && flatten_counter == 11'd0)
			begin
				busy_n = 1'd0;
				state_process_n = IDLE;
			end
		end
	endcase
end

integer i;
//wrong
//For read state
always @ (*) begin
	state_read_n = state_read;
	iaddr_n = iaddr;	

	for(i=0;i<256;i=i+1) TABLE_n[i]=TABLE[i];
	case(state_read)
		READ_IDLE:
		begin
			if (ready == 1'd1) state_read_n = READ_INIT;
		end
		READ_INIT:
		begin
			TABLE_n[iaddr[7:0]] = idata;
			if (iaddr[7] == 1) //read to third row
			begin
				if(iaddr == 12'd191) //finished third row
				begin
					iaddr_n = iaddr + 12'd1;
					state_read_n = READ_WAIT;
				end
				else iaddr_n = iaddr - 12'd127; //back to first row
			end
			else iaddr_n = iaddr + 12'd64; //read next row
		end
		READ_UP:
		begin
			if (iaddr[1:0] == 2'b11)
			begin
				state_read_n = READ_DOWN;
				iaddr_n = iaddr + 12'd61;
			end
			else iaddr_n = iaddr + 12'd1;
			TABLE_n[iaddr[7:0]] = idata;
		end
		READ_DOWN:
		begin
			TABLE_n[iaddr[7:0]] = idata;
			if (iaddr[5:0] == 6'd63)
			begin
				state_read_n = READ_WAIT;
				iaddr_n = iaddr + 12'd1;
			end
			else if (iaddr[1:0] == 2'b11)
			begin
				state_read_n = READ_UP;
				iaddr_n = iaddr - 12'd63;
			end
			else iaddr_n = iaddr + 12'd1;
		end
		READ_WAIT:
			if (column_counter == 6'd60)
			begin
				state_read_n = READ_UP; //when convolution reach last block, restart reading
			end
			else if(iaddr == 12'd0) state_read_n = READ_IDLE;  
	endcase
end

//For row state 
always @ (*) begin
	state_row_n = state_row;
	row_counter_n = row_counter;
	state_conv_n = state_conv;
	case(state_row)
		FIRSTROW:
		begin
			if (column_counter == 6'd62 && state_output == OUT_LAYER_1_KERNEL_0 ) 
			begin
				state_row_n = INTERROW;	
				row_counter_n = row_counter+6'd2;
				state_conv_n = SECOND_TYPE;
			end
		end
		INTERROW:
		begin
			if ( column_counter == 6'd62 && state_output == OUT_LAYER_1_KERNEL_0 )
			begin
				row_counter_n = row_counter + 6'd2;
				if ( row_counter == 6'd60) state_row_n = LASTROW;
				if (state_conv == SECOND_TYPE) state_conv_n = FOURTH_TYPE;
				else if (state_conv == FOURTH_TYPE) state_conv_n = SECOND_TYPE;
			end
		end
		LASTROW:
		begin
			if (column_counter == 6'd62 && state_output == OUT_LAYER_2_KERNEL_1) 
			begin
				state_row_n = FIRSTROW;
				row_counter_n = 6'd0;
				state_conv_n = FIRST_TYPE;
			end
		end
	endcase	
end


//For column state 
always @ (*) begin
	state_column_n = state_column;

	case(state_column)
		FIRSTCOLUMN:
		begin
			if (state_calculate == CAL_LOAD) state_column_n = INTERCOLUMN;
		end
		INTERCOLUMN:
		begin
			if (column_counter == 6'd60) state_column_n = LASTCOLUMN;
		end
		LASTCOLUMN:
		begin
			if (column_counter == 6'd62) state_column_n = FIRSTCOLUMN;
		end
	endcase
end

//For covolution state
always @ (*) begin
for(i=0;i<9;i=i+1)
begin
	convolution1_0_n[i] = convolution1_0[i];
	convolution2_0_n[i] = convolution2_0[i];
	convolution3_0_n[i] = convolution3_0[i];
	convolution4_0_n[i] = convolution4_0[i];
	convolution1_1_n[i] = convolution1_1[i];
	convolution2_1_n[i] = convolution2_1[i];
	convolution3_1_n[i] = convolution3_1[i];
	convolution4_1_n[i] = convolution4_1[i];
end
	case(state_conv) //only deal with CAL_0 now
		FIRST_TYPE:
		begin   
			case(state_calculate)
				CAL_0: //grid with four 3x3 blocks product with kernel0 and kernel1
				begin
					convolution1_0_n[0] = Grid[0]*$signed(20'h0A89E);
					convolution1_0_n[1] = Grid[1]*$signed(20'h092D5);
					convolution1_0_n[2] = Grid[2]*$signed(20'h06D43);
					convolution1_0_n[3] = Grid[4]*$signed(20'h01004);
					convolution1_0_n[4] = Grid[5]*$signed(20'hF8F71);
					convolution1_0_n[5] = Grid[6]*$signed(20'hF6E54);
					convolution1_0_n[6] = Grid[8]*$signed(20'hFA6D7);
					convolution1_0_n[7] = Grid[9]*$signed(20'hFC834);
					convolution1_0_n[8] = Grid[10]*$signed(20'hFAC19);
					
					convolution2_0_n[0] = Grid[1]*$signed(20'h0A89E);
					convolution2_0_n[1] = Grid[2]*$signed(20'h092D5);
					convolution2_0_n[2] = Grid[3]*$signed(20'h06D43);
					convolution2_0_n[3] = Grid[5]*$signed(20'h01004);
					convolution2_0_n[4] = Grid[6]*$signed(20'hF8F71);
					convolution2_0_n[5] = Grid[7]*$signed(20'hF6E54);
					convolution2_0_n[6] = Grid[9]*$signed(20'hFA6D7);
					convolution2_0_n[7] = Grid[10]*$signed(20'hFC834);
					convolution2_0_n[8] = Grid[11]*$signed(20'hFAC19);

					convolution3_0_n[0] = Grid[4]*$signed(20'h0A89E);
					convolution3_0_n[1] = Grid[5]*$signed(20'h092D5);
					convolution3_0_n[2] = Grid[6]*$signed(20'h06D43);
					convolution3_0_n[3] = Grid[8]*$signed(20'h01004);
					convolution3_0_n[4] = Grid[9]*$signed(20'hF8F71);
					convolution3_0_n[5] = Grid[10]*$signed(20'hF6E54);
					convolution3_0_n[6] = Grid[12]*$signed(20'hFA6D7);
					convolution3_0_n[7] = Grid[13]*$signed(20'hFC834);
					convolution3_0_n[8] = Grid[14]*$signed(20'hFAC19);

					convolution4_0_n[0] = Grid[5]*$signed(20'h0A89E);
					convolution4_0_n[1] = Grid[6]*$signed(20'h092D5);
					convolution4_0_n[2] = Grid[7]*$signed(20'h06D43);
					convolution4_0_n[3] = Grid[9]*$signed(20'h01004);
					convolution4_0_n[4] = Grid[10]*$signed(20'hF8F71);
					convolution4_0_n[5] = Grid[11]*$signed(20'hF6E54);
					convolution4_0_n[6] = Grid[13]*$signed(20'hFA6D7);
					convolution4_0_n[7] = Grid[14]*$signed(20'hFC834);
					convolution4_0_n[8] = Grid[15]*$signed(20'hFAC19);

					convolution1_1_n[0] = Grid[0]*$signed(20'hFDB55);
					convolution1_1_n[1] = Grid[1]*$signed(20'h02992);
					convolution1_1_n[2] = Grid[2]*$signed(20'hFC994);
					convolution1_1_n[3] = Grid[4]*$signed(20'h050FD);
					convolution1_1_n[4] = Grid[5]*$signed(20'h02F20);
					convolution1_1_n[5] = Grid[6]*$signed(20'h0202D);
					convolution1_1_n[6] = Grid[8]*$signed(20'h03BD7);
					convolution1_1_n[7] = Grid[9]*$signed(20'hFD369);
					convolution1_1_n[8] = Grid[10]*$signed(20'h05E68);

					convolution2_1_n[0] = Grid[1]*$signed(20'hFDB55);
					convolution2_1_n[1] = Grid[2]*$signed(20'h02992);
					convolution2_1_n[2] = Grid[3]*$signed(20'hFC994);
					convolution2_1_n[3] = Grid[5]*$signed(20'h050FD);
					convolution2_1_n[4] = Grid[6]*$signed(20'h02F20);
					convolution2_1_n[5] = Grid[7]*$signed(20'h0202D);
					convolution2_1_n[6] = Grid[9]*$signed(20'h03BD7);
					convolution2_1_n[7] = Grid[10]*$signed(20'hFD369);
					convolution2_1_n[8] = Grid[11]*$signed(20'h05E68);

					convolution3_1_n[0] = Grid[4]*$signed(20'hFDB55);
					convolution3_1_n[1] = Grid[5]*$signed(20'h02992);
					convolution3_1_n[2] = Grid[6]*$signed(20'hFC994);
					convolution3_1_n[3] = Grid[8]*$signed(20'h050FD);
					convolution3_1_n[4] = Grid[9]*$signed(20'h02F20);
					convolution3_1_n[5] = Grid[10]*$signed(20'h0202D);
					convolution3_1_n[6] = Grid[12]*$signed(20'h03BD7);
					convolution3_1_n[7] = Grid[13]*$signed(20'hFD369);
					convolution3_1_n[8] = Grid[14]*$signed(20'h05E68);

					convolution4_1_n[0] = Grid[5]*$signed(20'hFDB55);
					convolution4_1_n[1] = Grid[6]*$signed(20'h02992);
					convolution4_1_n[2] = Grid[7]*$signed(20'hFC994);
					convolution4_1_n[3] = Grid[9]*$signed(20'h050FD);
					convolution4_1_n[4] = Grid[10]*$signed(20'h02F20);
					convolution4_1_n[5] = Grid[11]*$signed(20'h0202D);
					convolution4_1_n[6] = Grid[13]*$signed(20'h03BD7);
					convolution4_1_n[7] = Grid[14]*$signed(20'hFD369);
					convolution4_1_n[8] = Grid[15]*$signed(20'h05E68);
				end
			endcase
		end
		SECOND_TYPE:
		begin	
			case(state_calculate)
				CAL_0:
				begin
					convolution1_0_n[0] = Grid[4]*$signed(20'h0A89E);
					convolution1_0_n[1] = Grid[5]*$signed(20'h092D5);
					convolution1_0_n[2] = Grid[6]*$signed(20'h06D43);
					convolution1_0_n[3] = Grid[8]*$signed(20'h01004);
					convolution1_0_n[4] = Grid[9]*$signed(20'hF8F71);
					convolution1_0_n[5] = Grid[10]*$signed(20'hF6E54);
					convolution1_0_n[6] = Grid[12]*$signed(20'hFA6D7);
					convolution1_0_n[7] = Grid[13]*$signed(20'hFC834);
					convolution1_0_n[8] = Grid[14]*$signed(20'hFAC19);

					convolution2_0_n[0] = Grid[5]*$signed(20'h0A89E);
					convolution2_0_n[1] = Grid[6]*$signed(20'h092D5);
					convolution2_0_n[2] = Grid[7]*$signed(20'h06D43);
					convolution2_0_n[3] = Grid[9]*$signed(20'h01004);
					convolution2_0_n[4] = Grid[10]*$signed(20'hF8F71);
					convolution2_0_n[5] = Grid[11]*$signed(20'hF6E54);
					convolution2_0_n[6] = Grid[13]*$signed(20'hFA6D7);
					convolution2_0_n[7] = Grid[14]*$signed(20'hFC834);
					convolution2_0_n[8] = Grid[15]*$signed(20'hFAC19);

					convolution3_0_n[0] = Grid[8]*$signed(20'h0A89E);
					convolution3_0_n[1] = Grid[9]*$signed(20'h092D5);
					convolution3_0_n[2] = Grid[10]*$signed(20'h06D43);
					convolution3_0_n[3] = Grid[12]*$signed(20'h01004);
					convolution3_0_n[4] = Grid[13]*$signed(20'hF8F71);
					convolution3_0_n[5] = Grid[14]*$signed(20'hF6E54);
					convolution3_0_n[6] = Grid[0]*$signed(20'hFA6D7);
					convolution3_0_n[7] = Grid[1]*$signed(20'hFC834);
					convolution3_0_n[8] = Grid[2]*$signed(20'hFAC19);

					convolution4_0_n[0] = Grid[9]*$signed(20'h0A89E);
					convolution4_0_n[1] = Grid[10]*$signed(20'h092D5);
					convolution4_0_n[2] = Grid[11]*$signed(20'h06D43);
					convolution4_0_n[3] = Grid[13]*$signed(20'h01004);
					convolution4_0_n[4] = Grid[14]*$signed(20'hF8F71);
					convolution4_0_n[5] = Grid[15]*$signed(20'hF6E54);
					convolution4_0_n[6] = Grid[1]*$signed(20'hFA6D7);
					convolution4_0_n[7] = Grid[2]*$signed(20'hFC834);
					convolution4_0_n[8] = Grid[3]*$signed(20'hFAC19);

					convolution1_1_n[0] = Grid[4]*$signed(20'hFDB55);
					convolution1_1_n[1] = Grid[5]*$signed(20'h02992);
					convolution1_1_n[2] = Grid[6]*$signed(20'hFC994);
					convolution1_1_n[3] = Grid[8]*$signed(20'h050FD);
					convolution1_1_n[4] = Grid[9]*$signed(20'h02F20);
					convolution1_1_n[5] = Grid[10]*$signed(20'h0202D);
					convolution1_1_n[6] = Grid[12]*$signed(20'h03BD7);
					convolution1_1_n[7] = Grid[13]*$signed(20'hFD369);
					convolution1_1_n[8] = Grid[14]*$signed(20'h05E68);

					convolution2_1_n[0] = Grid[5]*$signed(20'hFDB55);
					convolution2_1_n[1] = Grid[6]*$signed(20'h02992);
					convolution2_1_n[2] = Grid[7]*$signed(20'hFC994);
					convolution2_1_n[3] = Grid[9]*$signed(20'h050FD);
					convolution2_1_n[4] = Grid[10]*$signed(20'h02F20);
					convolution2_1_n[5] = Grid[11]*$signed(20'h0202D);
					convolution2_1_n[6] = Grid[13]*$signed(20'h03BD7);
					convolution2_1_n[7] = Grid[14]*$signed(20'hFD369);
					convolution2_1_n[8] = Grid[15]*$signed(20'h05E68);

					convolution3_1_n[0] = Grid[8]*$signed(20'hFDB55);
					convolution3_1_n[1] = Grid[9]*$signed(20'h02992);
					convolution3_1_n[2] = Grid[10]*$signed(20'hFC994);
					convolution3_1_n[3] = Grid[12]*$signed(20'h050FD);
					convolution3_1_n[4] = Grid[13]*$signed(20'h02F20);
					convolution3_1_n[5] = Grid[14]*$signed(20'h0202D);
					convolution3_1_n[6] = Grid[0]*$signed(20'h03BD7);
					convolution3_1_n[7] = Grid[1]*$signed(20'hFD369);
					convolution3_1_n[8] = Grid[2]*$signed(20'h05E68);

					convolution4_1_n[0] = Grid[9]*$signed(20'hFDB55);
					convolution4_1_n[1] = Grid[10]*$signed(20'h02992);
					convolution4_1_n[2] = Grid[11]*$signed(20'hFC994);
					convolution4_1_n[3] = Grid[13]*$signed(20'h050FD);
					convolution4_1_n[4] = Grid[14]*$signed(20'h02F20);
					convolution4_1_n[5] = Grid[15]*$signed(20'h0202D);
					convolution4_1_n[6] = Grid[1]*$signed(20'h03BD7);
					convolution4_1_n[7] = Grid[2]*$signed(20'hFD369);
					convolution4_1_n[8] = Grid[3]*$signed(20'h05E68);
				end
			endcase
		end
	
		FOURTH_TYPE:
		begin	
			case(state_calculate)
				CAL_0:
				begin
					convolution1_0_n[0] = Grid[12]*$signed(20'h0A89E);
					convolution1_0_n[1] = Grid[13]*$signed(20'h092D5);
					convolution1_0_n[2] = Grid[14]*$signed(20'h06D43);
					convolution1_0_n[3] = Grid[0]*$signed(20'h01004);
					convolution1_0_n[4] = Grid[1]*$signed(20'hF8F71);
					convolution1_0_n[5] = Grid[2]*$signed(20'hF6E54);
					convolution1_0_n[6] = Grid[4]*$signed(20'hFA6D7);
					convolution1_0_n[7] = Grid[5]*$signed(20'hFC834);
					convolution1_0_n[8] = Grid[6]*$signed(20'hFAC19);

					convolution2_0_n[0] = Grid[13]*$signed(20'h0A89E);
					convolution2_0_n[1] = Grid[14]*$signed(20'h092D5);
					convolution2_0_n[2] = Grid[15]*$signed(20'h06D43);
					convolution2_0_n[3] = Grid[1]*$signed(20'h01004);
					convolution2_0_n[4] = Grid[2]*$signed(20'hF8F71);
					convolution2_0_n[5] = Grid[3]*$signed(20'hF6E54);
					convolution2_0_n[6] = Grid[5]*$signed(20'hFA6D7);
					convolution2_0_n[7] = Grid[6]*$signed(20'hFC834);
					convolution2_0_n[8] = Grid[7]*$signed(20'hFAC19);

					convolution3_0_n[0] = Grid[0]*$signed(20'h0A89E);
					convolution3_0_n[1] = Grid[1]*$signed(20'h092D5);
					convolution3_0_n[2] = Grid[2]*$signed(20'h06D43);
					convolution3_0_n[3] = Grid[4]*$signed(20'h01004);
					convolution3_0_n[4] = Grid[5]*$signed(20'hF8F71);
					convolution3_0_n[5] = Grid[6]*$signed(20'hF6E54);
					convolution3_0_n[6] = Grid[8]*$signed(20'hFA6D7);
					convolution3_0_n[7] = Grid[9]*$signed(20'hFC834);
					convolution3_0_n[8] = Grid[10]*$signed(20'hFAC19);

					convolution4_0_n[0] = Grid[1]*$signed(20'h0A89E);
					convolution4_0_n[1] = Grid[2]*$signed(20'h092D5);
					convolution4_0_n[2] = Grid[3]*$signed(20'h06D43);
					convolution4_0_n[3] = Grid[5]*$signed(20'h01004);
					convolution4_0_n[4] = Grid[6]*$signed(20'hF8F71);
					convolution4_0_n[5] = Grid[7]*$signed(20'hF6E54);
					convolution4_0_n[6] = Grid[9]*$signed(20'hFA6D7);
					convolution4_0_n[7] = Grid[10]*$signed(20'hFC834);
					convolution4_0_n[8] = Grid[11]*$signed(20'hFAC19);

					convolution1_1_n[0] = Grid[12]*$signed(20'hFDB55);
					convolution1_1_n[1] = Grid[13]*$signed(20'h02992);
					convolution1_1_n[2] = Grid[14]*$signed(20'hFC994);
					convolution1_1_n[3] = Grid[0]*$signed(20'h050FD);
					convolution1_1_n[4] = Grid[1]*$signed(20'h02F20);
					convolution1_1_n[5] = Grid[2]*$signed(20'h0202D);
					convolution1_1_n[6] = Grid[4]*$signed(20'h03BD7);
					convolution1_1_n[7] = Grid[5]*$signed(20'hFD369);
					convolution1_1_n[8] = Grid[6]*$signed(20'h05E68);

					convolution2_1_n[0] = Grid[13]*$signed(20'hFDB55);
					convolution2_1_n[1] = Grid[14]*$signed(20'h02992);
					convolution2_1_n[2] = Grid[15]*$signed(20'hFC994);
					convolution2_1_n[3] = Grid[1]*$signed(20'h050FD);
					convolution2_1_n[4] = Grid[2]*$signed(20'h02F20);
					convolution2_1_n[5] = Grid[3]*$signed(20'h0202D);
					convolution2_1_n[6] = Grid[5]*$signed(20'h03BD7);
					convolution2_1_n[7] = Grid[6]*$signed(20'hFD369);
					convolution2_1_n[8] = Grid[7]*$signed(20'h05E68);

					convolution3_1_n[0] = Grid[0]*$signed(20'hFDB55);
					convolution3_1_n[1] = Grid[1]*$signed(20'h02992);
					convolution3_1_n[2] = Grid[2]*$signed(20'hFC994);
					convolution3_1_n[3] = Grid[4]*$signed(20'h050FD);
					convolution3_1_n[4] = Grid[5]*$signed(20'h02F20);
					convolution3_1_n[5] = Grid[6]*$signed(20'h0202D);
					convolution3_1_n[6] = Grid[8]*$signed(20'h03BD7);
					convolution3_1_n[7] = Grid[9]*$signed(20'hFD369);
					convolution3_1_n[8] = Grid[10]*$signed(20'h05E68);

					convolution4_1_n[0] = Grid[1]*$signed(20'hFDB55);
					convolution4_1_n[1] = Grid[2]*$signed(20'h02992);
					convolution4_1_n[2] = Grid[3]*$signed(20'hFC994);
					convolution4_1_n[3] = Grid[5]*$signed(20'h050FD);
					convolution4_1_n[4] = Grid[6]*$signed(20'h02F20);
					convolution4_1_n[5] = Grid[7]*$signed(20'h0202D);
					convolution4_1_n[6] = Grid[9]*$signed(20'h03BD7);
					convolution4_1_n[7] = Grid[10]*$signed(20'hFD369);
					convolution4_1_n[8] = Grid[11]*$signed(20'h05E68);
				end
			endcase
		end
	endcase
end

//For calculate state: update kernel0, kernel1: deal with ouutput of layer0 
always @ (*) begin
state_calculate_n = state_calculate;
column_counter_n = column_counter;
cal_counter_n = cal_counter;
for(i=0;i<16;i=i+1) Grid_n[i] = 0;
for(i=0;i<4;i=i+1) begin
	kernel0_n[i] = kernel0[i];
	kernel1_n[i] = kernel1[i];
end

	case(state_calculate)
		CAL_IDLE:
		begin
			cal_counter_n = cal_counter+4'd1; //initial: need to read 9 blocks before calculatet the first conv 4x4
			if (cal_counter == 4'd9) 
			begin
				state_calculate_n = CAL_LOAD;
			end
		end
		CAL_LOAD: //update Grid data from Table
		begin	
			state_calculate_n = CAL_0;	
			case(state_row)
				FIRSTROW:
				begin
					case(state_column)
						FIRSTCOLUMN:
						begin
							Grid_n[5] = TABLE[0];	
							Grid_n[6] = TABLE[1];	
							Grid_n[7] = TABLE[2];	
							Grid_n[9] = TABLE[64];
							Grid_n[10] = TABLE[65];
							Grid_n[11] = TABLE[66];
							Grid_n[13] = TABLE[128];
							Grid_n[14] = TABLE[129];
							Grid_n[15] = TABLE[130];
						end
						INTERCOLUMN:
						begin
							Grid_n[4] = TABLE[column_counter-8'd1];
							Grid_n[5] = TABLE[column_counter];
							Grid_n[6] = TABLE[column_counter+8'd1];
							Grid_n[7] = TABLE[column_counter+8'd2];
							Grid_n[8] = TABLE[column_counter+8'd63];
							Grid_n[9] = TABLE[column_counter+8'd64];
							Grid_n[10] = TABLE[column_counter+8'd65];
							Grid_n[11] = TABLE[column_counter+8'd66];
							Grid_n[12] = TABLE[column_counter+8'd127];
							Grid_n[13] = TABLE[column_counter+8'd128];
							Grid_n[14] = TABLE[column_counter+8'd129];
							Grid_n[15] = TABLE[column_counter+8'd130];
						end
						LASTCOLUMN:
						begin
							Grid_n[4] = TABLE[61];
							Grid_n[5] = TABLE[62];
							Grid_n[6] = TABLE[63];
							Grid_n[8] = TABLE[125];
							Grid_n[9] = TABLE[126];
							Grid_n[10] = TABLE[127];
							Grid_n[12] = TABLE[189];
							Grid_n[13] = TABLE[190];
							Grid_n[14] = TABLE[191];
						end
					endcase
				end
				INTERROW:
				begin	
					case(state_column)
						FIRSTCOLUMN:
						begin
							Grid_n[1] = TABLE[0];
							Grid_n[2] = TABLE[1];
							Grid_n[3] = TABLE[2];
							Grid_n[5] = TABLE[64];
							Grid_n[6] = TABLE[65];
							Grid_n[7] = TABLE[66];
							Grid_n[9] = TABLE[128];
							Grid_n[10] = TABLE[129];
							Grid_n[11] = TABLE[130];
							Grid_n[13] = TABLE[192];
							Grid_n[14] = TABLE[193];
							Grid_n[15] = TABLE[194];
						end
						INTERCOLUMN:
						begin
							Grid_n[0] = TABLE[column_counter-1];
							Grid_n[1] = TABLE[column_counter];
							Grid_n[2] = TABLE[column_counter+1];
							Grid_n[3] = TABLE[column_counter+2];
							Grid_n[4] = TABLE[column_counter+8'd63];
							Grid_n[5] = TABLE[column_counter+8'd64];
							Grid_n[6] = TABLE[column_counter+8'd65];
							Grid_n[7] = TABLE[column_counter+8'd66];
							Grid_n[8] = TABLE[column_counter+8'd127];
							Grid_n[9] = TABLE[column_counter+8'd128];
							Grid_n[10] = TABLE[column_counter+8'd129];
							Grid_n[11] = TABLE[column_counter+8'd130];
							Grid_n[12] = TABLE[column_counter+8'd191];
							Grid_n[13] = TABLE[column_counter+8'd192];
							Grid_n[14] = TABLE[column_counter+8'd193];
							Grid_n[15] = TABLE[column_counter+8'd194];
						end
						LASTCOLUMN:
						begin
							Grid_n[0] = TABLE[61];
							Grid_n[1] = TABLE[62];
							Grid_n[2] = TABLE[63];
							Grid_n[4] = TABLE[125];
							Grid_n[5] = TABLE[126];
							Grid_n[6] = TABLE[127];
							Grid_n[8] = TABLE[189];
							Grid_n[9] = TABLE[190];
							Grid_n[10] = TABLE[191];
							Grid_n[12] = TABLE[253];
							Grid_n[13] = TABLE[254];
							Grid_n[14] = TABLE[255];
						end
					endcase
				end
				LASTROW:
				begin
					case(state_column)
						FIRSTCOLUMN:
						begin
							Grid_n[5] = TABLE[64];
							Grid_n[6] = TABLE[65];
							Grid_n[7] = TABLE[66];
							Grid_n[9] = TABLE[128];
							Grid_n[10] = TABLE[129];
							Grid_n[11] = TABLE[130];
							Grid_n[13] = TABLE[192];
							Grid_n[14] = TABLE[193];
							Grid_n[15] = TABLE[194];
							// Grid_n[1] = TABLE[64];	
							// Grid_n[2] = TABLE[65];	
							// Grid_n[3] = TABLE[66];	
							// Grid_n[5] = TABLE[128];
							// Grid_n[6] = TABLE[129];
							// Grid_n[7] = TABLE[130];
							// Grid_n[9] = TABLE[192];
							// Grid_n[10] = TABLE[193];
							// Grid_n[11] = TABLE[194];
						end
						INTERCOLUMN:
						begin
							Grid_n[4] = TABLE[column_counter+8'd63];
							Grid_n[5] = TABLE[column_counter+8'd64];
							Grid_n[6] = TABLE[column_counter+8'd65];
							Grid_n[7] = TABLE[column_counter+8'd66];
							Grid_n[8] = TABLE[column_counter+8'd127];
							Grid_n[9] = TABLE[column_counter+8'd128];
							Grid_n[10] = TABLE[column_counter+8'd129];
							Grid_n[11] = TABLE[column_counter+8'd130];
							Grid_n[12] = TABLE[column_counter+8'd191];
							Grid_n[13] = TABLE[column_counter+8'd192];
							Grid_n[14] = TABLE[column_counter+8'd193];
							Grid_n[15] = TABLE[column_counter+8'd194];
						
						end
						LASTCOLUMN:
						begin
							Grid_n[4] = TABLE[125];
							Grid_n[5] = TABLE[126];
							Grid_n[6] = TABLE[127];
							Grid_n[8] = TABLE[189];
							Grid_n[9] = TABLE[190];
							Grid_n[10] = TABLE[191];
							Grid_n[12] = TABLE[253];
							Grid_n[13] = TABLE[254];
							Grid_n[14] = TABLE[255];
						end
					endcase
				end
			endcase
		end
		CAL_0: //product with kernel: do in above comb block
		begin
			state_calculate_n = CAL_1;
		end
		CAL_1: //add all 9 result of product, bias, ReLU, and rounding: maybe can cut pipeline if time-consuming
		begin
			state_calculate_n = CAL_WAIT;
			//for ReLU and rounding
			if(k0_0 > $signed(40'd0))begin //ReLU>0
				if(k0_0[15] == 1) kernel0_n[0] = k0_0[35:16] + (20'd1); //need rounding + 1
				else kernel0_n[0] = k0_0[35:16];
			end
			else begin //ReLU<0
				kernel0_n[0] = 20'd0;
			end
			if(k0_1 >$signed(40'd0))begin
				if(k0_1[15] == 1) kernel0_n[1] = k0_1[35:16] + 20'd1;
				else kernel0_n[1] = k0_1[35:16];
			end
			else begin
				kernel0_n[1] = 20'd0;
			end
			if(k0_2 > $signed(40'd0))begin
				if(k0_2[15] == 1) kernel0_n[2] = k0_2[35:16] + 20'd1;
				else kernel0_n[2] = k0_2[35:16];
			end
			else begin
				kernel0_n[2] = 20'd0;
			end
			if(k0_3 > $signed(40'd0))begin
				if(k0_3[15] == 1) kernel0_n[3] = k0_3[35:16] + 20'd1;
				else kernel0_n[3] = k0_3[35:16];
			end
			else begin
				kernel0_n[3] = 20'd0;
			end
			if(k1_0 > $signed(40'd0))begin
				if(k1_0[15] == 1) kernel1_n[0] = k1_0[35:16] + 20'd1;
				else kernel1_n[0] = k1_0[35:16];
			end
			else begin
				kernel1_n[0] = 20'd0;
			end
			if(k1_1 > $signed(40'd0))begin
				if(k1_1[15] == 1) kernel1_n[1] = k1_1[35:16] + 20'd1;
				else kernel1_n[1] = k1_1[35:16];
			end
			else begin
				kernel1_n[1] = 20'd0;
			end
			if(k1_2 > $signed(40'd0))begin
				if(k1_2[15] == 1) kernel1_n[2] = k1_2[35:16] + 20'd1;
				else kernel1_n[2] = k1_2[35:16];
			end
			else begin
				kernel1_n[2] = 20'd0;
			end
			if(k1_3 > $signed(40'd0))begin
				if(k1_3[15] == 1) kernel1_n[3] = k1_3[35:16] + 20'd1;
				else kernel1_n[3] = k1_3[35:16];
			end 
			else begin
				kernel1_n[3] = 20'd0;
			end
		end
		CAL_WAIT:
		begin
			if(busy == 1'd0) begin
				column_counter_n = 6'd0;
				state_calculate_n = CAL_IDLE;
			end
			else begin
				if(state_output == OUT_LAYER_1_KERNEL_0)
				begin
					column_counter_n = column_counter + 6'd2;
					state_calculate_n = CAL_LOAD;
				end
				else begin
					state_calculate_n = CAL_WAIT;
				end
			end
		end
	endcase
end


//Maxpool block: update interPooling, maxPooling: deal with output of layer1 
always @ (*) begin
	state_maxpool_n = state_maxpool;

	for(i=0; i<2; i=i+1)begin
		interPooling0_n[i] = interPooling0[i];
		interPooling1_n[i] = interPooling1[i];
	end

	maxPooling0_n = maxPooling0;
	maxPooling1_n = maxPooling1;

	case(state_maxpool)
		MAXPOOL_IDLE:
		begin  //after CAL_1; kernel0 kernel1 will be ready
			if(state_calculate == CAL_1) state_maxpool_n = MAXPOOL_FIRST_STEP;			
		end
		MAXPOOL_FIRST_STEP: //upper row comparison and lower row comparison: update interPooling0 interPooling1
		begin	
			state_maxpool_n = MAXPOOL_LAST_STEP;

			if(kernel0[0] > kernel0[1]) interPooling0_n[0] = kernel0[0];
			else interPooling0_n[0] = kernel0[1];
			if(kernel0[2] > kernel0[3]) interPooling0_n[1] = kernel0[2];
			else interPooling0_n[1] = kernel0[3];

			if(kernel1[0] > kernel1[1]) interPooling1_n[0] = kernel1[0];
			else interPooling1_n[0] = kernel1[1];
			if(kernel1[2] > kernel1[3]) interPooling1_n[1] = kernel1[2];
			else interPooling1_n[1] = kernel1[3];
		end
		MAXPOOL_LAST_STEP: //get maxPool result: update maxPooling0 maxPooling1
		begin
			state_maxpool_n = MAXPOOL_IDLE;

			if(interPooling0[0] > interPooling0[1]) maxPooling0_n = interPooling0[0];
			else maxPooling0_n = interPooling0[1];

			if(interPooling1[0] > interPooling1[1]) maxPooling1_n = interPooling1[0];
			else maxPooling1_n = interPooling1[1];
		end
	endcase
end


//output block
//WRONG
always @ (*) begin
	state_output_n = state_output;
	cwr_n = cwr;
	csel_n = csel;
	output_counter_n = output_counter;
	cdata_wr_n = cdata_wr;
	caddr_wr_n = caddr_wr;
	maxpool_counter_n = maxpool_counter;
	flatten_counter_n = flatten_counter;
	out_column_counter_n = out_column_counter;
	case(state_output) 
		OUT_IDLE:
		begin
			if(state_calculate == CAL_WAIT)
			begin
				cwr_n = 1'd1;
				csel_n = 3'b001;
				// modified : output_counter move to layer_2_kernel_1
				cdata_wr_n = kernel0[state_counter];
				caddr_wr_n = output_counter;
				state_output_n = OUT_LAYER_0_KERNEL_0;
			end
		end
		OUT_LAYER_0_KERNEL_0:
		begin
			cwr_n = 1'd1;
			csel_n = 3'b010;
			cdata_wr_n = kernel1[state_counter];
			caddr_wr_n = output_counter;
			state_output_n = OUT_LAYER_0_KERNEL_1;
			case(state_counter)
				COUNTER_0: output_counter_n = output_counter + 12'd1;
				COUNTER_1: output_counter_n = output_counter + 12'd63;
				COUNTER_2: output_counter_n = output_counter + 12'd1;
				COUNTER_3:
				begin
					if (out_column_counter == 5'd31)
					begin
						out_column_counter_n = 5'd0;	
						output_counter_n = output_counter + 12'd1;
					end
					else 
					begin
						out_column_counter_n = out_column_counter + 5'd1;
						output_counter_n = output_counter - 12'd63;
					end
				end
			endcase
		end
		OUT_LAYER_0_KERNEL_1:
		begin
			if (state_counter != COUNTER_0)
			begin
				cwr_n = 1'd1;
				csel_n = 3'b001;
				cdata_wr_n = kernel0[state_counter];
				caddr_wr_n = output_counter;
				state_output_n = OUT_LAYER_0_KERNEL_0;
			end
			else 
			begin
				csel_n = 3'b011;
				state_output_n = OUT_LAYER_1_KERNEL_0;
				cdata_wr_n = maxPooling0;
				caddr_wr_n = maxpool_counter;
			end
		end
		OUT_LAYER_1_KERNEL_0:
		begin
			cwr_n = 1'd1;
			csel_n = 3'b100;
			cdata_wr_n = maxPooling1;
			caddr_wr_n = maxpool_counter;
			state_output_n = OUT_LAYER_1_KERNEL_1;
			maxpool_counter_n = maxpool_counter + 10'd1;
		end
		OUT_LAYER_1_KERNEL_1:
		begin
			cwr_n = 1'd1;
			csel_n = 3'b101;
			cdata_wr_n = maxPooling0;
			caddr_wr_n = flatten_counter;
			state_output_n = OUT_LAYER_2_KERNEL_0;
			flatten_counter_n = flatten_counter + 11'd1;
		end
		OUT_LAYER_2_KERNEL_0:
		begin
			cwr_n = 1'd1;
			csel_n = 3'b101;
			cdata_wr_n = maxPooling1;
			caddr_wr_n = flatten_counter;
			state_output_n = OUT_LAYER_2_KERNEL_1;
			//modified
			flatten_counter_n = flatten_counter + 11'd1;
		end
		OUT_LAYER_2_KERNEL_1:
		begin
			//modified
			if (state_calculate == CAL_WAIT)
			begin
				cwr_n = 1'd1;
				csel_n = 3'b001;
				cdata_wr_n = kernel0[state_counter];
				caddr_wr_n = output_counter;
				state_output_n = OUT_LAYER_0_KERNEL_0;
			end
			else cwr_n = 1'd0;
		end
	endcase
end

//counter state
always @ (*) begin
	state_counter_n = state_counter;

	case(state_counter)
		COUNTER_0:
		begin
			if(state_output == OUT_LAYER_0_KERNEL_0) state_counter_n = COUNTER_1; 
		end
		COUNTER_1:
		begin
			if(state_output == OUT_LAYER_0_KERNEL_0) state_counter_n = COUNTER_2; 
		end
		COUNTER_2:
		begin
			if(state_output == OUT_LAYER_0_KERNEL_0) state_counter_n = COUNTER_3;
		end
		COUNTER_3:
		begin
			if(state_output == OUT_LAYER_0_KERNEL_0) state_counter_n = COUNTER_0;
		end
	endcase
end

//Sequential part
always @(posedge clk or posedge reset) begin
	if (reset) 
	begin
		//IO
		busy <= 1'd0;
		iaddr <= 12'd0;
		cwr <= 1'd0;
		caddr_wr <= 12'd0;
		cdata_wr <= 20'd0;
		csel <= 3'd0;
		//state
		state_process <= 1'd0;
		state_row <= 2'd0;
		state_read <= 3'd0;
		state_conv <= 2'd0;
		state_maxpool <= 2'd0;
		state_column <= 2'd0;
		state_calculate<= 3'd0;
		state_output <= 3'd0;
		state_counter <= 2'd0;

		//table & grid
		for(i=0;i<256;i=i+1) TABLE[i] <= 20'd0;
		for(i=0;i<16;i=i+1) Grid[i] <= 20'd0;
		//counter
		cal_counter <= 5'd0;
		column_counter <= 6'd0;
		row_counter <= 6'd0;
		output_counter <= 12'd0;
		maxpool_counter <= 10'd0;
		flatten_counter <= 11'd0;
		out_column_counter <= 5'd0;

		//reg 
		for(i=0; i<4;i=i+1) kernel0[i] <= 20'd0;
		for(i=0; i<4;i=i+1) kernel1[i] <= 20'd0;
		for(i=0; i<2;i=i+1) interPooling0[i] <= 20'd0;
		for(i=0; i<2;i=i+1) interPooling1[i] <= 20'd0;
		maxPooling0 <= 20'd0;
		maxPooling1 <= 20'd0;
		for(i=0; i<9;i=i+1)begin
			convolution1_0[i] <= 40'd0;
			convolution2_0[i] <= 40'd0;
			convolution3_0[i] <= 40'd0;
			convolution4_0[i] <= 40'd0;
			convolution1_1[i] <= 40'd0;
			convolution2_1[i] <= 40'd0;
			convolution3_1[i] <= 40'd0;
			convolution4_1[i] <= 40'd0;

		end		
	end
	else 
	begin
		busy <= busy_n;
		iaddr <= iaddr_n;
		caddr_wr <= caddr_wr_n;
		cdata_wr <= cdata_wr_n;
		csel <= csel_n;
		cwr <= cwr_n;

		//states
		state_process <= state_process_n;
		state_row <= state_row_n;
		state_read <= state_read_n;
		state_conv <= state_conv_n;
		state_maxpool <= state_maxpool_n;
		state_column <= state_column_n;
		state_calculate <= state_calculate_n;
		state_output <= state_output_n;
		state_counter <= state_counter_n;

		for(i=0;i<256;i=i+1) TABLE[i] <= TABLE_n[i];
		for(i=0;i<16;i=i+1) Grid[i] <= Grid_n[i];

		//counters
		cal_counter <= cal_counter_n;
		column_counter <= column_counter_n;
		row_counter <= row_counter_n;
		output_counter <= output_counter_n;
		maxpool_counter <= maxpool_counter_n;
		flatten_counter <= flatten_counter_n;
		out_column_counter <= out_column_counter_n;

		//reg
		for(i=0; i<4;i=i+1) kernel0[i] <= kernel0_n[i];
		for(i=0; i<4;i=i+1) kernel1[i] <= kernel1_n[i];
		for(i=0; i<2;i=i+1) interPooling0[i] <= interPooling0_n[i];
		for(i=0; i<2;i=i+1) interPooling1[i] <= interPooling1_n[i];
		maxPooling0 <= maxPooling0_n;
		maxPooling1 <= maxPooling1_n;
		for(i=0; i<9;i=i+1)begin
			convolution1_0[i] <= convolution1_0_n[i];
			convolution2_0[i] <= convolution2_0_n[i];
			convolution3_0[i] <= convolution3_0_n[i];
			convolution4_0[i] <= convolution4_0_n[i];
			convolution1_1[i] <= convolution1_1_n[i];
			convolution2_1[i] <= convolution2_1_n[i];
			convolution3_1[i] <= convolution3_1_n[i];
			convolution4_1[i] <= convolution4_1_n[i];

		end		
	end
end



endmodule


