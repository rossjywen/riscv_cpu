# Run in the Vivado Tcl Console with the Arty A7-100T project open:
#   source /path/to/riscv_cpu/scripts/create_clocking_wizard.tcl
# Generated IP files stay in the Vivado project, outside the portable SoC RTL.
if {[current_project -quiet] eq ""} {
    error "Open the Arty A7 Vivado project before sourcing this script."
}

set cpu_repo_dir [file normalize [file join [file dirname [info script]] ..]]
set clock_ip [get_ips -quiet clk_wiz_0]
if {[llength $clock_ip] == 0} {
    set clock_ip_dir [file join [get_property DIRECTORY [current_project]] ip]
    file mkdir $clock_ip_dir
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
        -module_name clk_wiz_0 -dir $clock_ip_dir
    set clock_ip [get_ips clk_wiz_0]
    set_property -dict [list \
        CONFIG.PRIMITIVE {MMCM} \
        CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.NUM_OUT_CLKS {1} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {80.000} \
        CONFIG.CLKOUT1_REQUESTED_PHASE {0.000} \
        CONFIG.CLKOUT1_REQUESTED_DUTY_CYCLE {50.000} \
        CONFIG.PRIMARY_PORT {clk_in1} \
        CONFIG.CLK_OUT1_PORT {clk_out1} \
        CONFIG.USE_RESET {true} \
        CONFIG.RESET_TYPE {ACTIVE_LOW} \
        CONFIG.RESET_PORT {resetn} \
        CONFIG.USE_LOCKED {true} \
        CONFIG.LOCKED_PORT {locked} \
    ] $clock_ip
} else {
    # Reuse the user's generated IP without changing its configuration.
    foreach {setting expected} {
        CONFIG.PRIMARY_PORT clk_in1
        CONFIG.CLK_OUT1_PORT clk_out1
        CONFIG.RESET_PORT resetn
        CONFIG.RESET_TYPE ACTIVE_LOW
        CONFIG.LOCKED_PORT locked
    } {
        if {[get_property $setting $clock_ip] ne $expected} {
            error "Existing clk_wiz_0 needs $setting=$expected for arty_a7_top; IP was not reconfigured."
        }
    }
    if {![get_property CONFIG.USE_RESET $clock_ip] ||
        ![get_property CONFIG.USE_LOCKED $clock_ip] ||
        [get_property CONFIG.NUM_OUT_CLKS $clock_ip] != 1 ||
        abs([get_property CONFIG.PRIM_IN_FREQ $clock_ip] - 100.0) > 0.001 ||
        abs([get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $clock_ip] - 80.0) > 0.001} {
        error "Existing clk_wiz_0 must provide 100 MHz input, one 80 MHz output, resetn and locked; IP was not reconfigured."
    }
}
generate_target all $clock_ip

# Register the board wrapper, retaining the existing project sources/constraints.
set wrapper_file [file join $cpu_repo_dir rtl arty_a7_top.v]
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse $wrapper_file
}
set_property top arty_a7_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Clocking Wizard configured: 100 MHz input, 80 MHz output; top = arty_a7_top."
