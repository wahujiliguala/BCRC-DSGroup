`timescale 1ns / 1ps

module EEPROM_CTRL(
	input CLK,
	input RESET,
	input RD,
	input WR,
	input [10:0] ADDR,

	output SCL,
	output RD_END,
	output WR_END,
	inout SDA,
	inout [7:0] DATA
	);

reg R_W,scl,hold_n,rd_end,wr_end;
reg [2:0] temp;
reg [7:0] data_in_reg,p2s_buf;
reg [12:0] main_state;

reg link_read;
reg link_0,link_1,link_p2s,link_sda;
wire sda0,sda1,sda_p2s,p2s;
wire p2s_end_signal;
assign sda0 = link_0 ? 0 : 0;
assign sda1 = link_1 ? 1 : 0;
assign sda_p2s = link_p2s ? p2s : 0;
assign SDA = link_sda ? (sda0|sda1|sda_p2s) : 1'bz;
assign DATA = link_read ? data_in_reg : 8'bz;
assign SCL = scl;
assign RD_END = rd_end;
assign WR_END = wr_end;

parameter
Idle 			= 		12'b0000_0000_0001,
Write_Ctrl 		= 		12'b0000_0000_0010,   // Write control signal
ACK_0 			= 		12'b0000_0000_0100,   // Ready to write address
Write_Addr 		= 		12'b0000_0000_1000,   // Write address
ACK_1 			= 		12'b0000_0001_0000,   // Switch to Ctrl_Rd or Write data
Write_Ctrl_Rd 	= 		12'b0000_0010_0000,   // Write read ctrl
Read_Data 		= 		12'b0000_0100_0000,   // Read data from EEPROM unit
Write_Data 		= 		12'b0000_1000_0000,   // Write data to EEPROM
ACK_4 			= 		12'b0001_0000_0000,   // Ready to stop after write data
NO_ACK 			= 		12'b0010_0000_0000,   // Pull up, ready to stop
ACK_5 			= 		12'b0100_0000_0000,   // Ready to read data from EEPROM unit
STOP 			= 		12'b1000_0000_0000;

p2s_8bit p2s_8bit_inst0(.SCL(scl),.CLK(CLK),.hold_n(hold_n),.DATA_IN(p2s_buf),.SDA(p2s),.p2s_end(p2s_end_signal));

always@(posedge CLK or negedge RESET) begin
	if(!RESET) scl = 1'b0;
	else scl = ~scl;
end

always@(posedge CLK or negedge RESET) begin
	if(!RESET) begin
		hold_n <= 1'b0;
		link_0 <= 1'b0;
		link_1 <= 1'b1;				//Pull SDA up
		link_p2s <= 1'b0;
		link_sda <= 1'b1;			//Set SDA as output
		link_read <= 1'b0;
		rd_end <= 1'b0;
		main_state <= Idle;
	end
	else case(main_state)
		Idle: begin
			if(scl) begin
				if(RD) begin
					link_0 <= 1'b1;		// Start signal	
					link_1 <= 1'b0;
					R_W <= 1'b1;		// Read mode
					temp <= 3'b111;
					rd_end <= 1'b0;
					p2s_buf <= {1'b1,1'b0,1'b1,1'b0,ADDR[10:8],1'b0};
					hold_n <= 1'b1;
					main_state <= Write_Ctrl;
				end
				else if(WR) begin
					link_0 <= 1'b1;		// Start signal
					link_1 <= 1'b0;
					R_W <= 1'b0;		// Write mode
					wr_end <= 1'b0;
					p2s_buf <= {1'b1,1'b0,1'b1,1'b0,ADDR[10:8],1'b0};
					hold_n <= 1'b1;
					main_state <= Write_Ctrl;
				end
				else main_state <= Idle;
			end
			else begin
			    link_read <= 1'b0;
			    rd_end <= 1'b0;
			    wr_end <= 1'b0;
			    main_state <= Idle;
			end
		end
		
		Write_Ctrl: begin
			if(!scl) begin
				if(link_p2s != 1'b1) begin
					link_p2s <= 1'b1;
					link_0 <= 1'b0;
				end
			end
			if(scl) begin                    // Check while scl rise
				if(p2s_end_signal != 1'b1) begin
					main_state <= Write_Ctrl;
				end
				else begin
					hold_n <= 1'b0;         // p2s finished, hold
					main_state <= ACK_0;	// Next state is to write 8bit ADDR
					p2s_buf <= ADDR[7:0];   // Dump the address to p2s unit
				end
			end
			else main_state <= Write_Ctrl;
		end

		//Next state is to write 8bit ADDR
		ACK_0: begin
		    if(!scl) begin
              link_p2s <= 1'b0;                     // Unlink p2s unit
              link_sda <= 1'b0;                     // Set SDA as input
		    end
			if(scl) begin
				if(SDA == 1'b0) begin               // Check the ACK signal from EEPROM unit 
					main_state <= Write_Addr;
					hold_n <= 1'b1;                 // Unlock p2s unit, ready to send address
				end
				else main_state <= ACK_0;
			end
			else main_state <= ACK_0;
		end

		Write_Addr: begin
		    if(!scl && link_sda == 1'b0) begin
                link_p2s <= 1'b1;           
                link_sda <= 1'b1;            // Set SDA as output
            end
			if(scl) begin                    // Check while scl rises
				if(p2s_end_signal != 1'b1) begin
					main_state <= Write_Addr;
				end
				else begin
				    hold_n <= 1'b0;
					main_state <= ACK_1;
				end
			end
			else main_state <= Write_Addr;
		end

		//Next state is to READ ctrl or write data
		ACK_1: begin
			if(!scl && link_sda == 1'b1) begin
			    hold_n <= 1'b0;
				link_0 <= 1'b0;
				link_1 <= 1'b0;
				link_p2s <= 1'b0;
				link_sda <= 1'b0;
			end
			if(R_W == 1'b0 && scl && SDA == 1'b0) begin //Ready to write data
				main_state <= Write_Data;
				hold_n <= 1'b1;
				link_0 <= 1'b1;             //Pull down
				link_1 <= 1'b0;
				link_p2s <= 1'b0;
				link_sda <= 1'b1;			//Set SDA as input
				p2s_buf <= DATA;			//DATA output through SDA, link_read remains 0
			end
			if(R_W == 1'b1 && scl && SDA == 1'b0) begin //Ready to write read ctrl
				hold_n <= 1'b0;				//Ready to READ ctrl signal
				link_p2s <= 1'b0;
				link_0 <= 1'b0;
				link_1 <= 1'b1;				//Pull up
				link_sda <= 1'b1;			//Set SDA as output
				main_state <= Write_Ctrl_Rd;
			end
		end

		Write_Data: begin
		    if(!scl && link_0 == 1'b1) begin
		        link_0 <= 1'b0;
		        link_p2s <= 1'b1;
		    end
			if(scl)
				if(p2s_end_signal != 1'b1) main_state <= Write_Data;
				else begin
					hold_n <= 1'b0;
					main_state <= ACK_4;
				end
			else main_state <= Write_Data;
		end

		Write_Ctrl_Rd: begin	
			if(scl && link_1 == 1'b1) begin
				link_1 <= 1'b0;
				link_0 <= 1'b1;
				hold_n <= 1'b1;
				p2s_buf <= {1'b1,1'b0,1'b1,1'b0,ADDR[10:8],1'b1};
				main_state <= Write_Ctrl_Rd;
			end
			if(!scl && link_0 == 1'b1) begin
			    link_0 <= 1'b0;
			    link_p2s <= 1'b1;
			end
			if(hold_n == 1'b1 && scl) begin
                if(p2s_end_signal != 1'b1) main_state <= Write_Ctrl_Rd;
                else main_state <= ACK_5;
            end
            else main_state <= Write_Ctrl_Rd;
		end

		ACK_5: begin
		    if(!scl && link_sda == 1'b1) begin
		        link_p2s <= 1'b0;
                link_sda <= 1'b0;        //Set SDA as input
                hold_n <= 1'b0;
		    end
			if(scl)
				if(SDA == 1'b0) begin
				    main_state <= Read_Data;
				    link_read <= 1'b1;
				end
		        else main_state <= ACK_5;
			else main_state <= ACK_5;
		end

		Read_Data: begin
			if(scl) begin
			    data_in_reg[temp] <= SDA;
				if(temp != 3'b000) main_state <= Read_Data;
				else main_state <= NO_ACK;
				temp <= temp - 1;
			end
			else main_state <= Read_Data;
		end

		//Next state is to STOP
		ACK_4: begin
			if(link_sda == 1'b1) begin
				link_sda <= 1'b0;			//Set SDA as input
				link_p2s <= 1'b0;
			end
			if(scl)
				if(SDA == 1'b0) begin
					main_state <= STOP;
				end
				else main_state <= ACK_4;
			else main_state <= ACK_4;
		end

		NO_ACK: begin
			if(scl)
				if(SDA == 1'b1) main_state <= STOP;
				else main_state <= NO_ACK;
			else main_state <= NO_ACK;
		end

		STOP: begin
			if(!scl && link_sda == 1'b0) begin
				link_1 <= 1'b0;
				link_0 <= 1'b1;
				link_sda <= 1'b1;
			end
			if(scl) begin
				link_0 <= 1'b0;
				link_1 <= 1'b1;
				link_sda <= 1'b1;
			end
			if(!scl && link_1 == 1'b1) begin
			    if(R_W == 1'b1) rd_end <= 1'b1;
			    else wr_end <= 1'b1;
			    main_state <= Idle;
			end
		end
		default: main_state <= Idle;
		
	endcase
end

endmodule:EEPROM_CTRL