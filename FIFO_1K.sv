`timescale 1ns/1ns
`define MAX_SIZE 640

module FIFO_1K (
	reset,
	clock,

	rd_req,
	q,
	wr_req,
	data,
	full,
	dt_read /* 	00 - one read to ~full status, 
				01 - two reads for ~full status, 
				10 - three reads for ~full status, 
				11 - forbidden*/
);

input logic reset;
input logic clock;
input logic rd_req;
output logic [7:0] q;
input logic wr_req;
output logic [7:0] data;
output logic full;
input logic dt_read;

logic [9:0] head, tail;
logic inner_full;
logic [7:0] pre_q;
logic d, dd;

RAM_1K	RAM_1K_inst (
	.clock ( clock ),
	.data ( data ),
	.rdaddress ( tail ),
	.wraddress ( head ),
	.wren ( wr_req ),
	.q ( pre_q )
);

assign full = inner_full;
assign q = pre_q;

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
		head <= 0;
		tail <= 0;
		inner_full <= 0;
		d <= 0;
		dd <= 0;
	end else begin
		if (~inner_full) begin 
			if (head == `MAX_SIZE-1) begin 
				inner_full <= 1;
				head <= 0;
			end else if (wr_req) begin 
				head <= head + 1;
			end
			d <= 0;
			dd <= 0;
		end else begin 
			if (tail == `MAX_SIZE-1) begin 
				if (dt_read == 2'b00 || dt_read == 2'b11) begin
					inner_full <= 0;
				end else if (dt_read == 2'b01) begin
					d <= 1;
					if (d) begin
						inner_full <= 0;
					end
				end else if (dt_read == 2'b10) begin 
					d <= 1;
					if (d) begin
						dd <= 1;
					end
					if (dd) begin
						inner_full <= 0;
					end
				end
				tail <= 0;
			end else if (rd_req) begin 
				tail <= tail + 1;
			end
		end
	end
end

endmodule // FIFO_1K