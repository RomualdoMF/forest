// This module defined the basecall model from the analysis and allows to
// override it, if the user asks so.

workflow detect_basecall_model {
    take:
        bam_channel
        basecall_models_data
    main:
        // Add basecall model to the bam channel
        bam_channel = bam_channel
            | map{ xam, xai, meta -> [meta, xam, xai] }
            | combine( basecall_models_data, by:0 )
            | map{
                meta, xam, xai, bc ->
                def models = bc.splitText().collect { it.strip() }
                [xam, xai, meta + [basecall_models: models]]
            }

        // attempt to pull out basecaller_cfg from metadata, keeping unique values
        metamap_basecaller_cfg = bam_channel
            | map { xam, bai, meta ->
                meta["basecall_models"]
            }
            | flatten  // squash lists
            | unique

        // Ensure that all BAMs in the bam_channel have the same basecaller configuration.
        // If the bam_channel is empty (ie. no pass BAMs), no messages or errors will occur.
        metamap_basecaller_cfg
                | count
                | combine(bam_channel | count)
                | map { int n_models, int n_bams ->
                    if (n_bams == 0) {
                        // emit a debug warning but don't halt: this may be OK
                        // we'll worry about this in the relevant workflows main.nf if it is fatal
                        log.warn "There were no valid input files from which to read a basecaller model, your input data likely has insufficient coverage for analysis."
                    } else if (n_models == 0){
                        if (params.override_basecaller_cfg) {
                            log.info "No basecaller models found in the input alignment header, falling back to the model provided with --override_basecaller_cfg: ${params.override_basecaller_cfg}"
                        }
                        else {
                            String input_data_err_msg = """\
                            ################################################################################
                            # INPUT DATA PROBLEM
                            Your input alignments does not indicate the basecall model in the header and
                            you did not provide an alternative with --override_basecaller_cfg.

                            ${workflow.manifest.name} requires the basecall model in order to
                            automatically select an appropriate calling model for analysis.

                            ## Next steps
                            You must re-run the workflow specifying the basecaller model with the
                            --override_basecaller_cfg option.
                            ################################################################################
                            """.stripIndent()
                            error input_data_err_msg
                        }
                    } else if (n_models > 1){
                        if (params.override_basecaller_cfg){
                            String input_data_warn_msg = """\
                            ################################################################################
                            Your input BAM file(s) indicate two or more different basecall models in the
                            header.

                            ${workflow.manifest.name} input BAM(s) should be basecalled with a one
                            model.

                            The workflow will proceed with the model provided by `--override_basecaller_cfg`.
                            ################################################################################
                            """.stripIndent()
                            log.info input_data_warn_msg
                        } else {
                            String input_data_err_msg = """\
                            ################################################################################
                            # INPUT DATA PROBLEM
                            Your input BAM file(s) indicate two or more different basecall models in the
                            header.

                            ${workflow.manifest.name} requires the basecall model in order to
                            automatically select an appropriate calling model for analysis. Multiple
                            basecall models are ambiguous and an appropriate calling model cannot be
                            selected automatically.

                            ## Next steps
                            Your input data should be re-basecalled with a single basecall model.
                            Alternatively, you may select an appropriate basecall model with the
                            --override_basecaller_cfg option, but the workflow may produce
                            unexpected results.
                            ################################################################################
                            """.stripIndent()
                            error input_data_err_msg
                        }
                    }
                }
        
        if (params.override_basecaller_cfg) {
            metamap_basecaller_cfg
                .subscribe onNext: {log.info "Detected basecaller_model: ${it}"}, onComplete: {log.warn "Overriding basecaller_model: ${params.override_basecaller_cfg}"}
            basecaller_cfg = Channel.of(params.override_basecaller_cfg)
            // Update override basecall model in meta
            bam_channel = bam_channel
            | map{
                xam, xai, meta ->
                [xam, xai, meta + [basecall_models: [params.override_basecaller_cfg]]]
            }
        }
        else {
            basecaller_cfg = metamap_basecaller_cfg
                | map { log.info "Detected basecaller_model: ${it}"; it }
                | ifEmpty(params.override_basecaller_cfg)
                | map { log.info "Using basecaller_model: ${it}"; it }
                | first  // unpack from list
        }

    emit:
        bam_channel = bam_channel
        basecaller_cfg = basecaller_cfg

}
