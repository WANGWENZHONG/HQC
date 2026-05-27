set hqc_root [file normalize [file join [file dirname [info script]] ../..]]
set accel_dir [file join $hqc_root rtl hqc_accel]

set accel_sources {
    hqc_crc16_ccitt.v
    hqc_sync_fifo.v
    hqc_security.v
    hqc_buffer_ram.v
    hqc_axi4lite_regs.v
    hqc_spi_slave.v
    hqc_uart.v
    hqc_cmd_frame_rx.v
    hqc_resp_frame_tx.v
    hqc_pack_engine.v
    hqc_kem_scheduler.v
    hqc_rng_sampler_cluster.v
    hqc_accel_top.v
}

foreach src $accel_sources {
    add_files -norecurse [file join $accel_dir $src]
}

add_files -norecurse [file join $hqc_root "HQC_weight_sampler&shake_rng_rtl" hqc_keccak_f1600_core.v]
add_files -norecurse [file join $hqc_root "HQC_weight_sampler&shake_rng_rtl" hqc_shake_rng.v]
add_files -norecurse [file join $hqc_root "HQC_weight_sampler&shake_rng_rtl" hqc_fixed_weight_sampler.v]

set rsrm_dir [file join $hqc_root "HQC_RS_RM_vector(1)" HQC_RS_RM_vector]
add_files -norecurse [file join $rsrm_dir vector_mul vector_multi.v]
add_files -norecurse [file join $rsrm_dir vector_mul vector_multi_top.v]
add_files -norecurse [file join $rsrm_dir Encode RM_encode.v]
add_files -norecurse [file join $rsrm_dir Encode RS_encode.v]
add_files -norecurse [file join $rsrm_dir Encode HQC_encode_top.v]
add_files -norecurse [file join $rsrm_dir gf_mul gf_mul_pipline_4.v]
add_files -norecurse [file join $rsrm_dir gf_mul gf_mul_pipline_8.v]
add_files -norecurse [file join $rsrm_dir Decode HQC_decode_top.v]
add_files -norecurse [file join $rsrm_dir Decode RM_decode RM_decode_top.v]
add_files -norecurse [file join $rsrm_dir Decode RM_decode RM_decode_sum.v]
add_files -norecurse [file join $rsrm_dir Decode RM_decode RM_HA_top.v]
add_files -norecurse [file join $rsrm_dir Decode RM_decode ha_layer.v]
add_files -norecurse [file join $rsrm_dir Decode RM_decode peak_detect.v]
add_files -norecurse [file join $rsrm_dir Decode RS_decode RS_decode_top.v]
add_files -norecurse [file join $rsrm_dir Decode RS_decode RS_syndrome.v]
add_files -norecurse [file join $rsrm_dir Decode RS_decode RS_ePIMBA.v]
add_files -norecurse [file join $rsrm_dir Decode RS_decode RS_error_ca.v]

set_property top hqc_accel_top [current_fileset]
