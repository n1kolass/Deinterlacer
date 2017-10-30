`timescale 1ns/1ns

module sum_div2 (
	a,
	b,
	out
);

parameter WIDTH = 24;

input logic [WIDTH-1:0] a,b;
output logic [WIDTH-1:0] out;

logic [WIDTH:0] sum;

assign out = sum[WIDTH:1];

always_comb begin
	sum = a + b;
end

endmodule