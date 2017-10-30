onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /structure/clock
add wave -noupdate /structure/reset
add wave -noupdate /structure/dout_ready
add wave -noupdate -radix hexadecimal /structure/dout_data
add wave -noupdate /structure/dout_valid
add wave -noupdate /structure/dout_startofpacket
add wave -noupdate /structure/dout_endofpacket
add wave -noupdate -radix hexadecimal /structure/dil/din_data
add wave -noupdate /structure/dil/din_ready
add wave -noupdate /structure/dil/din_valid
add wave -noupdate /structure/dil/din_startofpacket
add wave -noupdate /structure/dil/din_endofpacket
add wave -noupdate -radix decimal /structure/dil/width
add wave -noupdate -radix decimal /structure/dil/half_height
add wave -noupdate -radix decimal /structure/dil/height
add wave -noupdate -radix decimal /structure/dil/num_of_pixel_in_line
add wave -noupdate -radix decimal /structure/dil/num_of_line
add wave -noupdate -radix hexadecimal /structure/dil/mem
add wave -noupdate -radix hexadecimal /structure/dil/ptr_wr
add wave -noupdate -radix hexadecimal /structure/dil/ptr_rd
add wave -noupdate -radix hexadecimal /structure/dil/current_line_ptr
add wave -noupdate /structure/dil/ready_to_send
add wave -noupdate -radix hexadecimal /structure/dil/beat_index
add wave -noupdate -radix hexadecimal /structure/dil/s_beat_index
add wave -noupdate /structure/dil/sink_state
add wave -noupdate /structure/dil/source_state
add wave -noupdate /structure/dil/field_ident
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 235
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {5382 ns} {5749 ns}
